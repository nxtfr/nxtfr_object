%%%-------------------------------------------------------------------
%% @doc nxtfr_object top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(nxtfr_object_sup).
-author("christian@flodihn.se").
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_all,
                 intensity => 10,
                 period => 1},
    NxtfrObject = #{
        id => next_object,
        start => {nxtfr_object, start_link, []},
        type => worker
    },
    ChildSpecs = [NxtfrObject],
    {ok, {SupFlags, ChildSpecs}}.