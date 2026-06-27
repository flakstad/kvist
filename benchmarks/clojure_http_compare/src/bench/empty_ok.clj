;; Copyright (c) Andreas Flakstad and Kvist contributors
;; SPDX-License-Identifier: MIT

(ns bench.empty-ok
  (:require [org.httpkit.server :as hk])
  (:gen-class))

(defn parse-port []
  (Long/parseLong (or (System/getenv "PORT") "6970")))

(defn app [_]
  {:status 200
   :body ""})

(defn -main [& _]
  (let [port (parse-port)
        stop-fn (hk/run-server #'app {:port port})]
    (.addShutdownHook (Runtime/getRuntime)
                      (Thread. ^Runnable
                               (fn []
                                 (stop-fn :timeout 1000))))
    (println (str "clojure empty-ok listening on " port))
    @(promise)))
