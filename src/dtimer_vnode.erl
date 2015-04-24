-module(dtimer_vnode).
-behaviour(riak_core_vnode).
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

-record(state, {partition, db, file}).

%% API
start_vnode(I) ->
    riak_core_vnode_master:get_vnode_pid(I, ?MODULE).

init([Partition]) ->
	FileName = filename:join(["dtimer_data", integer_to_list(Partition)]),
	ok = del_dir(FileName),
	ok = filelib:ensure_dir(FileName),
	{ok, Ref} = eleveldb:open(FileName, [{create_if_missing, true}, {compression, true}, {use_bloomfilter, true}]),
	{ok, #state { partition=Partition, db=Ref, file=FileName }}.

%% Sample command: respond to a ping
handle_command(ping, _Sender, State) ->
	{reply, {pong, State#state.partition}, State};
handle_command({RefId, {add_timer, Name, Interval}}, _Sender, #state{db = Db} = State) ->
	ok = store(Db, Name, {Name, Interval}),
	WaitTime = random:uniform(Interval),
	erlang:send_after(WaitTime, self(), {tick, Name}),
	{reply, {RefId, {added, State#state.partition}}, State};
handle_command(Message, _Sender, State) ->
    ?PRINT({unhandled_command, Message}),
    {noreply, State}.

handle_info({tick, Name}, #state{db = Db, partition=Partition } = State) ->
%	?PRINT({ticked, Id, Name}),
	{ok, {Name, Interval}} = fetch(Db, Name),
	erlang:send_after(Interval, self(), {tick, Name}),
	{ok, Primary} = dtimer:find_primary({<<"timer">>, Name}),
	ThisVnode = {Partition, node()},
	case Primary of
		ThisVnode  -> io:format("~p~n", [{primary, Name}]);
		OtherVnode -> io:format("~p~n", [{secondary, Name, OtherVnode}])
	end,
	{ok, State};
handle_info(Info, State) ->
	?PRINT({unhandled_message, Info}),
	{ok, State}.

handle_handoff_command(_Message, _Sender, State) ->
    {noreply, State}.

handoff_starting(_TargetNode, State) ->
    {true, State}.

handoff_cancelled(State) ->
    {ok, State}.

handoff_finished(_TargetNode, State) ->
    {ok, State}.

handle_handoff_data(_Data, State) ->
    {reply, ok, State}.

encode_handoff_item(_ObjectName, _ObjectValue) ->
    <<>>.

is_empty(State) ->
    {true, State}.

delete(State) ->
	ok = del_dir(State#state.file),
	{ok, State}.

handle_coverage(_Req, _KeySpaces, _Sender, State) ->
    {stop, not_implemented, State}.

handle_exit(_Pid, _Reason, State) ->
    {noreply, State}.

terminate(Reason, _State) ->
	?PRINT(Reason),
	ok.

del_dir(Dir) ->
	case filelib:is_dir(Dir) of
		true -> lists:foreach(fun(D) ->
				ok = file:del_dir(D)
			end, del_all_files([Dir], []));
		false -> ok
	end.
 
del_all_files([], EmptyDirs) ->
   EmptyDirs;
del_all_files([Dir | T], EmptyDirs) ->
   {ok, FilesInDir} = file:list_dir(Dir),
   {Files, Dirs} = lists:foldl(fun(F, {Fs, Ds}) ->
                                  Path = Dir ++ "/" ++ F,
                                  case filelib:is_dir(Path) of
                                     true ->
                                          {Fs, [Path | Ds]};
                                     false ->
                                          {[Path | Fs], Ds}
                                  end
                               end, {[],[]}, FilesInDir),
   lists:foreach(fun(F) ->
                         ok = file:delete(F)
                 end, Files),
   del_all_files(T ++ Dirs, [Dir | EmptyDirs]).

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
