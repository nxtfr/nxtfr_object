-module(nxtfr_object).
-author("christian@flodihn.se").
-behaviour(gen_server).

-record(obj, {uid, state}).

%% External exports
-export([
    start_link/0,
    create_registry/1,
    create_registry/2,
    join_registry/2,
    destroy_registry/1,
    register/3,
    unregister/2,
    query/2]).

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

-spec create_registry(RegistryName :: atom()) -> {ok, created}.
create_registry(RegistryName) ->
    create_registry(RegistryName, shared).

-spec create_registry(RegistryName :: atom(), RegistryType :: local | shared) -> {ok, created}.
create_registry(RegistryName, RegistryType) ->
    gen_server:call(?MODULE, {create_registry, RegistryType, RegistryName}).

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

-spec init([]) -> {ok, []}.
init([]) ->
    mnesia:start(),
    mnesia:change_table_copy_type(schema, node(), disc_copies),
    {ok, []}.

handle_call({create_registry, RegistryType, RegistryName}, _From, State) ->
    case RegistryType of
        local ->
            mnesia:create_table(RegistryName, [
                {ram_copies, [node()]},
                {record_name, obj},
                {attributes, record_info(fields, obj)},
                {local_content, true}]);
        shared ->
            mnesia:create_table(RegistryName, [
                {ram_copies, [node()]},
                {record_name, obj},
                {attributes, record_info(fields, obj)}])
    end,
    {reply, ok, State};

handle_call({join_registry, Node, RegistryName}, _From, State) ->
    mnesia:change_config(extra_db_nodes, [Node]),
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