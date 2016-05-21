%% Copyright (c) 2012-2016 Peter Morgan <peter.james.morgan@gmail.com>
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

-module(tepid_tcp_advertiser).

-export([instances/0]).
-export([service/0]).

service() ->
    "_tepid._tcp".

instances() ->
    Hostname = net_adm:localhost(),
    Port = tepid_config:port(http),
    Id = integer_to_list(erlang:phash2({Hostname, Port}), 16),
    [#{hostname => Hostname,
       port => Port,
       instance => instance(Id, Hostname),
       properties => #{host => Hostname,
                       env => tepid_config:environment(),
                       id => Id,
                       vsn => tepid:vsn()},
       priority => 0,
       weight => 0}].


instance(Node, Hostname) ->
    Node ++ "@" ++ Hostname ++ "." ++ service() ++ mdns_config:domain().
