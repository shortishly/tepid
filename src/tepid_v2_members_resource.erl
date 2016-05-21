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

-module(tepid_v2_members_resource).

-export([init/2]).

init(Req, Opts) ->
    {ok,
     cowboy_req:reply(
       200,
       [{<<"content-type">>, <<"application/json">>}],
       jsx:encode(
         #{members => maps:fold(
                        fun
                            (Id, #{ip := IP, port := Port}, A) ->
                                [#{id => any:to_binary(Id),
                                   name => any:to_binary(Id),
                                   peerURLs => [url(IP, Port)],
                                   clientURLs => [url(IP, Port)]} | A]
                        end,
                        [],
                        tepid_mdns_discovery:discovered())}),
       Req),
     Opts}.

url(IP, Port) when is_binary(IP) andalso is_binary(Port) ->
    <<"http://", IP/bytes, ":", Port/bytes>>;

url(IP, Port) ->
    url(any:to_binary(inet:ntoa(IP)), any:to_binary(Port)).
