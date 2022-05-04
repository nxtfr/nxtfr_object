%%%-------------------------------------------------------------------
%% @doc nxtfr_object active objects supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(nxtfr_object_activeobj_sup).
-author("christian@flodihn.se").
-behaviour(supervisor).

-export([start/2, stop/1]).
-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => simple_one_for_one,
                 intensity => 10,
                 period => 1},

    NxtfrObjectActiveObj = #{
        id => nxtfr_object_activeobj,
        start => {nxtfr_object_activeobj, start_link, []},
        restart => transient},

    ChildSpecs = [NxtfrObjectActiveObj],
    {ok, {SupFlags, ChildSpecs}}.

%% external functions

start(CallbackModule, ObjState) ->
    supervisor:start_child(?MODULE, [CallbackModule, ObjState]).

stop(ChildPid) ->
    supervisor:terminate_child(?MODULE, ChildPid).