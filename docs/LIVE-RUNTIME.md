# Optional Live Runtime

This note sketches a long-term idea for Kvist beyond its current role as an
Odin frontend:

- `Kvist/AOT` as the normal source-to-source compiler that emits readable Odin
- `Kvist/Live` as an optional embedded dynamic runtime for commands, hooks,
  reports, tools, and automation inside a compiled program

This is intentionally speculative. It is not the current project direction and
should not pull the core compiler away from its present goals.

## Main Gain

The main gain is not just "a REPL exists." Kvist already has useful
compiler-driven eval-like workflows.

The stronger value is:

- a live programmable control layer inside an otherwise compiled system

That would enable:

- persistent runtime state
- redefinable commands and behaviors without rebuilding the host
- runtime-loaded modules
- application scripting and automation
- a language-native plugin model
- inspection and mutation of a running system through Kvist itself

Without that need, a live runtime is mostly academic overhead.

## What It Would Give You

An optional live runtime could provide:

1. A stateful runtime inside the app.
   Loaded modules stay loaded, values can persist, and commands/hooks can be
   redefined.
2. A plugin language with no language split.
   The host app and the extension language would both be Kvist rather than
   Kvist plus Lua/JS/something else.
3. A real hot-reload boundary.
   Some subsystems would stay compiled and static while others would be live
   and reloadable.
4. An in-app console attached to actual program state.
   This is stronger than scratch-file eval because it targets the running
   system rather than a temporary build artifact.

## Concrete Examples

### 1. Command Layer Inside A Compiled App

Imagine a compiled `ro`-like app.

The static Kvist/Odin side owns:

- database
- event log
- indexing
- sync
- UI/CLI shell
- process lifetime

The live Kvist side owns:

- commands
- reports
- saved queries
- automations
- hooks

So the compiled app exposes a boundary like:

- `register-command`
- `register-hook`
- `find-items`
- `load-item`
- `update-item!`
- `append-event!`
- `print-line`

Then live code can do:

```clojure
(defn stale-items-report [ctx]
  (let [items (find-items ctx {:status :open :updated-before "2026-01-01"})]
    (each [item items]
      (print-line ctx item.title))))
```

And:

```clojure
(defn auto-tag-blocked [ctx event]
  (core.when (= :item/updated event.type)
    (let [item (load-item ctx event.item-id)]
      (core.when (> item.blocked-days 7)
        (update-item! ctx item.id {:tags [:blocked]})))))
```

What is dynamic here:

- reload `stale-items-report`
- redefine `auto-tag-blocked`
- add new commands without rebuilding the app

What stays static:

- storage format
- indexing engine
- event processing core

### 2. In-App Live Console

A compiled app starts with optional live support:

```clojure
(app.start {:live? true})
```

Then inside the app you get a console:

```clojure
> (current-user)
{:id "u1" :name "Andreas"}

> (register-command! :hello
    (fn [ctx args]
      (print-line ctx "hello")))

> (run-command! :hello {})
hello
```

This is not just scratch eval. It is attached to the actual app state.

You can inspect:

- loaded modules
- command registry
- current workspace
- active UI selection
- cached data

You can patch:

- command behavior
- report formatting
- menu actions
- automation rules

### 3. Live Tooling In A Drawing App

Take a drawing app.

Static side:

- rendering
- input loop
- document model
- persistence
- performance-sensitive geometry

Live side:

- tools
- gesture interpretation rules
- exporters
- inspectors
- palette commands

A live tool might look like:

```clojure
(deftool highlighter
  {:cursor :crosshair}
  (fn [ctx stroke]
    (add-element! ctx
      {:type :highlight
       :points stroke.points
       :color :yellow
       :alpha 0.35})))
```

Then while the app runs:

- reload `highlighter`
- add a new tool
- change how selection snapping works
- add a debug overlay
- define a one-off export command

The renderer is not being hot-swapped. The tool and control plane is.

### 4. User Extensions After Deployment

Suppose someone ships a compiled app binary.

With live Kvist enabled, users can drop in:

- `commands/weekly-review.kvist`
- `hooks/on-open.kvist`
- `reports/aging-items.kvist`

At startup:

```clojure
(load-module! runtime "reports/aging-items.kvist")
(load-module! runtime "hooks/on-open.kvist")
```

The compiled app does not know the extension logic ahead of time. It only
knows the extension protocol.

## What The Boundary Looks Like

Live Kvist should not directly mutate arbitrary Odin memory.

Instead, the host exposes capabilities:

```clojure
(defhostapi app
  (find-items [query] -> [:arr :item])
  (load-item [id] -> :item)
  (save-item! [id patch] -> :item)
  (append-event! [event] -> :ok)
  (log! [level text] -> :ok))
```

Live Kvist calls those. Compiled Kvist/Odin implements those.

That means live Kvist acts as a control plane rather than arbitrary engine
surgery.

## Host / Live Split

The safe split looks like this.

Static Kvist/Odin core:

- rendering
- storage engine
- networking
- heavy compute
- resource ownership
- core domain state model
- stable primitive operations

Dynamic Kvist layer:

- commands
- queries
- reports
- automations
- policies
- transforms
- user tools
- inspectors
- glue logic

The static side must be designed for extension points, but not for wholesale
runtime replacement of arbitrary internal functions.

Think:

- command registry
- hook system
- query/report interface
- message/event handlers
- inspector API
- declarative host capabilities exposed to scripts

Not:

- "scripts can redefine any random engine function"

## Packaging

If this idea ever becomes real, the cleaner packaging is a library first:

- `import kvist.live`

rather than a vague global compiler mode.

That keeps:

- dependency opt-in explicit
- architecture visible at the source level
- per-app use deliberate
- the ordinary compiler surface clean

A compiler flag could still exist later as a convenience wrapper, but the core
concept should be a runtime library/API boundary.

## Shared Values

The hardest practical question is what crosses the host/live boundary.

A conservative answer is:

- plain scalars cross freely
- arrays/maps/struct-like runtime values cross when they belong to the portable
  shared subset
- large or sensitive host objects cross as opaque handles
- host APIs manipulate the real objects

That makes the live layer useful without forcing the entire Odin object graph
into the interpreter.

## Minimal First Version

A realistic first embedded version would only support a narrow shared subset:

- `def`, `defn`, `let`, `if`, `when`, `cond`
- arrays/maps/struct-like values
- module loading
- a persistent environment
- host function bindings
- reload by module
- opaque host handles where needed

That is enough for commands, reports, hooks, and automation.

## The Key Distinction

Current Kvist tooling already offers:

- generated-code inspection
- scratch evaluation
- fast compile-run loops

An optional live runtime would add:

- liveness inside the actual running program
- persistence of runtime definitions and state
- user-facing programmability after deployment
- reloadable behaviors in a shipped binary

That is the real difference.
