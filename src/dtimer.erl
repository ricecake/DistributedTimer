-module(dtimer).
-include("dtimer.hrl").
-include_lib("riak_core/include/riak_core_vnode.hrl").

-export([
         ping/0,
	 add_timer/3,
	 remove_timer/1,
         find_primary/1
        ]).

-ignore_xref([
              ping/0
             ]).

%% Public API

%% @doc Pings a random vnode to make sure communication is functional
ping() ->
	{ok, IndexNode} = find_primary({<<"ping">>, term_to_binary(now())}),
	riak_core_vnode_master:sync_spawn_command(IndexNode, ping, dtimer_vnode_master).

add_timer(Name, Interval, Data) when is_binary(Name), is_integer(Interval), Interval > 0, is_map(Data) ->
	replicated({add_timer, Name, Interval, Data}, {<<"timer">>, Name}).

remove_timer(Name) when is_binary(Name) ->
	replicated({remove_timer, Name}, {<<"timer">>, Name}).

replicated(Value) -> replicated(Value, Value).
replicated(Value, Key) ->
	{N, W} = getReplication(),
	TimeOut = timeout(),
	
	{ok, ReqId} = dtimer_op_fsm:op(N, W, Value, Key),
	receive 
		{ReqId, Val} -> {ok, Val}
	after TimeOut -> {error, timeout}
	end.


find_primary(Key) ->
	{N, _} = getReplication(),
	DocIdx = riak_core_util:chash_key(Key),
	[Primary |Secondaries] = riak_core_apl:get_apl(DocIdx, N, dtimer),
	{ok, Primary, Secondaries}.

getReplication() -> {3, 2}.
timeout() -> 5000.
