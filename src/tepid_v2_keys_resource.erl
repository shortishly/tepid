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


-module(tepid_v2_keys_resource).

-export([init/2]).
-export([info/3]).
-export([terminate/3]).


init(Req, _) ->
    init(
      Req,
      cowboy_req:method(Req),
      tepid_mdns_tansu_discovery:discovered(),
      key(Req),
      maps:from_list(cowboy_req:parse_qs(Req))).

init(Req, Method, Discovered, Key, QS) when map_size(Discovered) > 0 ->
    #{host := Host, port := Port} = pick_one_from(maps:values(Discovered)),
    {ok, Origin} = gun:open(Host, Port, #{transport => tcp}),
    {cowboy_loop,
     Req,
     #{monitor => erlang:monitor(process, Origin),
       proxy => ?MODULE,
       key => Key,
       origin => Origin,
       headers => maps:from_list(cowboy_req:headers(Req)),
       qs => QS,
       method => Method}};
init(Req, _, _, _, _) ->
    service_unavailable(Req, #{}).




pick_one_from(L) ->
    lists:nth(random:uniform(length(L)), L).

info({gun_up, Origin, _}, Req, #{origin := Origin} = State) ->
    %% A http connection to origin is up and available, proxy
    %% client request through to the origin.
    {ok, Req, maybe_request_body(Req, State)};

info({gun_response, _, _, nofin, Status, Headers}, Req, #{qs := #{<<"wait">> := <<"true">>}} = State) ->
    %% We have an initial http response from the origin together with
    %% some headers to forward to the client.
    {ok,
     cowboy_req:chunked_reply(
       Status,
       headers(maps:merge(maps:from_list(Headers), #{<<"content-type">> => <<"application/json">>})),
       Req),
     State#{origin => #{headers => maps:from_list(Headers), status => Status}, data => <<>>}};

info({gun_response, _, _, nofin, Status, Headers}, Req, State) ->
    %% We have an initial http response from the origin together with
    %% some headers to forward to the client.
    {ok,
     Req,
     State#{origin => #{headers => maps:from_list(Headers), status => Status}, data => <<>>}};

info({gun_response, _, _, fin, 404 = Status, Headers}, Req, #{key := Key} = State) ->
    {stop,
     cowboy_req:reply(
       Status,
       headers(maps:merge(maps:from_list(Headers), #{<<"content-type">> => <<"application/json">>})),
       add_newline(
         jsx:encode(
           #{errorCode => 100,
             message => <<"Key not found">>,
             cause => Key,
             index => index(Headers)
            })),
       Req),
     State};

info({gun_response, _, _, fin, 409, Headers}, Req, #{key := Key, qs := #{<<"prevExist">> := <<"false">>}} = State) ->
    {stop,
     cowboy_req:reply(
       412,
       headers(maps:merge(maps:from_list(Headers), #{<<"content-type">> => <<"application/json">>})),
       add_newline(
         jsx:encode(
           #{errorCode => 105,
             message => <<"Key already exists">>,
             cause => Key,
             index => index(Headers)
            })),
       Req),
     State};

info({gun_response, _, _, fin, 409, Headers}, Req, #{qs := #{<<"prevValue">> := Previous}} = State) ->
    {stop,
     cowboy_req:reply(
       412,
       headers(maps:merge(maps:from_list(Headers), #{<<"content-type">> => <<"application/json">>})),
       add_newline(
         jsx:encode(
           #{errorCode => 101,
             message => <<"Compare failed">>,
             cause => <<"Compare failed: ", Previous/bytes>>,
             index => index(Headers)
            })),
       Req),
     State};

info({gun_response, _, _, fin, 201 = Status, Headers}, Req, #{key := Key, method := <<"PUT">>, qs := #{<<"dir">> := <<"true">>}} = State) ->
    {stop,
     cowboy_req:reply(
       Status,
       headers(maps:merge(maps:from_list(Headers), #{<<"content-type">> => <<"application/json">>})),
       add_newline(
         jsx:encode(
           #{action => set,
             node => add_node_ttl(
                       #{key => Key,
                         dir => true,
                         modifiedIndex => index(Headers),
                         createdIndex => index(Headers)},
                       Headers)})),
       Req),
     State};

info({gun_response, _, _, fin, 201 = Status, Headers}, Req, #{key := Key, method := <<"PUT">>} = State) ->
    {stop,
     cowboy_req:reply(
       Status,
       headers(maps:merge(maps:from_list(Headers), #{<<"content-type">> => <<"application/json">>})),
       add_newline(
         jsx:encode(
           #{action => set,
             node => add_node_ttl(
                       #{key => Key,
                         modifiedIndex => index(Headers),
                         createdIndex => index(Headers)},
                       Headers)})),
       Req),
     State};

info({gun_response, _, _, fin, 204, Headers}, Req, #{key := Key, method := <<"PUT">>, qs := #{<<"prevIndex">> := PrevIndex}} = State) ->
    {stop,
     cowboy_req:reply(
       200,
       headers(maps:merge(maps:from_list(Headers), #{<<"content-type">> => <<"application/json">>})),
       add_newline(
         jsx:encode(
           #{action => compareAndSwap,
             node => add_node_ttl(
                       #{key => Key,
                         modifiedIndex => index(Headers),
                         createdIndex => index(Headers)}, Headers),
             prevNode => #{key => Key,
                           modifiedIndex => any:to_integer(PrevIndex),
                           createdIndex => any:to_integer(PrevIndex)}})),
       Req),
     State};

info({gun_response, _, _, fin, 204, Headers}, Req, #{key := Key, method := <<"PUT">>, qs := #{<<"prevExist">> := <<"true">>}} = State) ->
    {stop,
     cowboy_req:reply(
       200,
       headers(maps:merge(maps:from_list(Headers), #{<<"content-type">> => <<"application/json">>})),
       add_newline(
         jsx:encode(
           #{action => update,
             node => add_node_ttl(
                       #{key => Key,
                         modifiedIndex => index(Headers),
                         createdIndex => index(Headers)}, Headers),
             prevNode => #{key => Key,
                           modifiedIndex => index(Headers),
                           createdIndex => index(Headers)}})),
       Req),
     State};

info({gun_response, _, _, fin, 204, Headers}, Req, #{key := Key, method := <<"PUT">>} = State) ->
    {stop,
     cowboy_req:reply(
       200,
       headers(maps:merge(maps:from_list(Headers), #{<<"content-type">> => <<"application/json">>})),
       add_newline(
         jsx:encode(
           #{action => set,
             node => add_node_ttl(
                       #{key => Key,
                         modifiedIndex => index(Headers),
                         createdIndex => index(Headers)}, Headers),
             prevNode => #{key => Key,
                           modifiedIndex => index(Headers),
                           createdIndex => index(Headers)}})),
       Req),
     State};

info({gun_response, _, _, fin, Status, Headers}, Req, State) ->
    %% short and sweet, we have final http response from the origin
    %% with just status and headers and no response body.
    {stop, cowboy_req:reply(Status, headers(Headers), Req), State};

info({gun_data, _, _, nofin, Data}, Req, #{key := Key, data := Partial, origin := #{headers := Headers}, qs := #{<<"wait">> := <<"true">>}} = State) ->
    %% Tansu supplies a server sent event stream of change events to
    %% the key store, which are separated by "\n\n".
    case binary:split(<<Partial/bytes, Data/bytes>>, <<"\n\n">>) of

        [Message, _Remainder] ->
            case binary:split(Message, <<"\n">>, [global]) of
                [<<"id: ", Id/bytes>>, <<"event: ", Event/bytes>>, <<"data: ", Compound/bytes>>] ->
                    ok = cowboy_req:chunk(notification(
                                            Key,
                                            Id,
                                            Event,
                                            Headers,
                                            jsx:decode(Compound, [return_maps])),
                                          Req),
                    {stop, Req, State}
            end;
        _ ->
            {ok, Req, State#{data => <<Partial/bytes, Data/bytes>>}}
    end;

info({gun_data, _, _, nofin, Data}, Req, #{data := Partial} = State) ->
    {ok, Req, State#{data => <<Partial/bytes, Data/bytes>>}};

info({gun_data, _, _, fin, Data}, Req, #{key := ParentKey, method := <<"GET">>, origin := #{status := 200, headers := #{<<"content-type">> := <<"application/json">>} = Headers}, data := Partial} = State) ->
    ResponseBody = case jsx:decode(<<Partial/bytes, Data/bytes>>, [return_maps]) of
                       #{<<"children">> := Children} ->
                           jsx:encode(
                             #{action => get,
                               node => add_node_ttl(#{key => ParentKey,
                                                      dir => true,
                                                      modifiedIndex => index(Headers),
                                                      createdIndex => index(Headers),
                                                      nodes => maps:fold(
                                                                 fun
                                                                     (Key, #{<<"value">> := Value}, A) ->
                                                                         [#{key => Key, value => Value, modifiedIndex => index(Headers), createdIndex => index(Headers)} | A]
                                                                 end,
                                                                 [],
                                                                 Children)},
                                                    Headers)})
                   end,
    {stop, cowboy_req:reply(200, headers(Headers), add_newline(ResponseBody), Req), State};

info({gun_data, _, _, fin, Data}, Req, #{key := Key, method := <<"GET">>, origin := #{status := 200, headers := Headers}, data := Partial} = State) ->
    ResponseBody = case <<Partial/bytes, Data/bytes>> of
                       <<"etcd.dir">> ->
                           jsx:encode(
                             #{action => get,
                               node => add_node_ttl(#{key => Key,
                                                      modifiedIndex => index(Headers),
                                                      createdIndex => index(Headers),
                                                      dir => true},
                                                    Headers)});
                       Value ->
                           jsx:encode(
                             #{action => get,
                               node => add_node_ttl(#{key => Key,
                                                      modifiedIndex => index(Headers),
                                                      createdIndex => index(Headers),
                                                      value => Value},
                                                    Headers)})
                   end,
    {stop, cowboy_req:reply(200, headers(Headers), add_newline(ResponseBody), Req), State};


info({request_body, #{complete := Data}},
     Req,
     #{key := Key,
       headers := #{<<"content-type">> := <<"application/x-www-form-urlencoded">>},
       qs := QS,
       partial := Partial} = State) ->
    %% The client has streamed the http request body to us, and we
    %% have received the last chunk, forward the chunk to the origin
    %% letting them know not to expect any more.
    BodyQS = maps:from_list(cow_qs:parse_qs(<<Partial/bytes, Data/bytes>>)),
    Request = proxy(<<"/api/keys", Key/bytes>>, State#{qs := maps:merge(QS, maps:with([<<"ttl">>], BodyQS))}, qs(<<>>, BodyQS)),
    {ok, Req, maps:without([partial], State#{request => Request})};

info({request_body, #{more := More}},
     Req,
     #{headers := #{<<"content-type">> := <<"application/x-www-form-urlencoded">>},
       partial := Partial} = State) ->
    %% The client is streaming the http request body to us.
    {ok, Req, request_body(Req, State#{partial := <<Partial/bytes, More/bytes>>})};



info({'DOWN', Monitor, _, _, _}, Req, #{monitor := Monitor} = State) ->
    %% whoa, our monitor has noticed the http connection to the origin
    %% is emulating a Norwegian Blue parrot, time to declare to the
    %% client that the gateway has turned bad.
    bad_gateway(Req, State).


terminate(_Reason, _Req, #{origin := Origin, monitor := Monitor}) ->
    %% we are terminating and have a monitored connection to the
    %% origin, try and be a nice citizen and demonitor and pull the
    %% plug on the connection to the origin.
    erlang:demonitor(Monitor),
    gun:close(Origin);

terminate(_Reason, _Req, #{origin := Origin}) ->
    %% we are terminating and just have a connection to the origin,
    %% try and pull the plug on it.
    gun:close(Origin);

terminate(_Reason, _Req, _) ->
    ok.

add_node_ttl(Node, Headers) when is_list(Headers) ->
    add_node_ttl(Node, maps:from_list(Headers));
add_node_ttl(Node, Headers) ->
    maps:fold(
      fun
          (<<"ttl">>, Seconds, A) ->
              TTL = any:to_integer(Seconds),
              Now = calendar:datetime_to_gregorian_seconds(erlang:universaltime()),
              {{Year, Month, Date}, {Hour, Minute, Second}} = calendar:gregorian_seconds_to_datetime(Now + TTL),
              Expiration = iolist_to_binary(
                             io_lib:format(
                               "~4..0w-~2..0w-~2..0wT~2..0w:~2..0w:~2..0w.000000000Z",
                               [Year, Month, Date, Hour, Minute, Second])),
              A#{ttl => TTL, expiration => Expiration};
          (_, _, A) ->
              A
      end,
      Node,
      Headers).

maybe_request_body(_, #{key := Key, method := <<"PUT">>, qs := #{<<"dir">> := <<"true">>}, headers := Headers} = S0) ->
    S1 = S0#{headers := Headers#{<<"content-type">> => <<"application/x-www-form-urlencoded">>}},
    S1#{request => proxy(<<"/api/keys", Key/bytes>>, S1, <<"value=etcd.dir">>)};

maybe_request_body(Req, State) ->
    has_body(Req, State).

has_body(Req, #{key := Key} = State) ->
    case cowboy_req:has_body(Req) of
        true ->
            %% We have a http request body, start streaming it from
            %% the client.
            request_body(Req, State#{partial => <<>>});

        false ->
            %% There is no request body from the client, time to move
            %% on. Proxy the http request through to the origin.
            State#{request => proxy(<<"/api/keys", Key/bytes>>, State)}
    end.


request_body(Req, State) ->
    %% We are streaming the request body from the client
    case cowboy_req:body(Req) of
        {ok, Data, _} ->
            %% We have streamed all of the request body from the
            %% client.
            self() ! {request_body, #{complete => Data}},
            State;

        {more, Data, _} ->
            %% We have part of the request body, but there is still
            %% more waiting for us.
            self() ! {request_body, #{more => Data}}
    end.


proxy(Path, #{origin := Origin, method := Method, qs := QS, headers := Headers}, Body) ->
    %% Act as a proxy for a http request to the origin from the
    %% client.
    proxy_request(Origin, Method, <<Path/bytes, (qs(<<"?">>, QS))/bytes>>, headers(QS, Headers), Body).

proxy(Path, #{origin := Origin, method := Method, qs := QS, headers := Headers}) ->
    %% Act as a proxy for a http request to the origin from the
    %% client.
    proxy_request(Origin, Method, <<Path/bytes, (qs(<<"?">>, QS))/bytes>>, headers(QS, Headers)).

proxy_request(Origin, Method, PathQS, Headers, Body) ->
    gun:request(
      Origin,
      Method,
      PathQS,
      [{<<"content-length">>, any:to_binary(byte_size(iolist_to_binary(Body)))} | Headers],
      Body).

proxy_request(Origin, Method, PathQS, Headers) ->
    gun:request(Origin, Method, PathQS, Headers).

headers(QS, Headers) ->
    maps:fold(
      fun
          (<<"ttl">>, TTL, A) ->
              %% TTL is a header in Tansu and not part of the query
              %% string.
              [{<<"ttl">>, TTL} | A];


          (<<"accept-encoding">>, _, A) ->
              A;

          (_, _, A) ->
              A
      end,
      maps:to_list(maps:without([<<"content-length">>], Headers)),
      QS).

qs(Prefix, QS) ->
    maps:fold(
      fun
          (<<"wait">>, <<"true">>, A) ->
              %% Tansu uses "stream" rather than "waiting".
              append_to_qs(Prefix, <<"stream">>, <<"true">>, A);

          (<<"prevExist">> = K, V, A) ->
              append_to_qs(Prefix, K, V, A);

          (<<"value">> = K, V, A) ->
              append_to_qs(Prefix, K, V, A);

          (<<"prevValue">> = K, V, A) ->
              append_to_qs(Prefix, K, V, A);

          (<<"recursive">>, <<"true">> = Value, A) ->
              append_to_qs(Prefix, <<"children">>, Value, A);

          (<<"prevIndex">>, _, A) ->
              A;

          (<<"recursive">>, _, A) ->
              A;

          (<<"ttl">>, _, A) ->
              A;

          (<<"waitIndex">>, _, A) ->
              A;

          (<<"dir">>, _, A) ->
              A;

          (<<"quorum">>, <<"true">>, A) ->
              append_to_qs(Prefix, <<"role">>, <<"leader">>, A);

          (<<"quorum">>, _, A) ->
              A;

          (<<"sorted">>, _, A) ->
              A
      end,
      <<>>,
      QS).


append_to_qs(Prefix, Key, Value, <<>>) ->
    <<Prefix/bytes, Key/bytes, "=", Value/bytes>>;
append_to_qs(_, Key, Value, A) ->
    <<A/bytes, "&", Key/bytes, "=", Value/bytes>>.



bad_gateway(Req, State) ->
    stop_with_code(502, Req, State).
                
service_unavailable(Req, State) ->
    stop_with_code(503, Req, State).

stop_with_code(Code, Req, State) ->
    {ok, cowboy_req:reply(Code, Req), State}.

key(Req) ->
    slash_separated(cowboy_req:path_info(Req)).

slash_separated(PathInfo) ->
    lists:foldl(
      fun
          (Path, <<>>) ->
              <<"/", Path/bytes>>;
          (Path, A) ->
              <<A/bytes, "/", Path/bytes>>
      end,
      <<>>,
      PathInfo).


index(Headers) when is_list(Headers) ->
    index(maps:from_list(Headers));
index(#{<<"tansu-raft-la">> := Index}) ->
    any:to_integer(Index).


headers(Headers) when is_list(Headers) ->
    headers(maps:from_list(Headers));
headers(Headers) ->
    maps:fold(
      fun
          (<<"content-length">>, _, A) ->
              A;

          (<<"transfer-encoding">>, _, A) ->
              A;
          (<<"content-type">>, _, A) ->
              [{<<"content-type">>, <<"application/json">>} | A];

          (<<"tansu-role">>, _, A) ->
              A;

          (<<"tansu-raft-term">>, V, A) ->
              [{<<"X-Raft-Term">>, V} | A];

          (<<"tansu-raft-la">>, V, A) ->
              [{<<"X-Raft-Index">>, V}, {<<"X-Etcd-Index">>, V} | A];

          (<<"tansu-raft-ci">>, _, A) ->
              A;

          (<<"tansu-node-id">>, _, A) ->
              A;

          (<<"tansu-env">>, _, A) ->
              A;

          (<<"tansu-cluster-id">>, V, A) ->
              [{<<"X-Etcd-Cluster-Id">>, V} | A];

          (<<"ttl">>, _, A) ->
              A;

          (<<"accept-encoding">>, _, A) ->
              A;

          (<<"user-agent">>, _, A) ->
              A;

          (Header, Value, A) ->
              [{Header, Value} | A]
      end,
      [],
      Headers).

notification(Key, _Id, Event, Headers, #{<<"value">> := Value} = Data) ->
    jsx:encode(#{action => event(Event, Data),
                 node => add_node_ttl(#{key => Key,
                                        value => Value,
                                        modifiedIndex => index(Headers),
                                        createdIndex => index(Headers)},
                                      Data),
                 prevNode => add_node_ttl(#{key => Key,
                                            value => Value,
                                            modifiedIndex => index(Headers),
                                            createdIndex => index(Headers)},
                                          Data)}).

event(_, #{<<"type">> := <<"cas">>}) ->
    <<"compareAndSwap">>;
event(Event, _) ->
    Event.

add_newline(Response) ->
    [Response, <<"\n">>].
