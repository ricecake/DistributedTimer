-module(dtimer_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init(_Args) ->
	VMaster = { dtimer_vnode_master,
        		{riak_core_vnode_master, start_link, [dtimer_vnode]},
			permanent, 5000, worker, [riak_core_vnode_master]},
	CoverageFSMs = {dtimer_coverage_fsm_sup,
			{dtimer_coverage_fsm_sup, start_link, []},
			permanent, infinity, supervisor, [dtimer_coverage_fsm_sup]},
	OpFSMs = {dtimer_op_fsm_sup,
			{dtimer_op_fsm_sup, start_link, []},
			permanent, infinity, supervisor, [dtimer_op_fsm_sup]},
	CheckSup = {dtimer_checker_sup,
			{dtimer_checker_sup, start_link, []},
			permanent, infinity, supervisor, [dtimer_checker_sup]},


    { ok,
        { {one_for_one, 5, 10},
          [VMaster, CoverageFSMs, OpFSMs, CheckSup]}}.
