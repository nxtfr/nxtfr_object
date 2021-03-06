-module(nxtfr_object_activeobj).
-author("christian@flodihn.se").
-behaviour(gen_server).

-record(state, {uid, callback_module, obj_state}).
%% External exports
-export([start_link/2]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    code_change/3,
    terminate/2]).

-spec start_link(CallbackModule :: atom(), ObjState :: any()) -> {ok, Pid :: pid()}.
start_link(CallbackModule, ObjState) ->
    gen_server:start_link(?MODULE, [CallbackModule, ObjState], []).

-spec init(InitParameters :: list()) -> {ok, #state{}}.
init([CallbackModule, ObjState]) ->
    io:format("Activated object ~p.~n", [CallbackModule]),
    {ok, #state{callback_module = CallbackModule, obj_state = ObjState}}.

handle_call(Event, _From, #state{callback_module = CallbackModule, obj_state = ObjState} = State) ->
    CallbackModule:on_event(Event, ObjState),
    %error_logger:error_report([{undefined_call, Call}]),
    {reply, ok, State}.

handle_cast(Event, #state{callback_module = CallbackModule, obj_state = ObjState} = State) ->
    CallbackModule:on_event(Event, ObjState),
    %error_logger:error_report([{undefined_cast, Cast}]),
    {noreply, State}.

handle_info(Event, #state{callback_module = CallbackModule, obj_state = ObjState} = State) ->
    %case CallbackModule:on_event(Info, ObjState) of
    %    ok ->
    %        {noreply, State};
    %    {ok, NewObjState} ->
    %        {noreply, State#state{obj_state = NewObjState}}
    %end.
    CallbackModule:on_event(Event, ObjState),
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.