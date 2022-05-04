-module(nxtfr_object_activeobj).
-author("christian@flodihn.se").
-behaviour(gen_server).

-record(state, {uid, state}).

%% External exports
-export([start_link/1]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    code_change/3,
    terminate/2]).

-spec start_link(ObjState :: any()) -> {ok, Pid :: pid()}.
start_link(ObjState) ->
    gen_server:start_link(?MODULE, [ObjState], []).

-spec init([ObjState :: any()]) -> {ok, []}.
init([ObjState]) ->
    io:format("State: ~p.~n", [ObjState]),
    {ok, #state{}}.

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