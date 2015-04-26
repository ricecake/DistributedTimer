-module(dtimer_watchbin).

-export([
	new/1,
	add/3,
	add/4,
	tick/3
]).

%get time in seconds
%add interval
%max now+5, 5*round(next/5)
%set timer if not exists
%add key to list for timer

new(BucketSize) -> {watchbin, BucketSize, maps:new()}.

add(Struct, Interval, Value) -> add(Struct, Interval, Value, false).
add({watchbin, BucketSize, Map}, Interval, Value, Jitter) ->
	WaitTime = if
		Jitter -> random:uniform(Interval);
		not Jitter -> Interval
	end,
	Now = timestamp(),
	Timeout = max(Now+BucketSize, BucketSize*round((Now+WaitTime)/BucketSize)),
	NewValue = case maps:find(Timeout, Map) of
		{ok, List} when is_list(List) ->
					[{Interval, Value}| List];
		error                         ->
					erlang:send_after(timer:seconds(WaitTime), self(), {tick, Timeout}),
					[{Interval, Value}]
	end,
	{ok, {watchbin, BucketSize, maps:put(Timeout, NewValue, Map)}}.

tick({watchbin, BucketSize, Map}, Key, CallBack) ->
	lists:foldl(fun({Int, Data}, Struct) ->
		CallBack(Data),
		add(Struct, Int, Data)
	end, {watchbin, BucketSize, maps:remove(Key, Map)}, maps:get(Key, Map)).

timestamp() -> 
	{Mega, Secs, _} = os:timestamp(),
	Mega*1000*1000 + Secs.

