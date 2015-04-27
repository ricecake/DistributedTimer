-module(dtimer_vnode).
-behaviour(riak_core_vnode).

-include_lib("riak_core/include/riak_core_vnode.hrl").
-include("dtimer.hrl").

-export([start_vnode/1,
         init/1,
         terminate/2,
         handle_command/3,
         is_empty/1,
         delete/1,
         handle_handoff_command/3,
         handoff_starting/2,
         handoff_cancelled/1,
         handoff_finished/2,
         handle_handoff_data/2,
         encode_handoff_item/2,
         handle_coverage/4,
         handle_exit/3,
	 handle_info/2]).

-ignore_xref([
             start_vnode/1
             ]).

-record(state, {partition, db, file, time}).

%% API
start_vnode(I) ->
    riak_core_vnode_master:get_vnode_pid(I, ?MODULE).

init([Partition]) ->
	FileName = filename:join(["dtimer_data", integer_to_list(Partition)]),
	ok = filelib:ensure_dir(FileName),
	{ok, Ref} = eleveldb:open(FileName, [{create_if_missing, true}, {compression, true}, {use_bloomfilter, true}]),
	hackney_pool:start_pool(Partition, [{pool_size, 2 * erlang:system_info(schedulers)}]),
	Timer = dtimer_watchbin:new(1000),
	FilledTimer = eleveldb:fold(Ref, fun({_, Value}, WatchBin) -> 
		{Name, Interval} = binary_to_term(Value),
		{ok, NewTimer} = dtimer_watchbin:add(WatchBin, Interval, Name, true),
		NewTimer
	end, Timer, []),
	{ok, #state { partition=Partition, db=Ref, file=FileName, time=FilledTimer }}.

%% Sample command: respond to a ping
handle_command(ping, _Sender, State) ->
	{reply, {pong, State#state.partition}, State};
handle_command({RefId, {add_timer, Name, Interval}}, _Sender, #state{db = Db, time=Timer} = State) ->
	ok = store(Db, Name, {Name, Interval}),
	{ok, NewTimer} = dtimer_watchbin:add(Timer, Interval, Name, true),
	{reply, {RefId, {added, State#state.partition}}, State#state{time=NewTimer}};
handle_command(Message, _Sender, State) ->
    ?PRINT({unhandled_command, Message}),
    {noreply, State}.

handle_info({tick, TimeOut}, #state{db = Db, partition=Partition, time=Timer} = State) ->
	CallBack = fun(Name) ->
		{ok, {Name, _Interval}} = fetch(Db, Name),
		{ok, Primary} = dtimer:find_primary({<<"timer">>, Name}),
		ThisVnode = {Partition, node()},
		ok = case Primary of
			ThisVnode  -> dtimer_checker:run(Partition, head, []);
			_OtherVnode -> ok
		end
	end,
	{ok, NewTimer} = dtimer_watchbin:tick(Timer, TimeOut, CallBack),
	{ok, State#state{time=NewTimer}};
handle_info(Info, State) ->
	?PRINT({unhandled_message, Info}),
	{ok, State}.

handle_handoff_command(?FOLD_REQ{foldfun=Fun, acc0=Acc0}, _Sender, #state{db=Db} = State) ->
	{reply, eleveldb:fold(Db, Fun, Acc0, []), State};
handle_handoff_command(_Message, _Sender, State) ->
    {noreply, State}.

handoff_starting(_TargetNode, State) ->
    {true, State}.

handoff_cancelled(State) ->
    {ok, State}.

handoff_finished(_TargetNode, State) ->
    {ok, State}.

handle_handoff_data(BinData, #state{db=Db, time=Timer} = State) ->
	{_Key, Value} = binary_to_term(BinData),
	{Name, Interval} = binary_to_term(Value),
	ok = store(Db, Name, {Name, Interval}),
	{ok, NewTimer} = dtimer_watchbin:add(Timer, Interval, Name, true),
	{reply, ok, State#state{time=NewTimer}}.

encode_handoff_item(Key, Value) ->
	term_to_binary({Key, Value}).

is_empty(#state{db=Db} = State) -> {eleveldb:is_empty(Db), State}.

delete(State) ->
	eleveldb:close(State#state.db),
	case eleveldb:destroy(State#state.file, []) of
		ok ->
			{ok, State#state{db = undefined}};
		{error, Reason} ->
			{error, Reason, State}
	end.

handle_coverage(_Req, _KeySpaces, _Sender, State) ->
    {stop, not_implemented, State}.

handle_exit(_Pid, _Reason, State) ->
    {noreply, State}.

terminate(_Reason, #state{db=Db, partition=Partition}) ->
	case Db of
		undefined -> ok;
		_         ->
			eleveldb:close(Db)
	end,
	hackney_pool:stop_pool(Partition),
	ok.

store(Db, Key, Value) -> eleveldb:put(Db, term_to_binary(Key), term_to_binary(Value), []).
fetch(Db, Key)        ->
        case eleveldb:get(Db, term_to_binary(Key), []) of
                {ok, BinaryTerm} -> {ok, binary_to_term(BinaryTerm)};
                not_found        -> throw({not_found, Key})
        end.

exists(Db, Key) ->
        case eleveldb:get(Db, term_to_binary(Key), []) of
                {ok, _BinaryTerm}  -> true;
                not_found         -> false
        end.

getIfExists(Db, Key) ->
        case eleveldb:get(Db, term_to_binary(Key), []) of
                {ok, BinaryTerm} -> {ok, binary_to_term(BinaryTerm)};
                not_found         -> false
        end.

delete(Db, Key) ->
        eleveldb:delete(Db, term_to_binary(Key), []).

