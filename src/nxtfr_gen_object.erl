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
    loop/5,
    tick/5]).

-callback start_link(Uid :: binary(), CallbackModule :: atom(), ObjState :: any(), Registry :: atom(), State :: any()) -> {ok, Pid :: pid()}.
-callback handle_event(LastTick :: integer(), ObjState :: any(), State :: any()) -> {ok, NewState :: any()}.
-callback handle_tick(LastTick :: integer(), DeltaTime :: integer(), ObjState :: any(), State :: any()) -> {ok, NewState :: any()}.
-callback handle_sync_event(Event :: any(), ObjState :: any(), State :: any()) -> {ok, Reply :: any(), NewState :: any()} | {error, timeout}.
-callback stop(ObjState :: any(), State :: any()) -> ok.

start_link(Module, ObjState, State, TickFrequency) ->
    Pid = spawn_link(?MODULE, loop, [Module, ObjState, State, TickFrequency, timestamp()]),
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

loop(Module, ObjState, State, TickFrequency, LastTick) ->
    TimeUntilNextTick = time_until_next_tick(TickFrequency, LastTick),
    receive
        {handle_event, Event} ->
            {ok, NewObjState, NewState} = Module:handle_event(Event, ObjState, State),
            {ok, NewObjState2, TickedState, NewLastTick} = tick(Module, NewObjState, NewState, TickFrequency, LastTick),
            nxtfr_gen_object:loop(Module, NewObjState2, TickedState, TickFrequency, NewLastTick);
        {handle_sync_event, From, Event, Ref} ->
            {ok, Reply, NewObjState, NewState} = Module:handle_sync_event(Event, ObjState, State),
            From ! {Ref, Reply},
            {ok, NewObjState2, TickedState, NewLastTick} = tick(Module, NewObjState, NewState, TickFrequency, LastTick),
            nxtfr_gen_object:loop(Module, NewObjState2, TickedState, TickFrequency, NewLastTick);
        stop ->
            Module:stop(ObjState, State);
        Info ->
            {ok, NewObjState, NewState} = Module:handle_info(Info, ObjState, State),
            {ok, NewObjState2, TickedState, NewLastTick} = tick(Module, NewObjState, NewState, TickFrequency, LastTick),
            nxtfr_gen_object:loop(Module, NewObjState2, TickedState, TickFrequency, NewLastTick)
    after TimeUntilNextTick ->
        {ok, NewObjState, TickedState, NewLastTick} = tick(Module, ObjState, State, TickFrequency, LastTick),
        nxtfr_gen_object:loop(Module, NewObjState, TickedState, TickFrequency, NewLastTick)
    end.
        
tick(Module, ObjState, State, TickFrequency, LastTick) ->
    Now = timestamp(),
    DeltaTime = Now - LastTick,
    case DeltaTime > TickFrequency of
        true -> 
            {ok, NewObjState, NewState} = Module:handle_tick(LastTick, DeltaTime, ObjState, State),
            {ok, NewObjState, NewState, Now};
        false ->
            {ok, ObjState, State, LastTick}
    end.

time_until_next_tick(TickFrequency, LastTick) ->
    Time = timestamp() - (LastTick + TickFrequency),
    case Time < 0 of
        true -> 0;
        false -> Time
    end.

timestamp() ->
    erlang:system_time(millisecond).