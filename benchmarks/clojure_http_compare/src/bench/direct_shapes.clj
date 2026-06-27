;; Copyright (c) Andreas Flakstad and Kvist contributors
;; SPDX-License-Identifier: MIT

(ns bench.direct-shapes
  (:require [cheshire.core :as json]
            [org.httpkit.server :as hk])
  (:gen-class))

(defn parse-port []
  (Long/parseLong (or (System/getenv "PORT") "6970")))

(defn parse-shape []
  (or (System/getenv "SHAPE") "pong"))

(def json-static
  "{\"message\":\"pong\",\"count\":1,\"ok\":true,\"service\":\"clojure-http\",\"env\":\"bench\",\"user\":\"load-test\",\"stats\":{\"latency_ms\":12,\"cpu_pct\":37,\"mem_mb\":128},\"meta\":{\"request_id\":\"req-123456789\",\"build\":\"2026.06.01\",\"region\":\"eu-north-1\"},\"note\":\"Longer JSON payload for rough comparison.\"}")

(defn app-for-shape [shape]
  (case shape
    "pong"
    (fn [_]
      {:status 200
       :headers {"content-type" "text/plain"}
       :body "pong"})

    "plain"
    (fn [_]
      {:status 200
       :headers {"content-type" "text/plain"}
       :body json-static})

    "json"
    (fn [_]
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

    (fn [_]
      {:status 404
       :body "unknown shape"})))

(defn -main [& _]
  (let [port (parse-port)
        shape (parse-shape)
        stop-fn (hk/run-server (app-for-shape shape) {:port port})]
    (.addShutdownHook (Runtime/getRuntime)
                      (Thread. ^Runnable
                               (fn []
                                 (stop-fn :timeout 1000))))
    (println (str "clojure direct-shapes listening on " port " shape=" shape))
    @(promise)))
