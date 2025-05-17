-module(nxtfr_object).
-author("christian@flodihn.se").
-behaviour(gen_server).

-include("nxtfr_object.hrl").

-type registry_options() :: [{type, local | shared} | {storage, memory | disc}].

-define(TICK_LOOKUP_TABLE, nxtfr_tick_lookup).
-define(EVENT_TRACKER_TABLE, nxtfr_event_tracker).

%% External exports
-export([
    start_link/0,
    create_cluster/0,
    join_cluster/1,
    create_registry/1,
    create_registry/2,
    join_registry/2,
    destroy_registry/1,
    register/3,
    register/4,
    register/5,
    unregister/2,
    query/2,
    save/3,
    load/2,
    load_existing/2,
    activate/2,
    activate/3,
    deactivate/2,
    send_event/2,
    send_request/3]).

%% Internal exports
-export([
    dispatch_event/3
    ]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    code_change/3,
    terminate/2]).

-spec start_link() -> {ok, Pid :: pid()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec create_cluster() -> {ok, created}.
create_cluster() ->
    gen_server:call(?MODULE, create_cluster).

-spec join_cluster(Node :: atom()) -> {ok, joined}.
join_cluster(Node) ->
    gen_server:call(?MODULE, {join_cluster, Node}).

-spec create_registry(Registry :: atom()) -> {ok, created}.
create_registry(Registry) ->
    create_registry(Registry, [{type, shared}, {storage, disc}]).

-spec create_registry(Registry :: atom(), RegistryOptions :: registry_options()) -> {ok, created}.
create_registry(Registry, RegistryOptions) ->
    gen_server:call(?MODULE, {create_registry, Registry, RegistryOptions}).

-spec join_registry(Node :: atom(), Registry :: atom()) -> {ok, joined}.
join_registry(Node, Registry) ->
    gen_server:call(?MODULE, {join_registry, Node, Registry}).

-spec destroy_registry(Registry :: atom()) -> {ok, created}.
destroy_registry(Registry) ->
    gen_server:call(?MODULE, {destroy_registry, Registry}).

-spec register(Uid :: binary(), CallbackModule :: atom(), Registry :: atom()) -> {ok, registered} | {error, not_found} | {error, registry_not_found}.
register(Uid, CallbackModule, Registry) ->
    gen_server:call(?MODULE, {register, Uid, CallbackModule, 0, undefined, Registry}).

-spec register(Uid :: binary(), CallbackModule :: atom(), TickFrequency :: integer(), Registry :: atom()) -> {ok, registered} | {error, not_found} | {error, registry_not_found}.
register(Uid, CallbackModule, TickFrequency, Registry) ->
    gen_server:call(?MODULE, {register, Uid, CallbackModule, TickFrequency, undefined, Registry}).

-spec register(Uid :: binary(), CallbackModule :: atom(), TickFrequency :: integer(), ObjState :: any(), Registry :: atom()) -> {ok, registered} | {error, not_found} | {error, registry_not_found}.
register(Uid, CallbackModule, TickFrequency, ObjState, Registry) ->
    gen_server:call(?MODULE, {register, Uid, CallbackModule, TickFrequency, ObjState, Registry}).

-spec unregister(Uid :: binary(), Registry :: atom()) -> {ok, unregistered} | {error, not_found} | {error, registry_not_found}.
unregister(Uid, Registry) ->
    gen_server:call(?MODULE, {unregister, Uid, Registry}).

-spec query(Uid :: binary(), Registry :: atom()) -> {ok, State :: any()} | {error, not_found} | {error, registry_not_found}.
query(Uid, Registry) ->
    gen_server:call(?MODULE, {query, Uid, Registry}).

-spec save(Uid :: binary(), ObjState :: any(), Registry :: atom()) -> {ok, saved}.
save(Uid, ObjState, Registry) ->
    gen_server:call(?MODULE, {save, Uid, ObjState, Registry}).

-spec load(Uid :: binary(), Storage :: atom()) -> {ok, ObjState :: any()}.
load(Uid, Storage) ->
    gen_server:call(?MODULE, {load, Uid, Storage}).

-spec load_existing(Uid :: binary(), Storage :: atom()) -> {ok, ObjState :: any() | {error, not_found}}.
load_existing(Uid, Storage) ->
    gen_server:call(?MODULE, {load_existing, Uid, Storage}).

-spec activate(Uid :: binary(), Registry :: atom()) -> {ok, ObjState :: any()} | {error, not_found} | {error, registry_not_found}.
activate(Uid, Registry) ->
    gen_server:call(?MODULE, {activate, Uid, Registry}).

-spec activate(Uid :: binary(), Registry :: atom(), DeepState :: map()) -> {ok, ObjState :: any()} | {error, not_found} | {error, registry_not_found}.
activate(Uid, Registry, DeepState) ->
    gen_server:call(?MODULE, {activate, Uid, Registry, DeepState}).

-spec deactivate(Uid :: binary(), Registry :: atom()) -> {ok, ObjState :: any()} | {error, not_found}.
deactivate(Uid, Registry) ->
    gen_server:call(?MODULE, {deactivate, Uid, Registry}).

-spec send_event(Event :: any(), Registry :: atom()) -> {ok | {error, registry_not_found}}.
send_event(Event, Registry) ->
    gen_server:cast(?MODULE, {send_event, Event, Registry}).

-spec send_request(Uid :: binary(), Event :: any(), Registry :: atom()) -> {ok | {error, not_found} | {error, registry_not_found}}.
send_request(Uid, Event, Registry) ->
    Ref = make_ref(),
    gen_server:cast(?MODULE, {send_request, Uid, Event, Registry, self(), Ref}),
    wait_for_response(Ref).

-spec wait_for_response(Ref :: reference()) -> {ok, Response :: any()} | {error, timeout}.
wait_for_response(Ref) ->
    receive
        {Ref, Response} -> {ok, Response};
        Response ->
            error_logger:error_report({send_request, "Unexpected response", Response}),
            wait_for_response(Ref)
    after 10000 ->
        {error, timeout}
    end.

-spec init([]) -> {ok, []}.
init([]) ->
    mnesia:start(),
    {ok, StorageModule} = application:get_env(storage_module),
    {ok, StorageState} = StorageModule:init(),
    init_tick_procs(),
    {ok, #state{
        storage_module = StorageModule,
        storage_state = StorageState,
        tick_frequency_tables = maps:new(),
        tick_procs = maps:new()}}.

handle_call(create_cluster, _From, State) ->
    mnesia:change_table_copy_type(schema, node(), disc_copies),
    mnesia:create_table(?TICK_LOOKUP_TABLE, [
                {local_content, true},
                {disc_copies, [node()]},
                {record_name, tick_lookup},
                {attributes, record_info(fields, tick_lookup)}]),
    mnesia:create_table(?EVENT_TRACKER_TABLE, [
                {local_content, true},
                {ram_copies, [node()]},
                {record_name, event_tracker},
                {attributes, record_info(fields, event_tracker)}]),
    {reply, ok, State};

handle_call({join_cluster, Node}, _From, State) ->
    {ok, _} = mnesia:change_config(extra_db_nodes, [Node]),
    {atomic, ok} = mnesia:change_table_copy_type(schema, node(), disc_copies),
    rpc:call(Node, mnesia, add_table_copy, [?TICK_LOOKUP_TABLE, node(), disc_copies]),
    rpc:call(Node, mnesia, add_table_copy, [?EVENT_TRACKER_TABLE, node(), ram_copies]),
    {reply, ok, State};

handle_call({create_registry, Registry, RegistryOptions}, _From, State) ->
    MnesiaOptions = parse_registry_options(RegistryOptions),
    mnesia:create_table(Registry, MnesiaOptions),
    {reply, ok, State};

handle_call({join_registry, Node, RegistryName}, _From, State) ->
    rpc:call(Node, mnesia, add_table_copy, [RegistryName, node(), ram_copies]),
    {reply, ok, State};

handle_call({register, Uid, CallbackModule, TickFrequency, ObjState, Registry}, _From, State)
        when is_binary(Uid), is_atom(CallbackModule), is_integer(TickFrequency) ->
    case write_registry(Uid, CallbackModule, TickFrequency, ObjState, Registry) of
        ok ->
            Pid = undefined,
           case TickFrequency of
                0 -> pass;
                _ -> set_tick_frequency(Uid, Pid, CallbackModule, TickFrequency, Registry)
            end,
            {reply, ok, State};
        {error, registry_not_found} -> {reply, {error, registry_not_found}, State};
        Error -> {reply, Error, State}
    end;

handle_call({unregister, Uid, Registry}, _From, State) ->
    case mnesia:dirty_read(Registry, Uid) of
        [#active_obj{uid = Uid, tick_frequency = TickFrequency}] ->
            DeleteFun = fun() -> mnesia:delete(Registry, Uid, write) end,
            case mnesia:transaction(DeleteFun) of
                {atomic, ok} ->
                    unset_tick_frequency(Uid, TickFrequency),
                    {reply, ok, State};
                {aborted, {no_exists, Registry}} ->
                    {reply, {error, registry_not_found}, State};
                Error ->
                    {reply, Error, State}
            end;
        [] ->
            {reply, ok, State}
    end;

handle_call({query, Uid, Registry}, _From, State) ->
    try mnesia:dirty_read(Registry, Uid) of
        [#active_obj{uid = Uid, state = ObjState}] ->
            {reply, {ok, ObjState}, State};
        {aborted, {no_exists, _Record}} ->
            {reply, {error, registry_not_found}, State};
        [] ->
            {reply, {error, not_found}, State}
    catch
        aborted:Reason -> {reply, {error, Reason}, State}
    end;

handle_call({save, Uid, ObjState, Registry}, From, State) ->
    case mnesia:dirty_read(Registry, Uid) of
        [#active_obj{pid = undefined}] ->
            Result = write_storage(Uid, ObjState, Registry, State),
            {reply, Result, State};
        %% This happens when an active objects wants to save itself.
        [#active_obj{pid = From}] ->
            Result = write_storage(Uid, ObjState, Registry, State),
            {reply, Result, State};
        %% If someone else wants to write to an active objects, we 
        %% redirect the save there.
        [#active_obj{pid = Pid}] ->
            nxtfr_object_activeobj:save(Pid, ObjState),
            {reply, {ok, saved}, State}
    end;

handle_call({load, Uid, Registry}, _From, #state{
        storage_module = StorageModule,
        storage_state = StorageState} = State) ->
    case StorageModule:load(Uid, Registry, StorageState) of
        {ok, ObjState} ->
            {reply, {ok, ObjState}, State};
        {error, not_found} ->
            {reply, {ok, maps:new()}, State}
    end;

handle_call({load_existing, Uid, Registry}, _From, #state{
        storage_module = StorageModule,
        storage_state = StorageState} = State) ->
    case StorageModule:load(Uid, Registry, StorageState) of
        {ok, ObjState} ->
            {reply, {ok, ObjState}, State};
        {error, not_found} ->
            {reply, {error, not_found}, State}
    end;

handle_call({activate, Uid, Registry}, _From, State) ->
    {ok, Pid, UpdatedState} = activate_object(Uid, Registry, State),
    {reply, {ok, Pid}, UpdatedState};

handle_call({activate, Uid, Registry, ObjState}, _From, State) ->
    {ok, Pid, UpdatedState} = activate_object(Uid, Registry, ObjState, State),
    {reply, {ok, Pid}, UpdatedState};

handle_call({deactivate, Uid, Registry}, _From, State) ->
    ok = deactivate_object(Uid, Registry),
    {reply, ok, State};

handle_call(Call, _From, State) ->
    error_logger:error_report([{undefined_call, Call}]),
    {reply, ok, State}.

handle_cast({send_event, Event, Registry}, State) ->
    case mnesia:dirty_first(Registry) of
        {aborted, {no_exists, _Record}} ->
            {noreply, State};
        FirstKey ->
            spawn(nxtfr_object, dispatch_event, [FirstKey, Event, Registry]),
            {noreply, State}
    end;

handle_cast({send_request, Uid, Request, Registry, From, Ref}, State) ->
    try mnesia:dirty_read(Registry, Uid) of
        [#active_obj{pid = Pid}] ->
            case is_object_alive(Pid) of
                true ->
                    Pid ! {request, Request, From, Ref},
                    {reply, ok, State};
                false ->
                    case activate_object(Uid, Registry, State) of
                        {atomic, NewPid} ->
                            NewPid ! Request,
                            {reply, ok, State};
                        {aborted, {no_exists, _Record}} ->
                            {reply, {error, registry_not_found}, State}
                    end
            end;
        {aborted, {no_exists, _Record}} ->
            {reply, {error, registry_not_found}, State};
        [] ->
            {reply, {error, not_found}, State}
    catch
        aborted:Reason -> {reply, {error, Reason}, State}
    end;

handle_cast(Cast, State) ->
    error_logger:error_report([{undefined_cast, Cast}]),
    {noreply, State}.

handle_info(Info, State) ->
    error_logger:error_report([{undefined_info, Info}]),
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

parse_registry_options(RegistryOptions) ->
    BaseOptions = [
        {record_name, active_obj},
        {attributes, record_info(fields, active_obj)}],
    parse_registry_options(RegistryOptions, BaseOptions).

parse_registry_options([], Acc) ->
    Acc;

parse_registry_options([{type, Type} | Rest], Acc) ->
    case Type of
        local -> parse_registry_options(Rest, lists:append([{local_content, true}], Acc));
        shared -> parse_registry_options(Rest, Acc)
    end;

parse_registry_options([{storage, Storage} | Rest], Acc) ->
    case Storage of
        memory -> parse_registry_options(Rest, lists:append([{ram_copies, [node()]}], Acc));
        disc -> parse_registry_options(Rest, lists:append([{disc_copies, [node()]}], Acc))
    end.

activate_object(Uid, Registry, State) ->
    ObjState = read_object_storage(Uid, Registry, State),
    activate_object(Uid, Registry, ObjState, State).

activate_object(Uid, Registry, ObjState, State) ->
    case mnesia:dirty_read(Registry, Uid) of
        [] ->
            error_logger:error_report({activate_object, "Failed to read from registry", Uid, Registry}),
            {error, uid_not_found};
        [#active_obj{
                callback_module = CallbackModule,
                tick_frequency = TickFrequency} = Obj] ->
        {ok, Pid} = nxtfr_object_activeobj_sup:start(Uid, CallbackModule, ObjState, Registry, TickFrequency),
        case is_integer(TickFrequency) of
            true -> unset_tick_frequency(Uid, TickFrequency);
            false -> pass
        end,
        WriteFun = fun() -> 
            mnesia:write(Registry, Obj#active_obj{pid = Pid}, write),
            Pid
        end,
        mnesia:transaction(WriteFun),
        {ok, Pid, State}
    end.

deactivate_object(Uid, Registry) ->
    case mnesia:dirty_read(Registry, Uid) of
        [#active_obj{pid = undefined}] ->
            ok;
        [#active_obj{pid = Pid, tick_frequency = TickFrequency} = Obj] ->
            ok = nxtfr_object_activeobj_sup:stop(Pid),
            ok = write_registry(Obj#active_obj{pid = undefined}, Registry),
            set_tick_frequency(Uid, Pid, TickFrequency, Registry)
    end.

read_object_storage(Uid, Registry, #state{storage_module = StorageModule, storage_state = StorageState}) ->
    case StorageModule:load(Uid, Registry, StorageState) of
        {error, not_found} ->
            maps:new();
        {ok, ObjState} ->
            ObjState
    end.

is_object_alive(undefined) ->
    false;

is_object_alive(Pid) ->
    case node(Pid) == node() of
        true ->
            is_process_alive(Pid);
        false ->
            %% TODO: Is this too expensive to before every event?
            %% Maybe better approach is to make the Pid response with
            %% something so we can get a timeout instead.
            case rpc:call(node(Pid), is_process_alive, [Pid]) of
                true -> true;
                false -> false;
                {badrpc, nodedown} -> false
            end
    end.

write_registry(ObjState, Registry) ->
    WriteFun = fun() -> 
        mnesia:write(Registry, ObjState, write)
    end,
    case mnesia:transaction(WriteFun) of
        {atomic, ok} ->
            ok;
        {aborted, {no_exists, Registry}} ->
            {error, registry_not_found};
        Error ->
            Error
    end.

write_registry(Uid, CallbackModule, TickFrequency, ObjState, Registry) ->
    WriteFun = fun() -> 
        mnesia:write(Registry, #active_obj{
            uid = Uid,
            callback_module = CallbackModule,
            tick_frequency = TickFrequency,
            state = ObjState}, write)
    end,
    case mnesia:transaction(WriteFun) of
        {atomic, ok} ->
            ok;
        {aborted, {no_exists, Registry}} ->
            {error, registry_not_found};
        Error ->
            Error
    end.

write_storage(Uid, ObjState, Registry, #state{
        storage_module = StorageModule,
        storage_state = StorageState}) ->
    case StorageModule:save(Uid, ObjState, Registry, StorageState) of
        {ok, saved} -> {ok, saved};
        {error, not_found} -> {error, not_found}
    end.

set_tick_frequency(_Uid, _Pid, 0, _Registry) ->
    ok;

set_tick_frequency(Uid, Pid, TickFrequency, Registry) ->
    case mnesia:dirty_read(?TICK_LOOKUP_TABLE, TickFrequency) of
        [] ->
            TableName = frequency_to_table_id(TickFrequency),
            create_tick_table(TableName, TickFrequency),
            mnesia:dirty_write(TableName, #tick_obj{uid = Uid, pid = Pid, registry = Registry});
        [#tick_lookup{frequency = TickFrequency, table_name = TableName}] ->
            mnesia:dirty_write(TableName, #tick_obj{uid = Uid, pid = Pid, registry = Registry})
    end.

set_tick_frequency(Uid, Pid, CallbackModule, TickFrequency, Registry) ->
    case mnesia:dirty_read(?TICK_LOOKUP_TABLE, TickFrequency) of
        [] ->
            TableName = frequency_to_table_id(TickFrequency),
            create_tick_table(TableName, TickFrequency),
            mnesia:dirty_write(TableName, #tick_obj{uid = Uid, pid = Pid, callback_module = CallbackModule, registry = Registry});
         [#tick_lookup{frequency = TickFrequency, table_name = TableName}] ->
            mnesia:dirty_write(TableName, #tick_obj{uid = Uid, pid = Pid, callback_module = CallbackModule, registry = Registry})
    end.

unset_tick_frequency(Uid, TickFrequency) ->
    case mnesia:dirty_read(?TICK_LOOKUP_TABLE, TickFrequency) of
        [] ->
            pass;
        [#tick_lookup{frequency = TickFrequency, table_name = TableName}] ->
            mnesia:dirty_delete(TableName, Uid)
    end.

create_tick_table(TableName, TickFrequency) ->
    mnesia:create_table(TableName, [
        {local_content, true},
        {ram_copies, [node()]},
        {record_name, tick_obj},
        {attributes, record_info(fields, tick_obj)}]),
    start_tick_proc(TableName, TickFrequency).

frequency_to_table_id(TickFrequency) ->
    list_to_atom("nxtfr_tick_frequency_" ++ integer_to_list(TickFrequency)).

init_tick_procs() ->
    case mnesia:wait_for_tables([?TICK_LOOKUP_TABLE], 10000) of
        {timeout, _RemaingTables} ->
            error_logger:warning_msg(
                "Timeout when waiting for table ~p, call nxtfr_object:create_cluster to create it.",
                [?TICK_LOOKUP_TABLE]);
        ok ->
            case lists:member(?TICK_LOOKUP_TABLE, mnesia:system_info(tables)) of
                true ->
                    init_tick_procs(mnesia:dirty_first(?TICK_LOOKUP_TABLE));
            false ->
                error_logger:warning_msg(
                    "Table ~p not found during init, call nxtfr_object:create_cluster to create it.",
                    [?TICK_LOOKUP_TABLE])
            end
    end.

init_tick_procs('$end_of_table') ->
    done;

init_tick_procs(Key) ->
    case mnesia:wait_for_tables([?TICK_LOOKUP_TABLE], 10000) of
        {timeout, _RemaingTables} ->
            error_logger:warning_msg(
                "Timeout when waiting for table ~p, call nxtfr_object:create_cluster to create it.",
                [?TICK_LOOKUP_TABLE]);
        ok ->
            [#tick_lookup{frequency = TickFrequency, table_name = TableName}] = mnesia:dirty_read(
                ?TICK_LOOKUP_TABLE, Key),
            start_tick_proc(TableName, TickFrequency),
            init_tick_procs(mnesia:dirty_next(?TICK_LOOKUP_TABLE, Key))
    end.

start_tick_proc(TableName, TickFrequency) ->
    TickProc = nxtfr_object_tick_proc:start(TickFrequency, TableName),
    mnesia:dirty_write(?TICK_LOOKUP_TABLE, #tick_lookup{
        frequency = TickFrequency,
        table_name = TableName,
        tick_proc = TickProc}).

dispatch_event('$end_of_table', _Event, _Registry) ->
    ok;

dispatch_event(Key, Event, Registry) ->
    case mnesia:dirty_read({Registry, Key}) of
        [] ->
            ok;
        [#tick_obj{uid = Uid, pid = undefined, callback_module = CallbackModule}] ->
            CallbackModule:on_event(Uid, Event);
        [#tick_obj{pid = Pid}] ->
            Pid ! {event, Event}
    end,
    nxtfr_object:dispatch_event(mnesia:dirty_next(Registry, Key), Event, Registry).
