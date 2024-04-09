-module(nxtfr_object_tick_proc).
-author("christian@flodihn.se").

-include("nxtfr_object.hrl").

%% External exports.
-export([
    start/2
]).

%% Internal exports.
-export([
    frequency_loop/5,
    tick/2,
    tick/3
    ]).

start(TickFrequency, TableId) ->
    TickResolutionMs = application:get_env(nxtfr_object, tick_resolution_ms, 100),
    LastTick = timestamp(),
    TickProc = undefined,
    spawn_link(?MODULE, frequency_loop, [TableId, TickFrequency, TickResolutionMs, LastTick, TickProc]).

frequency_loop(TableName, TickFrequency, TickResolutionMs, LastTick, TickProc) ->
    NextFrequency = LastTick rem TickResolutionMs,
    timer:sleep(NextFrequency),
    Now = timestamp(),
    TimeDiff = timestamp() - LastTick,
    case TimeDiff >= TickFrequency of
        true ->
            case is_proc_alive(TickProc) of
                true ->
                    error_logger:warning_msg("Warning: TickProc for ~b might be stacking.~n", [TickFrequency]);
                false ->
                    pass
            end,
            NewTickProc = spawn_link(?MODULE, tick, [TableName, TimeDiff]),
            NewLastTick = Now,
            ?MODULE:frequency_loop(TableName, TickFrequency, TickResolutionMs, NewLastTick, NewTickProc);
        false ->
            ?MODULE:frequency_loop(TableName, TickFrequency, TickResolutionMs, LastTick, TickProc)
    end.

tick(TableName, LastTick) ->
    try mnesia:dirty_first(TableName) of
        FirstKey -> ?MODULE:tick(TableName, FirstKey, LastTick)
    catch
        exit:{aborted, Error} -> error_logger:error_report(Error)
    end.

tick(_TableName, '$end_of_table', _LastTick) ->
    done;

tick(TableName, Key, LastTick) ->
    case mnesia:dirty_read(TableName, Key) of
        [#tick_obj{uid = Uid, pid = undefined, registry = Registry}] ->
            {ok, Pid} = nxtfr_object:activate(Uid, Registry),
            %% Disable ticking until I figure out how I implemented this feature.
            %nxtfr_gen_object:tick(Pid, LastTick),
            mnesia:dirty_delete(TableName, Uid);
        [{_Uid, Pid, _Registry}] ->
            %% Disable ticking until I figure out how I implemented this feature.
            %{ok, ActiveObjectModule} = application:get_env(active_object_module),
            %ActiveObjectModule:tick(Pid, LastTick)
            pass
    end,
    ?MODULE:tick(TableName, mnesia:dirty_next(TableName, Key), LastTick).

is_proc_alive(undefined) ->
    false;

is_proc_alive(Pid) ->
    erlang:is_process_alive(Pid).

timestamp() ->
    erlang:system_time(millisecond).