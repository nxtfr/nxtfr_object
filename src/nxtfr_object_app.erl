%%%-------------------------------------------------------------------
%% @doc nxtfr_object public API
%% @end
%%%-------------------------------------------------------------------

-module(nxtfr_object_app).
-author("christian@flodihn.se").
-behaviour(application).

-export([start/0, start/2, stop/1]).

start() ->
    application:start(nxtfr_object).

start(_StartType, _StartArgs) ->
    nxtfr_object_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
