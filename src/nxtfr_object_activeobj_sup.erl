%%%-------------------------------------------------------------------
%% @doc nxtfr_object active objects supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(nxtfr_object_activeobj_sup).
-author("christian@flodihn.se").
-behaviour(supervisor).

-export([start/5, stop/1]).
-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => simple_one_for_one,
                 intensity => 10,
                 period => 1},

    {ok, ActiveObjectModule} = application:get_env(nxtfr_object, active_object_module, nxtfr_gen_object),

    NxtfrObjectActiveObj = #{
        id => ActiveObjectModule,
        start => {ActiveObjectModule, start_link, []},
        restart => transient},

    ChildSpecs = [NxtfrObjectActiveObj],
    {ok, {SupFlags, ChildSpecs}}.

%% external functions

start(Uid, CallbackModule, ObjState, Registry, TickFrequency) ->
    supervisor:start_child(?MODULE, [Uid, CallbackModule, ObjState, Registry, TickFrequency]).

stop(ChildPid) ->
    supervisor:terminate_child(?MODULE, ChildPid).