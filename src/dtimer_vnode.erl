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
	FileName = filename:join(["dtimer_data", integer_to_list(Partition), "main.sqlite"]),
	ok = filelib:ensure_dir(FileName),
	{ok, Pid} = sqlite3:open(anonymous, [{file, FileName }]),
	ok = sqlite3:create_table(Pid, timer, [
		{id, integer, [{primary_key, [asc, autoincrement]}]},
		{name, blob, [not_null]}, 
		{interval, integer, [not_null]}
	]),
	{ok, #state { partition=Partition, db=Pid, file=FileName }}.

%% Sample command: respond to a ping
handle_command(ping, _Sender, State) ->
	{reply, {pong, State#state.partition}, State};
handle_command({add_timer, Name, Interval}, _Sender, #state{db = Db} = State) ->
	{rowid, Id} = sqlite3:write(Db, timer, [{name, Name}, {interval, Interval}]),
	erlang:send_after(Interval, self(), {tick, {Id, Name}}),
	{reply, {added, State#state.partition}, State};
handle_command(Message, _Sender, State) ->
    ?PRINT({unhandled_command, Message}),
    {noreply, State}.

handle_info({tick, {Id, Name}}, #state{db = Db, partition=Partition } = State) ->
	?PRINT({ticked, Id, Name}),
	[{columns, _}, {rows, [{Id, Name, Interval}]}] = sqlite3:read(Db, timer, {id, Id}),
	erlang:send_after(Interval, self(), {tick, {Id, Name}}),
	{ok, Primary} = dtimer:find_primary({timer, Name}),
	ThisVnode = {Partition, node()},
	case Primary of
		ThisVnode  -> ?PRINT({primary, Name});
		OtherVnode -> ?PRINT({secondary, Name, OtherVnode})
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
	ok = file:delete(State#state.file),
	ok = file:delete_dir(filename:join(["dtimer_data", integer_to_list(State#state.partition)])),
	{ok, State}.

handle_coverage(_Req, _KeySpaces, _Sender, State) ->
    {stop, not_implemented, State}.

handle_exit(_Pid, _Reason, State) ->
    {noreply, State}.

terminate(normal, State) ->
	file:delete(State#state.file);
terminate(Reason, _State) ->
	?PRINT(Reason),
	ok.
