-module(nxtfr_object).
-author("christian@flodihn.se").
-behaviour(gen_server).

-record(obj, {uid, state}).
-record(state, {storage_module, storage_state}).

-type registry_options() :: [{type, local | shared} | {storage, memory | disc }].

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
    unregister/2,
    query/2,
    save/3,
    load/2,
    activate/2,
    deactivate/2]).

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

-spec create_registry(RegistryName :: atom()) -> {ok, created}.
create_registry(RegistryName) ->
    create_registry(RegistryName, [{type, shared}, {storage, disc}]).

-spec create_registry(RegistryName :: atom(), RegistryOptions :: registry_options()) -> {ok, created}.
create_registry(RegistryName, RegistryOptions) ->
    gen_server:call(?MODULE, {create_registry, RegistryName, RegistryOptions}).

-spec join_registry(Node :: atom(), RegistryName :: atom()) -> {ok, joined}.
join_registry(Node, RegistryName) ->
    gen_server:call(?MODULE, {join_registry, Node, RegistryName}).

-spec destroy_registry(RegistryName :: atom()) -> {ok, created}.
destroy_registry(RegistryName) ->
    gen_server:call(?MODULE, {destroy_registry, RegistryName}).

-spec register(Uid :: binary(), State :: any(), RegistryName :: atom()) -> {ok, registered}.
register(Uid, State, RegistryName) ->
    gen_server:call(?MODULE, {register, Uid, State, RegistryName}).

-spec unregister(Uid :: binary(), RegistryName :: atom()) -> {ok, unregistered}.
unregister(Uid, RegistryName) ->
    gen_server:call(?MODULE, {unregister, Uid, RegistryName}).

-spec query(Uid :: binary(), RegistryName :: atom()) -> {ok, State :: any()}.
query(Uid, RegistryName) ->
    gen_server:call(?MODULE, {query, Uid, RegistryName}).

-spec save(Uid :: binary(), ObjState :: any(), Storage :: atom()) -> {ok, saved}.
save(Uid, ObjState, Storage) ->
    gen_server:call(?MODULE, {save, Uid, ObjState, Storage}).

-spec load(Uid :: binary(), Storage :: atom()) -> {ok, ObjState :: any() | {error, not_found}}.
load(Uid, Storage) ->
    gen_server:call(?MODULE, {load, Uid, Storage}).

-spec activate(Uid :: binary(), Storage :: atom()) -> {ok, ObjState :: any() | {error, not_found}}.
activate(Uid, Storage) ->
    gen_server:call(?MODULE, {activate, Uid, Storage}).

-spec deactivate(Uid :: binary(), Storage :: atom()) -> {ok, ObjState :: any() | {error, not_found}}.
deactivate(Uid, Storage) ->
    gen_server:call(?MODULE, {deactivate, Uid, Storage}).

-spec init([]) -> {ok, []}.
init([]) ->
    mnesia:start(),
    {ok, StorageModule} = application:get_env(storage_module),
    {ok, StorageState} = StorageModule:init(),
    {ok, #state{storage_module = StorageModule, storage_state = StorageState}}.

handle_call(create_cluster, _From, State) ->
    mnesia:change_table_copy_type(schema, node(), disc_copies),
    {reply, ok, State};

handle_call({join_cluster, Node}, _From, State) ->
    {ok, _} = mnesia:change_config(extra_db_nodes, [Node]),
    {atomic, ok} = mnesia:change_table_copy_type(schema, node(), disc_copies),
    {reply, ok, State};

handle_call({create_registry, RegistryName, RegistryOptions}, _From, State) ->
    MnesiaOptions = parse_registry_options(RegistryOptions),
    mnesia:create_table(RegistryName, MnesiaOptions),
    {reply, ok, State};

handle_call({join_registry, Node, RegistryName}, _From, State) ->
    rpc:call(Node, mnesia, add_table_copy, [RegistryName, node(), ram_copies]),
    {reply, ok, State};

handle_call({register, Uid, ObjState, RegistryName}, _From, State) ->
    WriteFun = fun() -> 
        mnesia:write(RegistryName, #obj{uid = Uid, state = ObjState}, write)
    end,
    case mnesia:transaction(WriteFun) of
        {atomic, ok} ->
            {reply, ok, State};
        {aborted, {no_exists, RegistryName}} ->
            {reply, {error, registry_not_found}, State};
        Error ->
            {reply, Error, State}
    end;

handle_call({unregister, Uid, RegistryName}, _From, State) ->
    DeleteFun = fun() -> mnesia:delete(RegistryName, Uid, write) end,
    case mnesia:transaction(DeleteFun) of
        {atomic, ok} ->
            {reply, ok, State};
        {aborted, {no_exists, RegistryName}} ->
            {reply, {error, registry_not_found}, State};
        Error ->
            {reply, Error, State}
    end;

handle_call({query, Uid, RegistryName}, _From, State) ->
    try mnesia:dirty_read(RegistryName, Uid) of
        [#obj{uid = Uid, state = ObjState}] ->
            {reply, {ok, ObjState}, State};
        {aborted, {no_exists, _Record}} ->
            {reply, {error, registry_not_found}, State};
        [] ->
            {reply, {error, not_found}, State}
    catch
        aborted:Reason -> {reply, {error, Reason}, State}
    end;

handle_call({save, Uid, ObjState, Storage}, _From, #state{
        storage_module = StorageModule,
        storage_state = StorageState} = State) ->
    case StorageModule:save(Uid, ObjState, Storage, StorageState) of
        {ok, saved} ->
            {reply, {ok, saved}, State};
        {error, not_found} ->
            {reply, {error, not_found}, State}
    end;

handle_call({load, Uid, Storage}, _From, #state{
        storage_module = StorageModule,
        storage_state = StorageState} = State) ->
    case StorageModule:load(Uid, Storage, StorageState) of
        {ok, ObjState} ->
            {reply, {ok, ObjState}, State};
        {error, not_found} ->
            {reply, {error, not_found}, State}
    end;

handle_call(Call, _From, State) ->
    error_logger:error_report([{undefined_call, Call}]),
    {reply, ok, State}.

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
        {record_name, obj},
        {attributes, record_info(fields, obj)}],
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