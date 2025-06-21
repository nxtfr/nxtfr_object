-module(nxtfr_example_object).
-author("christian@flodihn.se").

-export([
    start/2,
    stop/2,
    on_event/3,
    on_request/3,
    tick/2,
    tick/3
]).

start(Uid, ObjectState) ->
    io:format("~p: Starting object with state: ~p~n", [Uid, ObjectState]),
    {ok, ObjectState}.

stop(Uid, ObjectState) ->
    io:format("~p: Stopping object with state: ~p~n", [Uid, ObjectState]),
    ok.

on_event(Uid, Event, ObjectState) ->
    io:format("~p: Received event: ~p~n", [Uid, Event]),
    {ok, ObjectState}.

on_request(Uid, Request, ObjectState) ->
    io:format("~p: Received request: ~p~n", [Uid, Request]),
    {ok, response, ObjectState}.

tick(Uid, DeltaTime) ->
    io:format("~p: Ticking with delta time: ~p ms~n", [Uid, DeltaTime]),
    ok.

tick(Uid, DeltaTime, ObjectState) ->
    io:format("~p: Ticking with delta time: ~p ms and state: ~p~n", [Uid, DeltaTime, ObjectState]),
    {ok, ObjectState}.
