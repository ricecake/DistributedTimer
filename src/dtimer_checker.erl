-module(dtimer_checker).

-export([
	run/3,
	start_link/3,
	process/3
]).

run(Partition, Type, Args) ->
	{ok, _} = supervisor:start_child(dtimer_checker_sup, [Partition, Type, Args]),
	ok.

start_link(Partition, Type, Args) ->
	{ok, erlang:spawn_link(?MODULE, process, [Partition, Type, Args])}.

process(Pool, head, _Args) ->
	hackney:head("fwb.tfm.nu", [], <<>>, [{pool, Pool}]),
	exit(normal).
