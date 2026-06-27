// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist_hot_app_runtime

import "core:strings"
import kvist_hot "../kvist_hot"

Run_Host :: struct {
    reloader:          ^kvist_hot.Reloader,
    reload_requested:  bool,
    checkpoint_error:  string,
}

run_host_init :: proc(reloader: ^kvist_hot.Reloader) -> Run_Host {
    return Run_Host{
        reloader = reloader,
    }
}

run_host_begin_cycle :: proc(host: ^Run_Host) {
    host.reload_requested = false
    if host.checkpoint_error != "" {
        delete(host.checkpoint_error)
        host.checkpoint_error = ""
    }
}

checkpoint :: proc(host: ^Run_Host) -> bool {
    if host.reloader == nil {
        return false
    }
    changed, change_err, change_ok := kvist_hot.source_changed(host.reloader)
    if !change_ok {
        if host.checkpoint_error != "" {
            delete(host.checkpoint_error)
        }
        host.checkpoint_error = change_err
        return true
    }
    if changed {
        host.reload_requested = true
        return true
    }
    return false
}
