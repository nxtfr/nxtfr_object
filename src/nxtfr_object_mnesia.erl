-module(nxtfr_object_mnesia).
-author("christian@flodihn.se").

-record(mnesia_state, {}).
-type mnesia_state() :: #mnesia_state{}.

-record(object_store, {uid, obj_state}).
-define(PUT_ARGS, [{w, 1}, {dw, 1}]).

-export([
    init/0,
    stop/1,
    save/4,
    load/3]).

-spec init() -> {ok, MnesiaState :: mnesia_state()}.
init() ->
    mnesia:start(),
    {ok, #mnesia_state{}}.

-spec create_table(TableName :: atom) -> ok | {error, Reason :: atom}.
create_table(TableName) ->
    % Define the table structure
    TableDef = [
        {attributes, [uid, obj_state]},    % Record fields: key and value
        {disc_copies, [node()]},       % Store on disc on this node
        {type, set}                    % Use 'set' type (unique keys)
    ],
    
    % Check if table exists and create if it doesn't
    case mnesia:create_table(TableName, TableDef) of
        {atomic, ok} ->
            ok;
        {aborted, {already_exists, TableName}} ->
            ok;
        {aborted, Reason} ->
            {error, Reason}
    end.

-spec stop(MnesiaState :: mnesia_state()) -> {ok, []}.
stop(_MnesiaState) ->
    ok.

-spec save(Uid :: binary(), ObjState :: any(), Storage :: atom(), MnesiaState :: mnesia_state()) -> {ok, saved}.
save(Uid, ObjState, Storage, _MnesiaState) ->
    Record = #object_store{uid = Uid, obj_state = ObjState},
    F = fun() -> mnesia:write(Record) end,
    {atomic, ok} = mnesia:transaction(F),
    {ok, saved}.

-spec load(Uid :: binary(), Storage :: atom(), MnesiaState :: mnesia_state()) -> {ok, ObjState :: any()}.
load(Uid, Storage, #mnesia_state{}) ->
    F = fun() -> mnesia:read({object_store, Uid}) end,
    case mnesia:transaction(F) of
        {atomic, [#object_store{obj_state = ObjState}]} -> {ok, ObjState};
        {atomic, []} -> {error, not_found}
    end.