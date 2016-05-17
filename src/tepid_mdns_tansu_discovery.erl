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

-module(tepid_mdns_tansu_discovery).
-behaviour(gen_server).

-export([code_change/3]).
-export([discovered/0]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([init/1]).
-export([service/0]).
-export([start_link/0]).
-export([stop/0]).
-export([terminate/2]).

-define(SERVICE, "_tansu._tcp").

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

discovered() ->
    gen_server:call(?MODULE, discovered).

stop() ->
    gen_server:cast(?MODULE, stop).

init([]) ->
    mdns_discover_sup:start_child(?MODULE),
    mdns:subscribe(advertisement),
    {ok, #{env => tepid_config:environment(), discovered => #{}}}.

handle_call(discovered, _, #{discovered := Discovered} = State) ->
    {reply, Discovered, State}.

handle_cast(stop, State) ->
    {stop, normal, State}.

handle_info({mdns_advertisement, #{service := ?SERVICE, ttl := 0}}, State) ->
    %% ignore "goodbyes" for the moment
    {noreply, State};

handle_info({_,
             {mdns, advertisement},
             #{service := ?SERVICE,
               id := Id,
               env := Env,
               port := Port,
               ip := IP}},
            #{env := Env, discovered := Discovered} = State) ->
    {noreply, State#{discovered := Discovered#{any:to_binary(Id) => #{host => inet:ntoa(IP), port => Port}}}};

handle_info({_, {mdns, advertisement}, _}, Data) ->
    {noreply, Data}.

terminate(_, _) ->
    ok.

code_change(_, State, _) ->
    {ok, State}.

service() ->
    ?SERVICE.
