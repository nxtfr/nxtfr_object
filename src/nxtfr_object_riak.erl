-module(nxtfr_object_riak).
-author("christian@flodihn.se").

-record(riak_state, {riak_client_pid :: pid()}).

-type riak_state() :: #riak_state{}.

-define(PUT_ARGS, [{w, 1}, {dw, 1}]).

-export([
    init/0,
    stop/1,
    save/4,
    load/3]).

-spec init() -> {ok, RiakState :: riak_state()}.
init() ->
    %% In case the supervisor trigger restarts because of lost db connection
    %% or similar. We want to avoid restarting too quickly.
    timer:sleep(500),
    {ok, RiakOptions} = application:get_env(riak_options),
    Hostname = proplists:get_value(hostname, RiakOptions, "127.0.0.1"),
    Port = proplists:get_value(port, RiakOptions, 8087),
    {ok, Pid} = riakc_pb_socket:start(Hostname, Port),
    {ok, #riak_state{riak_client_pid = Pid}}.

-spec stop(RiakState :: riak_state()) -> ok.
stop(#riak_state{riak_client_pid = Pid}) ->
    riakc_pb_socket:stop(Pid).

-spec save(Uid :: binary(), ObjState :: any(), Storage :: atom(), RiakState :: riak_state()) -> {ok, saved}.
save(Uid, ObjState, Storage, #riak_state{riak_client_pid = Pid}) ->
    Table = list_to_binary(atom_to_list(Storage)),
    case riakc_pb_socket:get(Pid, Table, Uid) of
        {error, notfound} ->
            NewObject = riakc_obj:new(Table, Uid, term_to_binary(ObjState)),
            riakc_pb_socket:put(Pid, NewObject, ?PUT_ARGS);
        {ok, ExistingObject} ->
            UpdatedObject = riakc_obj:update_value(ExistingObject, term_to_binary(ObjState)),
            ok = riakc_pb_socket:put(Pid, UpdatedObject, ?PUT_ARGS)
    end,
    {ok, saved}.

-spec load(Uid :: binary(), Storage :: atom(), RiakState :: riak_state()) -> {ok, ObjState :: any()}.
load(Uid, Storage, #riak_state{riak_client_pid = Pid}) ->
    Table = list_to_binary(atom_to_list(Storage)),
    case riakc_pb_socket:get(Pid, Table, Uid) of
        {ok, ObjState} ->
            {ok, binary_to_term(riakc_obj:get_value(ObjState))};
        {error, notfound} ->
            {error, not_found}
    end.