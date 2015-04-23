-module(dtimer).
-include("dtimer.hrl").
-include_lib("riak_core/include/riak_core_vnode.hrl").

-export([
         ping/0,
	 add_timer/2,
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

add_timer(Name, Interval) when is_binary(Name), is_integer(Interval), Interval > 0 ->
	replicated({<<"timer">>, Name}, {add_timer, Name, Interval}).

replicated(Value) -> replicated(Value, Value).
replicated(Value, Key) ->
	N = 2,
	W = 2,
	TimeOut = 10000,
	
	{ok, ReqId} = dtimer_op_fsm:op(N, W, Value, Key),
	receive 
		{ReqId, Val} -> {ok, Val}
	after TimeOut -> {error, timeout}
	end.


find_primary(Key) ->
    DocIdx = riak_core_util:chash_key(Key),
    PrefList = riak_core_apl:get_primary_apl(DocIdx, 1, dtimer),
    [{IndexNode, _Type}] = PrefList,
    {ok, IndexNode}.
