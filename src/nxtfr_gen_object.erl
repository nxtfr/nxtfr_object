%%%-------------------------------------------------------------------
%% @doc nxtfr_gen_object active object behaviour.
%% @end
%%%-------------------------------------------------------------------

-module(nxtfr_gen_object).
-author("christian@flodihn.se").

%% Behaviour exports
-export([
    start_link/5,
    stop/1
    ]).

%% Interal exports
-export([
    loop/5,
    loop/6,
    tick/5]).

-callback start_link(Uid :: binary(), CallbackModule :: atom(), ObjState :: any(), TickFrequency :: integer()) -> {ok, Pid :: pid()}.
-callback handle_event(LastTick :: integer(), ObjState :: any(), State :: any()) -> {ok, NewState :: any()}.
-callback handle_tick(LastTick :: integer(), DeltaTime :: integer(), ObjState :: any(), State :: any()) -> {ok, NewState :: any()}.
-callback handle_sync_event(Event :: any(), ObjState :: any(), State :: any()) -> {ok, Reply :: any(), NewState :: any()} | {error, timeout}.
-callback stop(ObjState :: any(), State :: any()) -> ok.

start_link(Uid, CallbackModule, ObjState, Registry, TickFrequency) ->
    Pid = spawn_link(?MODULE, loop, [Uid, CallbackModule, ObjState, Registry, TickFrequency]),
    {ok, Pid}.

stop(Pid) ->
    Pid ! stop.

loop(Uid, CallbackModule, ObjState, Registry, TickFrequency) ->
    {ok, NewObjState} = CallbackModule:start(Uid, ObjState),
    loop(Uid, CallbackModule, NewObjState, Registry, TickFrequency, timestamp()).

loop(Uid, CallbackModule, ObjState, Registry, TickFrequency, LastTick) ->
    TimeUntilNextTick = time_until_next_tick(TickFrequency, LastTick),
    receive
        {event, Event} ->
            {ok, NewObjState} = CallbackModule:on_event(Uid, Event, ObjState),
            {ok, NewObjState2, NewLastTick} = tick(Uid, CallbackModule, NewObjState, TickFrequency, LastTick),
            nxtfr_gen_object:loop(Uid, CallbackModule, NewObjState2, Registry, TickFrequency, NewLastTick);
        {request, Request, From, Ref} ->
            {ok, Response, NewObjState} = CallbackModule:on_request(Uid, From, Request, ObjState),
            {ok, NewObjState2, NewLastTick} = tick(Uid, CallbackModule, NewObjState, TickFrequency, LastTick),
            From ! {Ref, Response},
            nxtfr_gen_object:loop(Uid, CallbackModule, NewObjState2, Registry, TickFrequency, NewLastTick);
        stop ->
            CallbackModule:stop(Uid, ObjState);
        Info ->
            error_logger:warning_msg("~p received unhandled message: ~p.", [Uid, Info]),
            {ok, NewObjState2, NewLastTick} = tick(Uid, CallbackModule, ObjState, TickFrequency, LastTick),
            nxtfr_gen_object:loop(Uid, CallbackModule, NewObjState2, Registry, TickFrequency, NewLastTick)
    after TimeUntilNextTick ->
        {ok, NewObjState, NewLastTick} = tick(Uid, CallbackModule, ObjState, TickFrequency, LastTick),
        nxtfr_gen_object:loop(Uid, CallbackModule, NewObjState, Registry, TickFrequency, NewLastTick)
    end.
        
tick(Uid, CallbackModule, ObjState, TickFrequency, LastTick) ->
    Now = timestamp(),
    DeltaTime = Now - LastTick,
    case DeltaTime >= TickFrequency of
        true -> 
            {ok, NewObjState} = CallbackModule:tick(Uid, DeltaTime, ObjState),
            {ok, NewObjState, Now};
        false ->
            {ok, ObjState, LastTick}
    end.

time_until_next_tick(TickFrequency, LastTick) ->
    TimeUntilNextTick = (LastTick + TickFrequency) - timestamp(),
    case TimeUntilNextTick =< 0 of
        true -> 0;
        false -> TimeUntilNextTick
    end.

timestamp() ->
    erlang:system_time(millisecond).