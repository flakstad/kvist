(ns bench.http-compare
  (:require [cheshire.core :as json]
            [org.httpkit.server :as hk])
  (:gen-class))

(defn parse-port []
  (Long/parseLong (or (System/getenv "PORT") "6970")))

(defn sse-frame
  [{:keys [event data comment retry]}]
  (str
   (when comment
     (str ": " comment "\n"))
   (when retry
     (str "retry: " retry "\n"))
   (when event
     (str "event: " event "\n"))
   (when data
     (apply str
            (map #(str "data: " % "\n")
                 (.split ^String data "\n" -1))))
   "\n"))

(defn ping-handler [_]
  {:status 200
   :headers {"content-type" "text/plain"}
   :body "pong"})

(defn empty-handler [_]
  {:status 200
   :body ""})

(defn json-handler [_]
  {:status 200
   :headers {"content-type" "application/json"}
   :body (json/generate-string {:message "pong"
                                :count 1
                                :ok true
                                :service "clojure-http"
                                :env "bench"
                                :user "load-test"
                                :stats {:latency_ms 12
                                        :cpu_pct 37
                                        :mem_mb 128}
                                :meta {:request_id "req-123456789"
                                       :build "2026.06.01"
                                       :region "eu-north-1"}
                                :note "Longer JSON payload for rough comparison."})})

(def json-static
  "{\"message\":\"pong\",\"count\":1,\"ok\":true,\"service\":\"clojure-http\",\"env\":\"bench\",\"user\":\"load-test\",\"stats\":{\"latency_ms\":12,\"cpu_pct\":37,\"mem_mb\":128},\"meta\":{\"request_id\":\"req-123456789\",\"build\":\"2026.06.01\",\"region\":\"eu-north-1\"},\"note\":\"Longer JSON payload for rough comparison.\"}")

(defn json-static-handler [_]
  {:status 200
   :headers {"content-type" "text/plain"}
   :body json-static})

(defn sse-handler [req]
  (hk/with-channel req channel
    (let [open? (atom true)
          worker (future
                   (try
                     (hk/send! channel {:status 200
                                        :headers {"content-type" "text/event-stream"
                                                  "cache-control" "no-cache"
                                                  "connection" "keep-alive"}
                                        :body (sse-frame {:comment "connected"})}
                               false)
                     (hk/send! channel (sse-frame {:retry 1000}) false)
                     (hk/send! channel (sse-frame {:event "welcome" :data "ready"}) false)
                     (loop [n 0]
                       (when @open?
                         (Thread/sleep 1000)
                         (when @open?
                           (hk/send! channel (sse-frame {:event "tick" :data "ok"}) false)
                           (recur (inc n)))))
                     (catch Throwable _
                       nil)))]
      (hk/on-close channel (fn [_status]
                             (reset! open? false)
                             (future-cancel worker))))))

(defn app [req]
  (case (:uri req)
    "/empty" (empty-handler req)
    "/ping" (ping-handler req)
    "/json" (json-handler req)
    "/plain" (json-static-handler req)
    "/events" (sse-handler req)
    {:status 404
     :headers {"content-type" "text/plain"}
     :body "not found"}))

(defn -main [& _]
  (let [port (parse-port)
        stop-fn (hk/run-server #'app {:port port})]
    (.addShutdownHook (Runtime/getRuntime)
                      (Thread. ^Runnable
                               (fn []
                                 (stop-fn :timeout 1000))))
    (println (str "clojure http compare listening on " port))
    @(promise)))
