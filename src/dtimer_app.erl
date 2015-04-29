-module(dtimer_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
	case dtimer_sup:start_link() of
		{ok, Pid} ->
			ok = hackney_pool:start_pool(dtimer, [{pool_size, 512 * erlang:system_info(schedulers)}]),

			ok = riak_core:register([{vnode_module, dtimer_vnode}]),

			ok = riak_core_ring_events:add_guarded_handler(dtimer_ring_event_handler, []),
			ok = riak_core_node_watcher_events:add_guarded_handler(dtimer_node_event_handler, []),
			ok = riak_core_node_watcher:service_up(dtimer, self()),

			{ok, Pid};
		{error, Reason} ->
			{error, Reason}
	end.

stop(_State) ->
	ok.
