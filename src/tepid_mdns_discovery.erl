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

-module(tepid_mdns_discovery).
-behaviour(gen_server).

-export([code_change/3]).
-export([discovered/0]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([init/1]).
-export([start_link/0]).
-export([terminate/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

discovered() ->
    gen_server:call(?MODULE, discovered).

init([]) ->
    case tepid_config:can(mesh) of
        true ->
            mdns:subscribe(advertisement),
            {ok, #{discovered => #{}}};

        false ->
            ignore
    end.

handle_call(discovered, _, #{discovered := Discovered} = State) ->
    {reply, Discovered, State}.

handle_cast(_, State) ->
    {stop, error, State}.

handle_info({_,
             {mdns, advertisement},
             #{advertiser := tepid_tcp_advertiser,
               id := Id,
               env := Env,
               port := Port,
               ttl := TTL,
               ip := Host}},
            #{discovered := Discovered} = Data) when TTL > 0 ->
    case tepid_config:environment() of
        Env ->
            {noreply, Data#{discovered := Discovered#{Id => #{ip => Host, port => Port}}}};
        _ ->
            {noreply, Data}
    end;

handle_info({_,
             {mdns, advertisement},
             #{advertiser := tepid_tcp_advertiser,
               id := Id,
               ttl := 0}},
            #{discovered := Discovered} = Data) ->
    {noreply, Data#{discovered := maps:without([Id], Discovered)}};

handle_info({_,
             {mdns, advertisement},
             #{advertiser := _}},
            Data) ->
    {noreply, Data}.

terminate(_, _) ->
    ok.

code_change(_, State, _) ->
    {ok, State}.

