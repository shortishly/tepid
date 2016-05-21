%% Copyright (c) 2016 Peter Morgan <peter.james.morgan@gmail.com>
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(tepid_app).
-behaviour(application).

-export([start/2]).
-export([stop/1]).

start(_Type, _Args) ->
    try
        {ok, Sup} = tepid_sup:start_link(),
        _ = start_advertiser(tepid_tcp_advertiser),
        [tepid:trace(true) || tepid_config:enabled(debug)],
        {ok, Sup, #{listeners => [start_http(http)]}}
    catch
        _:Reason ->
            {error, Reason}
    end.


stop(#{listeners := Listeners}) ->
    lists:foreach(fun cowboy:stop_listener/1, Listeners);
stop(_State) ->
    ok.


start_advertiser(Advertiser) ->
    _ = [mdns_discover_sup:start_child(Advertiser) || tepid_config:can(discover)],
    _ = [mdns_advertise_sup:start_child(Advertiser) || tepid_config:can(advertise)].


start_http(Prefix) ->
    {ok, _} = cowboy:start_http(
                Prefix,
                tepid_config:acceptors(Prefix),
                [{port, tepid_config:port(Prefix)}],
                [{env, [dispatch(Prefix)]}]),
    Prefix.


dispatch(Prefix) ->
    {dispatch, cowboy_router:compile(resources(Prefix))}.

resources(http) ->
    [{'_', endpoints()}].


endpoints() ->
    [endpoint(v2, "/members", tepid_v2_members_resource),
     endpoint(v2, "/keys/[...]", tepid_v2_keys_resource)].

endpoint(Endpoint, Pattern, Module) ->
    endpoint(Endpoint, Pattern, Module, []).

endpoint(Endpoint, undefined, Module, Parameters) ->
    {tepid_config:endpoint(Endpoint), Module, Parameters};

endpoint(Endpoint, Pattern, Module, Parameters) ->
    {tepid_config:endpoint(Endpoint) ++ Pattern, Module, Parameters}.
    
