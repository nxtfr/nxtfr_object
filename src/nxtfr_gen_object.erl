%%%-------------------------------------------------------------------
%% @doc nxtfr_gen_object active object behaviour.
%% @end
%%%-------------------------------------------------------------------

-module(nxtfr_gen_object).
-author("christian@flodihn.se").

%% Behaviour exports
-export([
    start_link/5,
    send_event/2,
    send_message/2,
    send_message/3,
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

send_event(Pid, Event) ->
    Pid ! {event, Event}.

send_message(Pid, Event) ->
    send_message(Pid, Event, 10000).

send_message(Pid, Event, Timeout) ->
    Ref = make_ref(),
    Pid ! {message, self(), Event, Ref},
    receive 
        {Ref, Reply} -> Reply
    after 
        Timeout -> {error, timeout}
    end.

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
        {message, From, Message, Ref} ->
            {ok, Reply, NewObjState} = CallbackModule:on_message(Uid, From, Message, ObjState),
            {ok, NewObjState2, NewLastTick} = tick(Uid, CallbackModule, NewObjState, TickFrequency, LastTick),
            pid ! {Ref, Reply},
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
    case DeltaTime > TickFrequency of
        true -> 
            {ok, NewObjState} = CallbackModule:tick(Uid, DeltaTime, ObjState),
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