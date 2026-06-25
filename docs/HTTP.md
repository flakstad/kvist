# HTTP

`kvist:http` is a thin, practical wrapper over the vendored Odin HTTP package.
It keeps routing, responses, sessions, clients, SSE, and Datastar helpers close
to the generated Odin code.

The surface is split into small packages:

- `kvist:http` - routers, handlers, responses, cookies, middleware, rate limits.
- `kvist:http/client` - client requests and responses.
- `kvist:http/session` - cookie session and CSRF planning.
- `kvist:http/sse` - server-sent events.
- `kvist:http/datastar` - Datastar patch events over SSE.

## A Small Server

The usual server shape is explicit: make a router, make a server, destroy the
router, register routes, then listen.

```clojure
(import http "kvist:http")

(defn main []
  (let [router (http.new-router)
        server (http.new-server)]
    (defer (http.router-destroy! router))

    (http.get! router "/ping" [req res]
      (http.respond-plain res "pong"))

    (http.server-shutdown-on-interrupt! server)
    (http.listen-and-serve! server router 6969)))
```

For a scoped router, use `http.with-router`. It creates the router, binds it for
the body, and destroys it when the scope exits:

```clojure
(http.with-router [router]
  (let [server (http.new-server)]
    (http.get! router "/ping" [req res]
      (http.respond-plain res "pong"))

    (http.server-shutdown-on-interrupt! server)
    (http.listen-and-serve! server router 6969)))
```

Routes bind request and response pointers:

```clojure
(http.get! router "/hello/(%w+)" [req res]
  (let [params req^.url_params]
    (http.respond-plain res params[0])))
```

Route registration mutates the router. Bang names are not decoration here.

## Routes And Responses

The route macros cover the common methods:

```clojure
(http.get! router path [req res] ...)
(http.post! router path [req res] ...)
(http.put! router path [req res] ...)
(http.patch! router path [req res] ...)
(http.delete! router path [req res] ...)
(http.all! router path [req res] ...)
```

Route registration mutates the router, so route macros use bang names only.

Response helpers stay close to the vendor API:

```clojure
(http.respond-ok res)
(http.respond-plain res "pong")
(http.respond-html res page)
(http.respond-json res value)
(http.respond-file res "public/index.html")
(http.respond-file-content res "index.html" content)
```

Use `http.respond-html` with strings you already trust or rendered with
`kvist:html`; it sends the HTML as provided.

## Handlers And Middleware

`http.handler` creates a handler value:

```clojure
(let [app (http.handler [req res]
            (http.respond-plain res "ok"))]
  ...)
```

`http.middleware` wraps a next handler and can call it with `http.handle!`:

```clojure
(let [mw (http.middleware app [next req res]
           (http.set-cookie! res "visited" "yes")
           (http.handle! next req res))]
  ...)
```

Rate limiting is middleware-shaped too:

```clojure
(let [opts (http.new-rate-limit-opts time.Second 5)
      data (http.new-rate-limit-data)]
  (defer (http.rate-limit-destroy! data))
  (http.rate-limit data next opts))
```

## Cookies And Sessions

Use the small cookie helpers for direct request/response work:

```clojure
(let [[sid ok] (http.request-cookie req "sid")]
  ...)

(http.set-cookie! res "sid" sid)
```

`kvist:http/session` gives you a tiny plan/apply flow for cookie sessions and
CSRF checks:

```clojure
(import session "kvist:http/session")

(let [opts (session.new-opts "sid" "csrf" new-sid csrf-for request-csrf)
      plan (session.plan req opts)]
  (session.apply-plan! res opts plan)
  (if (session.accepted? plan)
    (http.respond-plain res plan.sid)
    (session.reject! res)))
```

The session package makes a decision; your route still decides what to serve.
Good. Magic sessions are where bugs rent office space.

## Client Requests

`kvist:http/client` mirrors the explicit lifetime style:

```clojure
(import client "kvist:http/client")

(let [[res err] (client.get "http://127.0.0.1:6969/ping")]
  (if (= err nil)
    (do
      (defer (client.response-destroy res))
      (= res.status .OK))
    false))
```

For custom requests:

```clojure
(let [req (client.new-request .Post)]
  (defer (client.request-destroy req))
  (client.set-header! req "x-api-key" "demo")
  (client.add-cookie! req "session" "abc")
  (client.with-json req value)
  (client.request req "http://127.0.0.1:6969/hello"))
```

Or use `client.with-request` for the scoped form:

```clojure
(client.with-request [req .Post]
  (client.set-header! req "x-api-key" "demo")
  (client.add-cookie! req "session" "abc")
  (client.with-json req value)
  (client.request req "http://127.0.0.1:6969/hello"))
```

Destroy request and response state when you own it.

## SSE And Datastar

For a short SSE response, `sse.with-stream` is enough:

```clojure
(import sse "kvist:http/sse")

(http.get! router "/events" [req res]
  (sse.with-stream [stream res]
    (sse.comment! stream "connected")
    (sse.retry! stream 1000)
    (sse.send-event! stream "welcome" "ready")
    (sse.close! stream)))
```

For long-lived streams, define callbacks:

```clojure
(sse.on-error on-err [stream err]
  (println "client disconnected"))

(sse.on-timeout tick [_op stream]
  (when (not (sse.closed? stream))
    (sse.send-event! stream "tick" "ok")
    (sse.schedule-timeout! time.Second stream tick)))
```

Datastar helpers send named SSE events:

```clojure
(import dstar "kvist:http/datastar")

(dstar.patch-elements! stream "<div id='status'>Ready</div>")
(dstar.patch-signals! stream "{connected: true}")
(dstar.execute-script! stream "console.log('ready')")
```

## Examples

- [`examples/web/http-server.kvist`](../examples/web/http-server.kvist) - small
  router and JSON response.
- [`examples/web/http-client.kvist`](../examples/web/http-client.kvist) - client
  GET and POST request setup.
- [`examples/web/http-session.kvist`](../examples/web/http-session.kvist) -
  session planning.
- [`examples/web/http-sse.kvist`](../examples/web/http-sse.kvist) - short SSE
  stream.
- [`examples/web/http-sse-live.kvist`](../examples/web/http-sse-live.kvist) -
  long-lived SSE stream.
- [`examples/web/http-datastar.kvist`](../examples/web/http-datastar.kvist) -
  Datastar events.
