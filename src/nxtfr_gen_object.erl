%%%-------------------------------------------------------------------
%% @doc nxtfr_gen_object active object behaviour.
%% @end
%%%-------------------------------------------------------------------

-module(nxtfr_gen_object).
-author("christian@flodihn.se").

%% Behaviour exports
-export([
    start_link/4,
    handle_event/2,
    handle_sync_event/2,
    handle_sync_event/3,
    stop/1
    ]).

%% Interal exports
-export([
    loop/6,
    tick/5]).

-callback start_link(Uid :: binary(), CallbackModule :: atom(), ObjState :: any(), TickFrequency :: integer()) -> {ok, Pid :: pid()}.
-callback handle_event(LastTick :: integer(), ObjState :: any(), State :: any()) -> {ok, NewState :: any()}.
-callback handle_tick(LastTick :: integer(), DeltaTime :: integer(), ObjState :: any(), State :: any()) -> {ok, NewState :: any()}.
-callback handle_sync_event(Event :: any(), ObjState :: any(), State :: any()) -> {ok, Reply :: any(), NewState :: any()} | {error, timeout}.
-callback stop(ObjState :: any(), State :: any()) -> ok.

start_link(Uid, CallbackModule, ObjState, TickFrequency) ->
    Pid = spawn_link(?MODULE, loop, [Uid, CallbackModule, ObjState, TickFrequency, timestamp()]),
    {ok, Pid}.

handle_event(Pid, Event) ->
    Pid ! {handle_event, Event}.

handle_sync_event(Pid, Event) ->
    handle_sync_event(Pid, Event, 10000).

handle_sync_event(Pid, Event, Timeout) ->
    Ref = make_ref(),
    Pid ! {handle_sync_event, self(), Event, Ref},
    receive 
        {Ref, Reply} -> Reply
    after 
        Timeout -> {error, timeout}
    end.

stop(Pid) ->
    Pid ! stop.

loop(Uid, CallbackModule, ObjState, TickState, TickFrequency, LastTick) ->
    TimeUntilNextTick = time_until_next_tick(TickFrequency, LastTick),
    receive
        {handle_event, Event} ->
            {ok, NewObjState} = CallbackModule:handle_event(Event, ObjState, TickState),
            {ok, NewObjState2, TickedState, NewLastTick} = tick(CallbackModule, NewObjState, TickState, TickFrequency, LastTick),
            nxtfr_gen_object:loop(Uid, CallbackModule, NewObjState2, TickedState, TickFrequency, NewLastTick);
        {handle_sync_event, From, Event, Ref} ->
            {ok, Reply, NewObjState, NewTickState} = CallbackModule:handle_sync_event(Event, ObjState, TickState),
            From ! {Ref, Reply},
            {ok, NewObjState2, TickedState, NewLastTick} = tick(CallbackModule, NewObjState, NewTickState, TickFrequency, LastTick),
            nxtfr_gen_object:loop(Uid, CallbackModule, NewObjState2, TickedState, TickFrequency, NewLastTick);
        stop ->
            CallbackModule:stop(ObjState, TickState);
        Info ->
            {ok, NewObjState, NewTickState} = CallbackModule:handle_info(Info, ObjState, TickState),
            {ok, NewObjState2, TickedState, NewLastTick} = tick(CallbackModule, NewObjState, NewTickState, TickFrequency, LastTick),
            nxtfr_gen_object:loop(Uid, CallbackModule, NewObjState2, TickedState, TickFrequency, NewLastTick)
    after TimeUntilNextTick ->
        {ok, NewObjState, TickedState, NewLastTick} = tick(CallbackModule, ObjState, TickState, TickFrequency, LastTick),
        nxtfr_gen_object:loop(Uid, CallbackModule, NewObjState, TickedState, TickFrequency, NewLastTick)
    end.
        
tick(CallbackModule, ObjState, TickState, TickFrequency, LastTick) ->
    Now = timestamp(),
    DeltaTime = Now - LastTick,
    case DeltaTime > TickFrequency of
        true -> 
            {ok, NewObjState} = CallbackModule:handle_tick(LastTick, DeltaTime, ObjState, TickState),
            {ok, NewObjState, Now};
        false ->
            {ok, ObjState, LastTick}
    end.

time_until_next_tick(TickFrequency, LastTick) ->
    Time = timestamp() - (LastTick + TickFrequency),
    case Time < 0 of
        true -> 0;
        false -> Time
    end.

timestamp() ->
    erlang:system_time(millisecond).