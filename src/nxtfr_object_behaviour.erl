-module(nxtfr_object_behaviour).
-export([behaviour_info/1]).

behaviour_info(callbacks) ->
    [
        {tick, 2},
        {tick, 3},
        {on_event, 3},
        {on_message, 3},
        {start, 2},
        {stop, 2}
    ];

behaviour_info(_Other) ->
    undefined.