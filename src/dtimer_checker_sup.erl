-module(dtimer_checker_sup).

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
	Checker= { dtimer_checker,
        		{dtimer_checker, start_link, []},
			temporary, 5000, worker, [dtimer_checker]},
    { ok,
        { {simple_one_for_one, 5, 10},
          [Checker]}}.
