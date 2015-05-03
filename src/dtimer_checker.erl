-module(dtimer_checker).

-export([
	run/2,
	start_link/2,
	process/2
]).

run(Type, Args) ->
	{ok, _} = supervisor:start_child(dtimer_checker_sup, [Type, Args]),
	ok.

start_link(Type, Args) ->
	{ok, erlang:spawn_link(?MODULE, process, [Type, Args])}.

process(head, _Args) ->
	hackney:head("localhost", [], <<>>, [{pool, dtimer}]).
