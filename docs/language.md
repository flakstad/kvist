# Language Reference

Kvist is a small Lisp-shaped source language that lowers to ordinary Odin.
It keeps Odin's execution model visible: values are concrete, mutation is
explicit, allocations are explicit, and generated `.odin` should stay readable.

This document is the primary reference for Kvist syntax, semantics, and the
main forms the compiler understands directly. Kvist also exposes large parts of
ordinary Odin through its syntax and interop model, but this document is not a
full Odin reference. When Kvist reuses an Odin concept directly, the goal here
is to explain the Kvist spelling, semantics, and ownership rules rather than to
restate every Odin API.

## Scope And Model

Kvist is easier to read if you know a few Odin-shaped ideas up front:

- a **value** is copied when passed around unless you explicitly use a pointer
- a **pointer** is a reference to some existing value; use it for shared
  identity or in-place mutation
- a **fixed array** like `[3]int` stores three `int` values inline
- a **slice** like `[]int` is a non-owning view of contiguous elements
- a **dynamic array** like `[dynamic]int` owns growable storage and must be
  deleted when you are done with it
- a **map** like `map[string]int` is an associative container; when you create
  one, it owns storage and must be deleted
- Odin procedures can return **multiple values** directly, and Kvist keeps that
  model
- Odin uses explicit **allocators** for heap-backed storage; Kvist keeps that
  model too

Kvist does not add a garbage collector, hidden object model, or lazy sequence
runtime on top of those rules.

Use this document as a reference, not a tutorial.

## Surface Index

The most common forms are:

```clojure
; file and package structure
package import foreign-import @export @private @exports odin

; declarations
def def- defvar defvar- defstruct defstruct- defenum defenum-
defunion defunion- defn defn- defmacro defmacro-
deftransform deftransform- defiter defiter-

; local structure
let do block fn comment

; control flow
if when cond case match while for return discard break continue defer
when-let if-let when-ok if-ok

; mutation and places
set! mut! update! delete! inc! dec! toggle! negate!
assoc update dissoc dissoc-in get slice

; ownership and allocators
make alloc delete zero with-allocator with-temp-allocator

; pointers and types
addr deref ptr type transmute type-assert

; polymorphism
overload

; core helpers
count empty? contains? nil? or-else println str

; threading, setup, and inspection
-> ->> cond-> as-> doto tap> doc

; bit operations
bit.and bit.or bit.xor bit.not bit.shift-left bit.shift-right
bit.and-not bit.test bit.set bit.clear bit.flip
```

## Source Files, Packages, And Names

### Reader Syntax

Kvist uses Clojure-style reader syntax:

- `(head args...)` for calls and language forms
- `[...]` for bindings, parameters, positional aggregates, and collection
  literals
- `{...}` for labeled aggregates and map literals
- `#{...}` for set literals

Whitespace and commas are interchangeable separators. Strings may span lines.
Numbers and string escapes use Odin spelling.

Reader prefixes are:

```clojure
'form    ; quote
`form    ; quasiquote
~form    ; unquote
~@forms  ; splice
#_form   ; discard the next form
#"..."   ; regex pattern
```

Quote produces immutable `Data` in runtime code and source forms in macro
code. See [data.md](data.md) and [macros.md](macros.md).

### File Model

Kvist source files use the `.kvist` extension. A folder is a package. Files in
the same folder use the same package name and form one compilation unit.

For example:

```text
app/
  main.kvist
  users/
    model.kvist
    format.kvist
```

Both files under `users/` start with:

```clojure
(package users)
```

Declarations in `model.kvist` and `format.kvist` can see and call one another
without imports. The filename does not create another namespace.

`app/main.kvist` imports the folder:

```clojure
(package main)
(import users "users")

(defn main []
  (println (users.display-name (users.User {name: "Ada"}))))
```

`package` is optional only for the root source passed to `kvist`; omitted root
packages default to `main`. Files in imported Kvist source packages must declare
exactly one `package`, and all files in that package directory must use the same
package name.

This differs from Clojure, where a source file normally declares its own
namespace and other files `require` that namespace. In Kvist, the folder is the
package, every file in it contributes declarations to that package, and only
code outside the folder imports it.

`import` declarations require a preceding package declaration. Imports belong
before ordinary declarations.

Ordinary `.odin` files remain ordinary Odin. A Kvist package directory may
contain both `.kvist` and `.odin` files:

- imported package directories are treated as Kvist source packages when they
  contain `.kvist` files
- sibling `.odin` files in imported source-package directories are sidecars and
  are available through the package alias
- root `run`, `build`, `check`, and `test` commands include sibling `.odin`
  files by generating a temporary Odin file into the source directory and
  building the package directory

Use `foreign-import` for Odin foreign imports:

```clojure
(foreign-import sqlite "system:sqlite3")
```

Raw Odin inside a `.kvist` file is explicit and should be reserved for cases
without a canonical Kvist form:

```clojure
(odin "some_odin_only_construct()")
```

Use `odin-infix` and `odin-prefix` when a macro needs to splice Kvist
subexpressions into a raw Odin operator expression:

```clojure
(odin-infix "&" flags mask)
(odin-prefix "~" mask)
```

### Declarations

The main declaration forms are:

```clojure
(def Max-Retries 3)            ; immutable value or type alias
(defvar request-count 0)       ; mutable value

(defstruct User {
  name: string
  active?: bool
})

(defenum State [Pending Ready Failed])
(defunion Result {
  user: User
  error: string
})

(defn greet [user: User] -> string
  (str "Hello, " user.name))
```

Add `-` to the form name to make a top-level declaration private to its
package: `def-`, `defvar-`, `defstruct-`, `defenum-`, `defunion-`, and `defn-`.
Macros, transforms, and iterators use `defmacro`, `deftransform`, and `defiter`.
The [declarations](#declaration-details) and
[compile-time forms](#compile-time-forms) sections cover the full syntax.

### Names And Symbols

Names are Clojure-style symbols. Ordinary declaration and local names use
letters, digits, `_`, `-`, `?`, and `!`, and cannot start with a digit. Examples
are `request-count`, `active?`, `push!`, `App-State`, and `value_2`. Whitespace,
commas, and collection delimiters end a symbol.

The punctuation has conventions:

- `-` separates words
- `?` marks predicates
- `!` marks mutation
- a leading `.` is a field selector, such as `.name`
- `.` inside a name accesses a package or field, such as `arr.map` or
  `user.name`
- operator symbols such as `+`, `<=`, and `bit.and` are used in call position

Field access and package access use dot syntax:

```clojure
user.name
fmt.println
arr.map
```

Field selectors such as `.name` and `.age` are not values by themselves. They
are special shorthand in supported places such as `get`, `assoc`, `update`,
`arr.map`, `arr.filter`, and similar helpers.

Keywords are ordinary values of type `keyword`. They are useful for lightweight
symbolic data in otherwise Odin-shaped code:

```clojure
(defstruct Config {
  mode: keyword
})

(Config {mode: :env/dev})
```

Kvist still uses specific keyword literals positionally in some forms. For
example, `:defer`, `:errdefer`, `:using`, `:or-return`, `:yield`, `:next`,
`:dispose`, and `cond`'s `:else` act as markers in those syntactic slots.

Generated Odin uses a predictable mapping:

- `-` becomes `_`
- `?` becomes `_p`
- `!` becomes `_bang`
- case and existing underscores are preserved

For example, `route-add`, `active?`, and `push!` become `route_add`,
`active_p`, and `push_bang`. This usually matters only when reading generated
code or calling Kvist declarations from Odin.

### Imports And Exports

Imports are uniform:

```clojure
(import fmt "core:fmt")
(import arr "kvist:arr")
(import "kvist:arr" :as arr)
(import "kvist:arr" :refer [map filter reduce])
(import support "support")
```

Imports either name an alias explicitly or opt into selected bare helpers with
`:refer`. `(import arr "kvist:arr")` and `(import "kvist:arr" :as arr)` both
expose qualified names such as `arr.map`.
`(import "kvist:arr" :refer [map filter reduce])` exposes those helpers bare
and also keeps the package's default qualified alias available.

Plain path-only imports are not valid Kvist source. Use an alias for ordinary
package access, or use `:refer` when a file intentionally wants selected public
helpers bare.

Relative imports are resolved by inspecting the target:

- a target with `.kvist` files is a Kvist source package
- an Odin-only target remains an ordinary Odin import
- `kvist:*` imports load shipped Kvist packages
- `core:*`, `base:*`, `vendor:*`, and other Odin package paths remain Odin

Relative paths are resolved from the file containing the import.
There is no `:odin` import marker.

Use `@export` to attach Odin `@(export)` to the next top-level declaration.
Use `@private` to attach Odin `@(private)` to the next top-level declaration.
Use `@exports [Name ...]` when raw Odin sidecar
declarations should be exposed through a Kvist source-package import.

```clojure
@export
(defn callback :abi "c" [ctx: rawptr] -> void
  ...)

@private
(defn hidden [] -> int #force_inline
  42)

@exports [Raw_Handle]
```

### Ownership And Cleanup

Kvist uses explicit ownership. Dynamic arrays, maps, sets, built strings, and
many package helpers return owned storage. The owner must return it, transfer
it, or clean it up.

Odin's explicit form works:

```clojure
(let [xs (arr.range 0 10)]
  (defer (delete xs))
  (println xs))
```

For a local binding, prefer the equivalent `:defer` marker:

```clojure
(let [xs (arr.range 0 10) :defer]
  (println xs))
```

Use `:defer-with` when a resource has its own cleanup function:

```clojure
(let [file (open-file path) :defer-with close-file]
  (read-header file))
```

Keep the marker on the same line as its binding. Cleanup runs when the
surrounding scope exits. Borrowed slices and string views are not deleted; the
storage they point into must remain alive. Compiler-managed `Data` values need
no cleanup marker.

Use `(addr value)` or the shorter `&value` when a mutating function needs a
pointer:

```clojure
(update-state! &state)
```

See [Ownership, Allocation, And Context](#ownership-allocation-and-context) for
transfers, allocators, `:errdefer`, and compiler warnings.

## Types, Values, And Data Shapes

Kvist reuses Odin's data shapes directly.

### Scalars

Primitive scalar types include `bool`, integer types such as `int`, `i32`,
`u64`, floating-point types such as `f32` and `f64`, and string-like types such
as `string`, `cstring`, `rune`, and `byte`.

Strings are plain Odin strings. They are values, not objects with methods.
Boolean literals are `true` and `false`. `nil` is the nil value used for
pointers and other Odin values that accept nil.

String literals may span lines:

```clojure
(def Query: string "[:find ?name
 :where [?e :user/name ?name]]")
```

Regex pattern literals use Clojure-shaped `#"..."`
syntax and lower to Odin
strings while preserving regex backslashes:

```clojure
#"\d+"
```

Use `kvist:regex` for compiled regex ownership and matching helpers:

```clojure
(import re "kvist:regex")

(re.matches? #"\d+" "abc123")
```

Compiled regexes and capture arrays are ordinary owned Odin values; destroy
them with `regex.destroy!` and `regex.destroy-capture!` when using the explicit
compile or match APIs. For scoped locals, use `:defer-with`:

```clojure
(let [[compiled err] (re.compile #"^a+$")]
  (if (= err nil)
    (let [owned compiled :defer-with re.destroy!]
      (re.matches-compiled? owned "aaa"))
    false))
```

### Keywords

`keyword` is a symbolic scalar for tags, modes, states, and other
closed-world labels:

```clojure
:dev
:queued
:not-found
:http/status
```

At lowering time, Kvist emits:

```odin
keyword :: distinct string
```

That keeps the runtime model Odin-shaped: a keyword is just a distinct string
value, not an interned dynamic object. Equality, map keys, set membership, and
struct fields therefore work through ordinary Odin value semantics.

Keywords may include `/` for Clojure-style grouping, such as `:job/queued` or
`:http/status`. The namespace part is ordinary data, not package or import
resolution.

Use `keyword` when the value is symbolic and stable:

```clojure
(defstruct Result {
  status: keyword
})

(Result {status: :ok})
```

Prefer `string` when the value is user-facing text, open-ended input, or needs
full text processing.

### Fixed Arrays

A fixed array stores a known number of elements inline:

```clojure
([3]int [1 2 3])
```

This is useful when the size is part of the type.

### Slices

A slice is a pointer plus a length: a cheap, non-owning view over contiguous
elements. Its type is `[]T`, where `T` is the element type:

```clojure
([]int [1 2 3])
```

Indexing reads one element. Slicing creates another view:

```clojure
xs[i]           ; one element
xs[:]           ; the whole sequence
xs[start:]      ; start through the end
xs[:end]        ; beginning through end, excluding end
xs[start:end]   ; start through end, excluding end
```

The call-shaped equivalents are `(get xs i)`, `(slice xs)`,
`(slice xs start)`, and `(slice xs start end)`.

A slice may modify its backing storage:

```clojure
(defn clear! [values: []int]
  (for [value index values]
    (set! values[index] 0)))
```

It does not own that storage. Do not delete a slice, and do not keep or return
one after its backing value has been deleted:

```clojure
(let [xs (arr.dynamic int [10 20 30 40]) :defer
      middle xs[1:3]]
  (set! middle[0] 99)
  (println xs)) ; [10, 99, 30, 40]
```

Here `xs` owns the allocation and `middle` borrows it. Fixed arrays, dynamic
arrays, and strings can all provide slice-like views; the owner must outlive
every view.

### Dynamic Arrays

A dynamic array owns growable storage:

```clojure
([dynamic]int [1 2 3])
```

Dynamic arrays must be deleted when locally owned:

```clojure
(let [xs ([dynamic]int [1 2 3]) :defer]
  (count xs))
```

### Maps

Maps are associative containers:

```clojure
(map[string]int {"ok" 200 "missing" 404})
(map[keyword]int {:ok 200 :missing 404})
```

Like dynamic arrays, maps own storage when created and must be deleted when
locally owned.

### Sets

`set[T]` uses Odin's set representation directly and lowers to
`map[T]struct{}`:

```clojure
set[string]
```

Like maps and dynamic arrays, sets own storage when created and must be deleted
when locally owned.

### Structs

Structs group named fields into one concrete value:

```clojure
(defstruct User {
  name: string
  age: int
})

(User {name: "Ada" age: 36})
```

Struct values are copied by value unless passed through a pointer.
Omitted fields in a struct literal use Odin zero values.

Field metadata accepts ordinary type spelling, including compact Odin-like type
tokens:

```clojure
(defstruct Batch {
  ids: []int
  tags: set[string]
  weights: [4]f32
})
```

Use `:using` after a field type when you want Odin to promote the embedded
field's members onto the containing struct. This is useful for composition:
the containing value still stores a normal named field, but callers can access
the embedded field's members directly through the outer value.

```clojure
(defstruct Logger {
  level: int
})

(defstruct App {
  logger: Logger :using
  config: Config
})

(defn app-level [app: App] -> int
  app.level) ; promoted from app.logger.level by Odin
```

This lowers to:

```odin
App :: struct {
    using logger: Logger,
    config: Config,
}
```

Use ordinary fields when you want explicit access such as `app.logger.level`.
Use `:using` when Odin's field/procedure promotion is the intended API.

The parser also accepts `[slice T]` as a vector shorthand in `defstruct` field
metadata. It lowers to `[]T`. Use ordinary type spelling such as `[dynamic]T`,
`[N]T`, and `(set T)` for dynamic arrays, fixed arrays, and sets.

Struct fields use ordinary Odin-shaped types. A plain native struct does not
gain hidden lifecycle behavior from its field types or from specially named
procedures.

When a struct is used as a target of `data.decode` or `data.validate`, Kvist has
structural evidence that decoded strings, dynamic arrays, nested decoded
structs, and `Data` fields are acquired values. It then generates recursive
copy, replacement, and cleanup support for that decoded shape. This is inferred
from the boundary operation rather than declared on the type.

Opaque handles and structs assembled through arbitrary native code remain
explicit, as in Odin. Give them ordinary cleanup functions and use `defer` or
`:defer-with` at the owning scope.

Use `:default` after a field type to replace its zero-value construction
default:

```clojure
(defstruct Settings {
  port: i64 :default 8080
  label: string :default "local"
})

(Settings {})
```

Defaults are evaluated when an omitted field is constructed. At a decoded
boundary, they follow the inferred structural lifetime of the resulting shape.
Struct signatures and editor metadata retain
the annotation, and obvious literal type mismatches are compiler errors.

### Enums

Enums define a named integer-like set of values:

```clojure
(defenum Method [
  Get
  Head
  Post
])

(defenum Http-Status {
  OK: 200
  Not-Found: 404
})
```

Use `.Name` to refer to an enum member:

```clojure
.Get
.Not-Found
```

### Unions

Unions define tagged values that can contain one of several payload shapes:

```clojure
(defunion Value {
  i: int
  s: string
})

(Value {i: 42})
(Value {s: "kvist"})
```

Use `case` to inspect the active payload.

### Pointer Types

A pointer refers to some existing value instead of copying it:

```clojure
^User
(ptr User)
```

Use pointers for:

- in-place mutation
- optional or shared identity
- passing large values around without copying them

### Procedure Types

Procedures are values too. Function types use `fn`:

```clojure
(fn [x: int] -> int)
```

That type means "a procedure taking one `int` and returning one `int`."

### Type Constructors And Polymorphic Types

Most type shapes can be written with compact Odin-like tokens or list-shaped
constructors. These are equivalent where both are accepted:

```clojure
[]T                 (slice T)
[dynamic]T          (dynamic T)
[N]T                (array N T)
map[K]V             (map K V)
set[T]              (set T)
^T                  (ptr T)
```

Package helpers often use Odin-style polymorphic parameters. A type prefixed
with `$` introduces an inferred type parameter; the unprefixed name refers to
that inferred type later in the signature:

```clojure
(defn contains? [m: map[$K]$V, key: K] -> bool
  (contains? m key))

(defn write-json [path: string, value: $T] -> os.Error
  ...)
```

Use `$T: typeid` when the caller passes a type explicitly:

```clojure
(defn read-as [$T: typeid, path: string] -> [value: T, err: os.Error]
  ...)
```

## Declaration Details

Top-level declarations are public by default. Add `-` to make a declaration
package-private:

```clojure
(def answer 42)
(def- internal-scale 3)

(defvar counter 0)
(defvar- private-counter 0)
```

Typed declarations use `name: Type`:

```clojure
(def default-port: int 8080)
(defvar current-state: State (State {}))
```

An uninitialized typed `defvar` starts with the type's zero value:

```clojure
(defvar current-state: State)
```

`def` is immutable but is not limited to compile-time constants. Calls to
single-result Kvist functions are initialized once before `main`, with their
return type inferred:

```clojure
(import edn "kvist:edn")

(def config (edn.read-file "config.edn"))
```

Runtime bindings initialize in declaration order. Managed `Data` bindings are
released in reverse order at package shutdown. Reads remain direct typed
accesses; there is no Var indirection. Use an explicit type for runtime forms
whose result cannot be inferred from a single-result Kvist call.

Untyped `def` also declares Odin type aliases when the right-hand side is a
type expression:

```clojure
(def Handle (distinct rawptr))
(def Order-Groups map[int][dynamic]Order)
```

These lower to ordinary Odin aliases:

```odin
Handle :: distinct rawptr
Order_Groups :: map[int][dynamic]Order
```

Quoted values are first-class immutable `Data`. This is the dynamic data
island for heterogeneous Lisp/EDN-shaped values; unquoted vectors, maps, and
sets remain native homogeneous collections.

```clojure
(import data "kvist:data")

(def config
  '{:port 8080
    :features #{:query :pull}})

(def query
  '[:find ?name
    :where [?e :user/name ?name]])

(let [port (data.int (get config :port))
      features (get config :features)]
  (println port
           (contains? features :query)
           (count query)))
```

An unquoted collection literal is also Data when its surrounding type context
expects `Data`. Its scalar literals become Data values, while symbols and calls
are evaluated and converted from Data or native scalar values:

```clojure
(def default-contact: Data
  {:contact/name "Ada"
   :contact/active? true})

(defn contact [id: i64, name: string] -> Data
  {:db/id id
   :contact/name name})

(data.conj transactions
  [:db/add [:contact/id id] :contact/email email])
```

Return types, typed bindings, function parameters, and uniquely matching
overload parameters provide this context. Without Data context, unquoted
vectors, maps, and sets remain native homogeneous collections. A type
annotation selects the Data representation while expressions inside the
collection are still evaluated; quote instead preserves the form itself
without evaluation.

`Data` represents nil, booleans, integers, floats, strings, symbols, keywords,
lists, vectors, maps, sets, and tagged values. Quoted literals use static
backing storage, are cheap to copy and pass, and require no cleanup. Use `get`,
`contains?`, and `count` for structural access. The `data.int`, `data.float`,
`data.bool`, `data.string`, `data.symbol`, and `data.keyword` accessors cross
from dynamic data into native typed values; `data.vector?` and the corresponding
kind predicates inspect shapes. The `kvist:data` package also provides
`data.nth`, `data.get-in`, `data.keys`, and `data.vals`.

Keywords and Data maps can be called as map lookups:

```clojure
(:owner message)
(:owner message :unknown)
(message :owner)
(message :owner :unknown)
```

These forms borrow the stored value. The optional fallback is used only when
the key is absent; a present Data nil is preserved. This is Data-specific
lookup syntax, not a general callable-value protocol.

Tagged Data values are created with `data.tagged` or read from tagged EDN.

The compiler owns the representation-sensitive primitive operations, quote
lowering, and managed lifetime protocol. Higher-level construction, persistent
updates, traversal, and EDN operations live in the shipped `kvist:data` and
`kvist:edn` source packages. Runtime-owned values are deterministically managed;
immortal quoted literals retain the zero-cleanup path.

Local declarations use the same names and are scoped to the current block.
Local `defstruct`, `defenum`, and `defunion` declare block-scoped Odin types;
the declarations themselves are compile-time declarations, not runtime
allocations.

```clojure
(let []
  (def limit 10)
  (defvar total 0)
  ...)
```

Use `let` when you want to introduce initialized local names as part of one
expression. Use `defvar` when the local should behave like an ordinary mutable
declaration that is updated across several later statements:

```clojure
(defn sum-until-zero [xs: []int] -> int
  (defvar total 0)
  (for [x xs]
    (if (= x 0)
      (break))
    (set! total (+ total x)))
  total)
```

This is often clearer than forcing a dummy `let` binding just to create a place
that will be mutated later.

Use `_` when a binding exists only to evaluate and discard an expression:

```clojure
(let [_ (record-metric)
      [value _] (lookup key)]
  value)
```

These forms are also valid directly inside a function body:

```clojure
(defn classify-code [code: int] -> int
  (def limit: int 99)
  (defenum Status [OK Large])
  (defstruct Payload {code: int status: Status})
  (defunion Value {payload: Payload raw: int})
  (let [payload (Payload {code: code status: .OK})
        value (Value {payload: payload})]
    (case value
      (Payload item) (if (> item.code limit) 1 0)
      (int raw) raw
      -1)))
```

This does not mean Kvist creates a new enum, struct, or union every time the
function runs. These are still compile-time declarations. They are scoped to the
function body in source, but they lower as local type and binding declarations
in the generated Odin rather than as runtime "define a type now" operations.

Use function-scoped declarations when a helper type or constant only makes sense
inside one function and would add noise at top level.

Structs, enums, unions, transforms, sources, and macros use the same public /
package-private split at top level:

```clojure
(defstruct Point {
  x: f32
  y: f32
})

(defenum Status {
  Ready: 1
  Done: 2
})

(defunion Payload {
  text: string
  code: int
})

(deftransform- internal-transform
  (comp (map normalize)))

(defiter- internal-source [] -> Source_State :yield int
  :next next-source-item
  (open-source))

(defmacro- internal-macro [x]
  ...)
```

Package-private top-level names are available inside their own file/package but
are not exported through Kvist source-package imports.

## Functions And Calling

Functions are declared with `defn`:

```clojure
(defn distance [a: Point, b: Point] -> f32
  ...)

(defn- helper [x: int] -> int
  (+ x 1))
```

The final form of a single-result function is returned implicitly. Use
`return` for early exits and direct multiple returns.

Use `:abi` when a function must use a specific foreign ABI:

```clojure
(defn callback :abi "c" [ctx: rawptr] -> void
  ...)
```

Directive wrappers such as `#force_inline` can appear on function declarations:

```clojure
(defn tiny-helper [x: int] -> int #force_inline
  (+ x 1))

(defn query [] -> [value: int, ok: bool] #optional_ok
  (return 42 true))
```

Caller intrinsics use Odin spelling:

```clojure
(import rt "base:runtime")

(defn location
  [loc: rt.Source_Code_Location = #caller_location]
  -> rt.Source_Code_Location
  loc)

(defn expression
  [x: bool, text: string = (#caller_expression x)]
  -> string
  text)
```

Kvist infers lifetime boundaries from ordinary procedure bodies:

```clojure
(defn allocate [] -> [dynamic]int
  (make [dynamic]int))

(defn consume [values: [dynamic]int]
  (delete values))

(defn view [value: Data] -> Data
  value)
```

`allocate` is inferred to return new storage because every return path
allocates. `consume` is inferred to consume `values` because the body deletes
it. `view` is inferred to return a borrowed view because it aliases its
parameter. Callers move compiler-tracked owned locals into consuming calls and
disable the former scope cleanup; a later use is diagnosed.

Inference is conservative. A function that may return either an input array or
a new array is not treated as transferring ownership. Unknown or opaque native
resources keep explicit Odin semantics. Use ordinary cleanup functions with
`defer`, `:defer`, or `:defer-with`.

The forms `(owned T)`, `(borrowed T)`, `#owned`, `#borrowed`, and
`managed:` metadata are not part of Kvist. Procedure names such as
`Type-destroy` and `Type-clone` are ordinary names and do not install a
lifecycle protocol.

Use `kvist lifetimes path/to/file.kvist` to inspect the boundaries inferred by
the compiler and the evidence category used for each result and parameter.

The Kvist runtime has a reviewed foreign-binding table for operations whose
native bodies are opaque to the source analyzer. It records facts such as
“`kvist_data_retain` returns a new shared reference” and
“`kvist_data_item_at` returns a borrowed view.” This table describes Kvist's
own runtime ABI; it is not a Vev/Ro special case and does not classify arbitrary
foreign procedures by their names. Unknown foreign resources remain explicit.

Other Odin-style proc directives stay available in the same position when you
need them.

Polymorphic functions may add one Odin `where` constraint immediately after the
signature:

```clojure
(defn same? [value: $T, expected: T] -> bool
  (where (intrinsics.type-is-comparable T))
  (= value expected))
```

### Polymorphism, Formatting, And Overloads

Kvist supports parametric polymorphism through `$` type parameters. A type
prefixed with `$` introduces an inferred type parameter, and the unprefixed name
refers to that same type later in the signature:

```clojure
(defn debug-str [value: $T] -> string
  (fmt.aprintf "%v" value))
```

The `fmt` package accepts different value types, so this kind of helper is
useful for debugging and tooling. The returned string is owned because
`fmt.aprintf` returns an allocator-backed string. Use `fmt.tprintf` for
temporary-allocator strings that are consumed immediately and not deleted
manually.

For ordinary construction, use core `str`:

```clojure
(let [request (str "@get('" path "', {openWhenHidden: true})") :defer]
  (println request))
```

`str` accepts Odin-printable values, does not interpret braces or percent
signs in its string arguments, and lowers to one allocator-backed
`fmt.aprintf` call. Its result is always an owned string, including `(str)`, so
bind it with `:defer`, delete it explicitly, or return it.

Use `$T: typeid` when the caller passes a type explicitly:

```clojure
(defn read-as [$T: typeid, path: string] -> [value: T, err: os.Error]
  ...)

(read-as (type Config) "config.json")
```

Use `where` when a generic helper should only accept types that satisfy a
compile-time predicate:

```clojure
(import intrinsics "base:intrinsics")

(defn same? [value: $T, expected: T] -> bool
  (where (intrinsics.type-is-comparable T))
  (= value expected))
```

For ad hoc overloading, use `def` with an `overload` right-hand side:

```clojure
(defn render-int [value: int] -> string
  (fmt.aprintf "int:%d" value))

(defn render-user [user: User] -> string
  (fmt.aprintf "user:%s" user.name))

(def render (overload render-int render-user))

(defn render-supported [value: $T] -> string
  (render value))
```

The same form works for local `def` declarations inside a function body when
the overload set is only useful in that local scope.

This lowers to:

```odin
render :: proc{render_int, render_user}
```

Overload members are written with normal Kvist names. Resolution happens at
each specialized call site. If no overload matches, the generated program
reports the supported overloads.

Anonymous functions use `fn`:

```clojure
(arr.map (fn [x: int] -> int (+ x 1)) xs)
```

Non-capturing `fn` values lower to ordinary Odin procedure values. Captured
`fn` literals lower to explicit context-passing calls when the compiler can
prove the callback does not escape.

Captured callbacks are not general closure values. They cannot be stored,
returned, or passed to unknown escaping APIs. Captured locals become extra proc
parameters in generated Odin, not heap closure objects.

### Calls

Ordinary calls are list-shaped:

```clojure
(println "hello")
(+ 1 2 3)
(fmt.tprintf "user-%d" 42)
```

Kvist also supports named arguments for API-shaped functions. Named arguments
are passed as a single brace literal at the end of the call:

```clojure
(defn greet [name: string, punctuation: string = "!"] -> string
  ...)

(defn place [name: string, x: int, y: int, label: string = "ok"] -> string
  ...)

(greet "Ada")
(greet {name: "Linus" punctuation: "?"})
(place "enemy" {x: 10 y: 20})
```

Parameters with defaults must trail required parameters. Defaults can be omitted
positionally from the tail or omitted by name. Mixed calls keep a positional
prefix and name the remaining tail:

```clojure
(place "enemy" {x: 10 y: 20 label: "boss"})
```

Named arguments use `field:` labels, reject duplicates, and reject names that do
not match the callee's parameters. A named argument cannot overlap a positional
argument already supplied.

### Multiple Return Values

Kvist keeps Odin's direct multi-return model:

```clojure
(defn divmod [n: int, d: int] -> [q: int, r: int]
  (return (/ n d) (% n d)))

(defn parse-count [text: string] -> [value: int, ok: bool]
  (return (count text) true))
```

Multiple return values bind positionally:

```clojure
(let [[q r] (divmod 17 5)]
  (println q r))

(let [[value ok] (parse-count "42")]
  (if ok value 0))
```

This is the ordinary pattern for "value plus success flag" and "value plus
error" APIs.

The most common multi-return shapes are:

- `[value: T, ok: bool]` for parsing, lookup, search, and "found?" style APIs
- `[value: T, err: Some_Error_Type]` for Odin APIs where the zero error value
  means success
- small tuples such as `[q: int, r: int]` where both values are part of the
  result

Kvist does not wrap these in result objects. You bind the values directly and
branch explicitly.

For guard-oriented helpers such as `when-let`, `if-let`, `when-ok`, `if-ok`,
and `:or-return`, Kvist checks the last returned value only.

- if the last value is a `bool`, `true` means success and `false` means failure
- if the last value is an Odin error type, the zero error value means success
  and a non-zero error means failure

The earlier returned values are just ordinary bound results. They are not
packed into a special tuple object and they are not inspected as conditions.

So these two forms are applying the same rule to different final return types:

```clojure
(if-let [[value ok] (lookup key)]
  value
  fallback)

(if-ok [[data err] (os.read_entire_file path context.allocator)]
  data
  fallback)
```

In the first case the last value is `ok: bool`. In the second case the last
value is `err: os.Error`.

#### `value, ok`

Use this shape when failure is an expected ordinary outcome:

```clojure
(defn parsed-or-zero [text: string] -> int
  (let [[value ok] (parse-count text)]
    (if ok value 0)))
```

This is a good fit for:

- parse attempts
- map or table lookups
- search helpers
- optional conversions

#### `value, err`

Use this shape when calling Odin-style APIs that return an explicit error value:

```clojure
(defn read-byte-count [path: string] -> int
  (if-ok [[data err] (os.read_entire_file path context.allocator)]
    (do
      (defer (delete data))
      (count data))
    0))
```

This is the ordinary Kvist style for error-returning APIs.

## Literals, Constructors, And Conversion

The general rule is: a type in call position constructs or converts a value of
that type.

```clojure
(Point {x: 1.0 y: 2.0})
(rl.Vector2 [10.0 20.0])
(f32 x)
([3]i32 [1 2 3])
(matrix[2 2]f32 [1 2 3 4])
(#simd[4]f32 [1 2 3 4])
(#soa[dynamic]Particle [(Particle {x: 0 y: 0 vx: 1 vy: 1})])
(bit_set[Permission; u8] [.Read .Execute])
(quaternion [0.0 0.0 0.0 1.0])
```

Vector literals are positional aggregate input. Brace literals are field-labeled
aggregate input:

```clojure
(rl.Vector2 [10.0 20.0])
(rl.Rectangle {x: 0 y: 0 width: 1 height: 1})
```

Inline collection literals are also available for the most common owned
containers:

```clojure
[1 2 3]                  ; [dynamic]int
{"one" 1 "two" 2}        ; map[string]int
{:job/ready 1 :job/done 2} ; map[keyword]int
#{"math" "lisp"}         ; set[string]
#{:env/dev :env/prod}    ; set[keyword]
```

These are owned values, not persistent Clojure data structures. Delete them
when a local binding owns them, return them to transfer ownership, or pass them
to an API that takes ownership:

```clojure
(let [xs [1 2 3] :defer
      lookup {"one" 1 "two" 2} :defer
      states {:job/ready 1 :job/done 2} :defer
      tags #{"math" "lisp"} :defer
      modes #{:env/dev :env/prod} :defer]
  ...)
```

Empty inline literals need type context:

```clojure
(let [xs: [dynamic]int [] :defer
      lookup: map[string]int {} :defer
      states: map[keyword]int {} :defer
      tags: set[string] #{} :defer
      modes: set[keyword] #{} :defer]
  ...)
```

Use `keyword` when the value is a symbolic tag rather than user-facing text:

```clojure
(defstruct Job {
  state: keyword
  label: string
})

(Job {state: :job/queued label: "thumbnail"})
```

Use `(type Head Args...)` when a type must appear as a value. This includes
explicit `typeid` arguments and instantiated polymorphic types:

```clojure
(read-as (type Config) "config.json")
(linalg.identity (type matrix[2 2]f32))
(chan.create (type chan.Chan int) 1 context.allocator)
```

For Odin polymorphic struct literals, the type constructor can be used directly
when the final argument is a vector or brace literal:

```clojure
(queue.Queue int {})
(sc.State_Def Door-State {id: .Closed})
```

These lower to Odin generic type instantiation, for example
`queue.Queue(int){}` and `sc.State_Def(Door_State){...}`. Use `(type ...)`
when you need the type value itself, such as a parameter type, return type, or
`typeid` argument.

Use `make` for runtime or allocator-backed construction where Odin uses a
procedure-like allocation operation:

```clojure
(make [dynamic]int)
(make [dynamic]int 0 128)
(make map[string]int)
```

For dynamic arrays, the common `make` shapes are:

- `(make [dynamic]T)` for an empty dynamic array
- `(make [dynamic]T n)` for a dynamic array with length `n`
- `(make [dynamic]T n cap)` for a dynamic array with length `n` and capacity
  `cap`

Examples:

```clojure
(let [xs (make [dynamic]int 0 128) :defer]
  ...)

(let [cells (make [dynamic]f32 grid-cells) :defer]
  ...)
```

Like Odin, these allocations use the current `context.allocator` by default.
If you want a different allocator, you can either pass it directly to `make` or
choose it lexically with `with-allocator`:

```clojure
(let [scratch (make [dynamic]int 0 64 context.temp_allocator) :defer]
  ...)

(with-allocator [allocator context.temp_allocator]
  (let [scratch (make [dynamic]int 0 64) :defer]
    ...))
```

Use `alloc` when you want an Odin `new(T)` pointer allocation:

```clojure
(alloc Node)
(alloc Node context.temp_allocator)
```

Free an owned pointer from `alloc` with Odin's `free` when its allocator
requires individual cleanup.

Use `zero` to construct an explicit zero value for a type:

```clojure
(zero [2]f32)
(zero bit_set[Permission; u8])
```

For many collection-building cases, the shipped helper packages provide more
specific constructors with optional capacity arguments:

```clojure
(arr.empty int)
(arr.empty int 128)

(map.empty string int)
(map.empty string int 256)
```

`arr.empty` creates an owned empty dynamic array. `map.empty` creates an owned
empty map. The optional numeric argument is a capacity hint. These helpers are
often the clearest choice when you want to build a collection incrementally with
`append`, `arr.into!`, `map.assoc!`, `map.merge!`, or direct indexed updates.
`let` can infer local binding types from `arr.empty`, `map.empty`, and `map.of`
calls.

There is no separate object-construction runtime. Struct construction is just
type-call syntax over a brace literal.

## Bindings, Blocks, And Local Flow

`let` is an expression and a local scope:

```clojure
(let [xs ([dynamic]int [1 2 3]) :defer
      total (sum xs)]
  total)
```

The final expression in the body is the value of the `let`.

`if` is an expression when both branches produce a value. `when` can also be
used as an expression when the result type is known:

```clojure
(defn selected-index [selected?: bool] -> int
  (when selected? 1))
```

The false branch of a `when` expression is the zero value for the expected type.
In the example above, false returns `int{}`. A single-form body can often provide
the type in a local binding; multi-form `when` expressions need an explicit
expected type from the surrounding context.

Use value-producing `when` when that zero value is the intended fallback. When
the false branch carries meaning, prefer `if` and spell both branches out.

Use `do` when a branch or callback needs several expressions:

```clojure
(do
  (println "loading")
  (load-users))
```

`block` is the explicit block form when you want a block without new bindings.
That is useful when you want a nested scope for local declarations, `defer`, or
early control flow, but do not want a `let` binding list:

```clojure
(defn first-large [xs: []int] -> [value: int, ok: bool]
  (block
    (defvar found 0)
    (for [x xs]
      (if (> x 100)
        (do
          (set! found x)
          (return found true))))
    (return)))
```

Here `block` is just introducing a scoped body. The mutable local comes from
`defvar`, not from a `let` binding list.

Native structs continue to use dot access or explicit locals. `Data` has
Clojure-style map and sequential destructuring:

```clojure
(let [{:keys [name roles]
       :person/keys [email]
       :strs [external-id]
       :syms [status]
       :or {name "Anonymous"}
       :as original}
      contact
      [primary secondary & remaining :as all-roles]
      roles]
  ...)
```

Explicit map entries use `{local :source-key}`. `:keys`, literal namespaced
`:person/keys`, `:strs`, `:syms`, `:or`, and `:as` follow their Clojure
meanings. `::alias` resolution is not implied.

Sequential destructuring accepts Data lists and vectors. Missing positions,
nil, and a wrong collection kind behave as empty; extra positions are ignored.
An empty `&` rest binds Data nil, while a non-empty rest preserves list/vector
kind. Map defaults are evaluated only for absent keys, not explicit Data nil.
Defaults may refer to earlier destructured locals.

Every captured subvalue is an automatically managed `Data` local. Cleanup
markers are therefore rejected on Data patterns. A simple vector binding
remains native multi-return destructuring unless its right-hand side is
statically Data or a contextually compatible Data literal.

Owned local bindings may use the `:defer` marker:

```clojure
(let [xs (arr.empty int) :defer]
  ...)
```

This is shorthand for a matching `defer (delete xs)` at the end of the scope.
Use `:defer-with` when cleanup is a function other than `delete`:

```clojure
(let [file (open-file path) :defer-with close-file]
  ...)
```

This lowers to:

```odin
file := open_file(path)
defer close_file(file)
```

Cleanup markers are mutually exclusive. Use `:defer` for `delete(value)`,
`:defer-with` for `cleanup(value)`, or `:errdefer` for failure-only cleanup of
returned owned values.

For guarded multi-return bindings, `:defer` deletes the first bound value after
the guard succeeds:

```clojure
(let [[data err] (read-text path) :or-return :defer]
  ...)
```

`:defer-with` works the same way for guarded multi-return bindings, but calls
the named cleanup function on the first bound value:

```clojure
(let [[file err] (open-file path) :or-return :defer-with close-file]
  ...)
```

Use `:errdefer` when an owned value should be returned on success but cleaned
up if the function later returns an error:

```clojure
(defn load-buffer [path: string] -> [data: [dynamic]byte, err: rawptr]
  (let [[data err] (read-buffer path) :or-return :errdefer]
    (if (invalid-buffer? data)
      (do
        (set! err (validation-error))
        (return)))
    (return data err)))
```

`:errdefer` lowers to an ordinary deferred conditional cleanup:

```odin
defer {
    if err != nil {
        delete(data)
    }
}
```

It is only supported on `[value err]` bindings with `:or-return` in a
tail-position `let`, so the generated `defer` runs when the function exits. Use
`:defer` for unconditional scope cleanup.

### Guarded Multi-Return Bindings

Result bindings may use `:or-return`, `:or-break`, or `:or-continue` guards:

```clojure
(defn parse-required [text: string] -> [value: int, ok: bool]
  (let [[value ok] (parse-count text) :or-return]
    (return value true)))

(while running
  (let [[item ok] (next-item) :or-break]
    (println item)))

(for [text texts]
  (let [[value ok] (parse-count text) :or-continue]
    (println value)))
```

`:or-return` requires named proc returns matching the bound names.

These guards are shorthand for a very common Odin-style pattern:

- `:or-return` means "if the success condition failed, return now"
- `:or-break` means "if it failed, stop this loop"
- `:or-continue` means "if it failed, skip this iteration"
- `:errdefer` may follow `[value err] ... :or-return` to delete `value` only
  when the function exits with a non-nil `err`

They are designed for `value, ok` style bindings where the second bound value is
the success flag. More generally, they check the last bound value only. For
`bool`-terminated returns, `false` triggers the guard. For error-terminated
returns, a non-zero error triggers the guard.

The common helper macros for multi-return APIs are also available:

```clojure
(when-let [[value ok] (lookup key)]
  (println value))

(if-let [[value ok] (lookup key)]
  value
  fallback)

(when-ok [[data err] (read-file path)]
  (println (count data)))

(if-ok [[data err] (read-file path)]
  data
  fallback)
```

Use `when-let` and `if-let` for `value, ok` style APIs. Use `when-ok` and
`if-ok` for `value, err` style APIs.

Each binding form can also contain several dependent pairs. Evaluation stops at
the first false `ok` or non-zero `err`:

```clojure
(if-let [[user ok] (find-user id)
         [profile ok] (find-profile user.profile-id)]
  (render-profile profile)
  fallback)

(if-ok [[data err] (read-file path)
        [cfg err]  (parse-config data)]
  (validate-config cfg)
  fallback)
```

These chains are local branch selection. They do not return errors
automatically and they do not accept `let` binding modifiers such as
`:or-return`, `:defer`, or `:errdefer`. Use `let` with those modifiers when a
step owns resources that must be cleaned up before later failures can branch.

`when-let` is the statement form for `value, ok`:

```clojure
(let [total 0]
  (when-let [[value ok] (parse-count "42")]
    (set! total (+ total value)))
  total)
```

Use it when failure should simply skip a side effect or local mutation.

`if-let` is the expression form for `value, ok`:

```clojure
(if-let [[value ok] (parse-count text)]
  value
  0)
```

Use it when both the success and failure paths should produce a value. With
several binding pairs, the else branch is used when any `ok` is false.

`when-ok` is the statement form for `value, err`:

```clojure
(when-ok [[data err] (os.read_entire_file path context.allocator)]
  (defer (delete data))
  (println (count data)))
```

Use it when the success branch performs work but the failure branch can simply
do nothing.

`if-ok` is the expression form for `value, err`:

```clojure
(if-ok [[data err] (os.read_entire_file path context.allocator)]
  (do
    (defer (delete data))
    (count data))
  0)
```

Use it when the failure path should produce a fallback value. With several
binding pairs, the failure branch is used when any `err` is non-zero.

The main distinction is:

- `when-let` / `if-let`: the second value is a `bool`
- `when-ok` / `if-ok`: the second value is an error object or error pointer

There is no implicit condition coercion and no automatic exception model.
Conditions are boolean, and success and failure stay explicit in the source.

### Named Returns And Naked `return`

When a procedure has named return values, those names are real local result
slots. You may assign to them and then use a naked `return`:

```clojure
(defn parse-required [text: string] -> [value: int, ok: bool]
  (if (= text "")
    (return))
  (set! value (count text))
  (set! ok true)
  (return))
```

A naked `(return)` returns the current contents of the named result slots. If
you have not assigned anything yet, those slots contain the zero values for
their types, just like Odin locals:

- `int` returns `0`
- `bool` returns `false`
- pointers return `nil`
- slices, dynamic arrays, maps, strings, and other composite values return
  their zero values
- error return values return their zero "no error" value

That is why `:or-return` works naturally with named returns:

```clojure
(defn read-required [path: string] -> [data: []byte, err: os.Error]
  (let [[data err] (os.read_entire_file path context.allocator) :or-return]
    (return data err)))
```

For `:or-return`, the binding names must match the named return slots exactly.
Kvist assigns the result into those slots before checking the guard. If
`os.read_entire_file` fails, `err` is already set, so the naked return produced
by `:or-return` returns the captured error.

Because `:or-return` assigns into named return slots, `:errdefer` observes the
same `err` slot at function exit. If later code sets `err` and returns, the
owned first value is deleted. If `err` is still nil on success, ownership stays
with the returned value. For that reason, `:errdefer` is rejected in non-tail
`let` forms where Odin would run the generated `defer` at block exit instead of
function exit.

## Control Flow

The core control forms are:

```clojure
(if test then else)
(when test body...)
(while test body...)
(do body...)
(block body...)
(return value...)
(discard value...)
(break)
(continue)
(defer body...)
```

`if` and `when` are expression-oriented. `when` is the one-armed version of
`if`.

`do` evaluates a sequence of forms and returns the final value. `block` does
the same, but is used when you want an explicit nested scope for local
declarations, `defer`, or early control flow without a `let` binding vector.

`while` is the ordinary condition loop:

```clojure
(while (< i n)
  (println i)
  (mut! i += 1))
```

`return`, `break`, and `continue` lower directly to the corresponding Odin
control flow.

`discard` intentionally ignores one or more expression results:

```clojure
(discard x)
(discard x y)
```

This lowers to `_ = ...` assignments. It is useful when a value is intentionally
unused, but it does not override ownership rules: discarding a known owned
result still warns.

`defer` emits Odin `defer`. A single expression defers that expression;
multiple forms defer a block.

Inside `for` or `while`, `defer` still follows Odin scope rules: it runs when
the surrounding scope exits, not automatically after each iteration. Kvist warns
on direct loop-body `defer` forms. Wrap the iteration body in `(block ...)` when
you want a per-iteration scope, or clean up explicitly at the end of the loop
body.

### `cond`

Use `cond` when each branch has its own predicate:

```clojure
(cond
  (< n 0) "negative"
  (= n 0) "zero"
  :else "positive")
```

Vector clauses are also accepted when a branch needs several body forms:

```clojure
(cond
  [(< n 0) (println "negative") "negative"]
  [:else "non-negative"])
```

### `case`

Use `case` when one subject is being classified. Arms are flat pattern and
expression pairs followed by a naked default expression. Use `(do ...)` when an
arm needs multiple forms.

Value cases expand to equality tests. Union and type payload cases lower to
Odin type switches:

```clojure
(case status
  .Ready "ready"
  .Done "done"
  "unknown")

(case method
  .Get "read"
  .Head "read"
  .Post "write"
  "other")

(case state
  :queued 0
  :running 1
  :done 2
  -1)

(case event
  (Connected conn) conn.id
  (Disconnected _) 0
  (Data data) (count data.payload)
  -1)
```

A vector arm is one vector literal, not a way to group several case values.
Its type comes from the subject context, and comparison follows Odin's equality
rules. Repeat arms when several values share one result.

Use `_` when a type payload case should match the variant without binding the
payload.

`case` may lower to Odin `switch` or `#partial switch` internally. Those are
generated Odin details, not Kvist source forms. Kvist source uses `case` for
subject dispatch and `cond` for predicate branches.

### `match`

Use `match` for structural `Data` dispatch. Arms are flat pattern/result pairs
and the final arm must be `:else` or `_`:

```clojure
(match message
  {:op :query :query query}
  (run-query query)

  (as whole {:op :transact :tx tx})
  (validate-and-transact whole tx)

  (kind :vector [head & tail])
  (handle-sequence head tail)

  :else
  (unknown-message message))
```

Plain symbols capture Data and `_` is the wildcard. Quote a symbol when it is a
literal pattern. Maps are open but every mentioned literal key is required.
Sequences are exact unless they contain `&`; both lists and vectors match an
unconstrained sequence pattern. Exact set patterns contain literals only.

`(as name pattern)` captures the complete value. `(kind :vector pattern)`
constrains the Data representation; the supported kind names are `:nil`,
`:bool`, `:int`, `:float`, `:string`, `:symbol`, `:keyword`, `:list`,
`:vector`, `:map`, `:set`, and `:tagged`. Captures remain Data, so native
conversion stays explicit through `data.int`, `data.string`, `data.decode`,
and related operations.

The subject is evaluated once and the first matching arm wins. Structural
tests borrow their input; captures are retained only after the complete arm
succeeds. Use `case` instead for native enums, unions, and ordinary values.

### `for`

Use `for` for side-effect iteration:

```clojure
(for [x xs]
  (println x))

(for [k v lookup]
  (println k v))

(for [x i xs]
  (println i x))
```

Unlike Clojure's `for`, this is not a lazy sequence builder. It is a loop.

Data patterns can be loop binders:

```clojure
(for [[id title] rows]
  ...)

(for [{:keys [name email]} contacts]
  ...)

(for [index [id title] rows]
  ...)
```

Data list, vector, and set sources iterate in backing order; Data nil performs
zero iterations. Native arrays, slices, and dynamic arrays of `Data` are also
supported. Other runtime Data kinds report a source-mapped kind error.

Ordinary indexed iteration follows Odin's value/index order:
`[value index source]`. Indexed Data-pattern iteration uses
`[index pattern source]`, as in the final example above.

## Places, Mutation, And Value Updates

Kvist exposes direct Odin-style places:

```clojure
value.field
xs[i]
xs[:end]
xs[start:end]
xs[start:]
```

The call-shaped equivalents are available too:

```clojure
(get value .field)
(get xs i)
(get lookup key default)
(slice xs)
(slice xs start end)
(slice xs start)
(slice xs 0 end)
```

Use place syntax when you want direct read or write access to storage.

### Mutating Forms

```clojure
(set! place value)             ; assignment
(mut! place += value)          ; compound assignment
(update! place f args...)      ; read, apply, write
(delete! target key)           ; remove map/set key in place
```

Examples:

```clojure
(set! robot.x nx)
(mut! particles.vx[i] += ax)
(update! point.y + 4)
(update! (get lookup "a") inc)
(delete! lookup "stale")
```

Unary mutation helpers are available for common place updates:

```clojure
(inc! point.x)
(dec! xs[i])
(toggle! enabled)
(negate! velocity.x)
```

### Non-Mutating Value Updates

For native struct or immutable `Data` updates where you want a changed value
instead of mutating the original, use `assoc` and `update`:

```clojure
(assoc user.name "Ada")
(assoc user.profile.name "Ada")
(update user.age inc)
(update user.profile.age + 1)

(assoc message :status :ready)
(update message :attempts increment-data)
```

Dispatch is resolved statically from the target type. Struct forms copy the
root value once, update the selected field path, and return the copy. Data forms
perform an immutable map or vector update and preserve structural sharing.

Remove map keys from Data with `dissoc`. It accepts one or more keys:

```clojure
(dissoc message :temporary)
(dissoc message :temporary :debug)
```

Use `dissoc-in` with a Data list or vector path to remove a nested leaf:

```clojure
(dissoc-in message '[:request :credentials])
```

Missing paths leave the original value unchanged. Empty parent maps are
preserved rather than implicitly pruned.

Dynamic arrays, slices, maps, and sets are not path-updated this way; use
explicit copying or mutation for those. This restriction does not apply to
immutable `Data` collections.

### Decoding Data Into Native Structs

Use `data.decode` when a dynamic boundary should become a concrete native
struct:

```clojure
(defstruct Settings {
  port: i64
  enabled: bool
  metadata: Data
})

(let [[settings err ok]
      (data.decode Settings message '[:settings])]
  (if ok
    (start settings)
    (println err.path err.expected err.actual)))
```

The optional path becomes the root of any `Decode-Error`. Required nested
Kvist structs and `Data`, boolean, integer, floating-point, string, and enum
fields are supported. Enum keywords use lowercase source
spelling, so `.Read-Only` is represented by `:read-only`. A keyword outside the
enum sets `err.enum-value?`, `err.expected-type`, and `err.actual-value`.
Decoded string ownership is inferred from use of the struct as a decode target.
Nested validation completes before construction, so acquired leaves exist only
for a successful result. The decoded struct and error then receive
deterministic structural cleanup.
A field annotated `:default value` is optional at the Data boundary: a missing
map key evaluates the same default used by ordinary struct construction, while
a present key is still validated. Presence is checked independently from Data
`nil`, so an explicit `nil` does not select the default.

Fields declared `[dynamic]T` decode Data vectors into owning native dynamic
arrays when `T` is `Data`, `bool`, an integer scalar, or a
floating-point scalar, a Kvist enum, or a Kvist struct:

```clojure
(defstruct Point {
  x: i64
  y: i64
})

(defstruct Batch {
  ids: [dynamic]i64
  points: [dynamic]Point
})

(data.decode Batch {:ids [10 20 30]
                    :points [{:x 1 :y 2}
                             {:x 3 :y 4}]})
```

Every element is validated before the native array is allocated. Errors append
the failing numeric index to the Data path, such as `[:ids 1]`. Nested struct
fields extend that path further, such as `[:points 1 :x]`, and honor the same
defaults and managed-field rules as directly nested structs. `Data` elements
are retained; scalar and enum elements are stored unboxed. Invalid enum
keywords also populate `expected-type` and `actual-value`.

The same supported element types can be decoded directly when no wrapper
struct is useful:

```clojure
(let [[points err ok]
      (data.decode
        (dynamic Point)
        [{:x 1 :y 2} {:x 3 :y 4}]
        [:points])]
  (if ok
    (draw-points points)
    (println err.path err.expected err.actual)))
```

`points` is an ordinary owned `[dynamic]Point`, not a persistent or boxed
collection. A result destructuring binding schedules deterministic cleanup,
including recursive destruction of managed struct elements. Direct decoding
also validates the complete Data vector before allocating native storage.
Native string arrays and borrowed slices are not supported decode targets.

### Validating Data Without Decoding

Use `data.validate` when Data should remain Data after checking a reusable
native shape:

```clojure
(let [[err ok]
      (data.validate Message message [:message])]
  (if ok
    (handle-data-message message)
    (println err.path err.expected err.actual)))
```

The target may be any struct or `(dynamic T)` target accepted by
`data.decode`. Validation uses the same required fields, `:default` optional
fields, enum variants, nested structs, array elements, and path-aware
`Decode-Error` values. It returns `[err ok]` and does not construct the native
target, clone managed fields, or allocate native array storage. The original
immutable Data value is unchanged.

This is useful for validating once at a package or protocol boundary and then
passing Data through code that relies on that boundary contract. Validation
does not create a hidden runtime schema object or a distinct boxed/refined Data
type; the native target type remains the single shape definition.

In a `->` pipeline, use a `.field` selector step:

```clojure
(-> user
  (assoc .profile.name "Ada")
  (update .profile.age + 1)
  (assoc .name "Ada"))
```

## Ownership, Allocation, And Context

Kvist keeps Odin's explicit allocation model. It automatically manages `Data`
and aggregates whose nontrivial lifetime is structurally derived from `Data`.
Ordinary native strings, arrays, maps, and opaque resources still use explicit
Odin-style cleanup. Typed decode results are a narrow exception because the
decode boundary proves their complete allocation shape. This is deterministic
management, not tracing garbage collection.

If a value owns dynamic storage, delete it when the current scope is done with
it. The common owned values are dynamic arrays, maps, and helper results that
create them.

```clojure
(let [xs (arr.range 0 8) :defer]
  (for [x xs]
    (println x)))
```

The practical ownership rules are:

- allocating native expressions remain explicit; use `defer`, `:defer`, or
  `:defer-with`
- a parameter is inferred as consuming when the procedure body explicitly
  deletes it or transfers it through a proven owning result
- parameters otherwise borrow
- if every return path proves a new value, ownership transfers to the caller
- borrowed views must not be deleted
- compiler-tracked `Data`, structs whose lifetime derives from contained
  `Data`, and decoded structural results receive deterministic generated
  cleanup
- ambiguous or opaque imported resources use explicit `defer`, `:defer`, or
  `:defer-with`
- cleanup-like procedure names do not change a type's semantics
- `:defer` is scope cleanup for ordinary owned values
- `:defer-with` is scope cleanup through a named cleanup function
- `:errdefer` is failure-only cleanup for `[value err] :or-return` bindings
- iterators use `:dispose` in their `defiter` declaration to name producer-state cleanup

Common owned values:

- dynamic arrays such as `(make [dynamic]int)` or `([dynamic]int [1 2 3])`
- maps such as `(make map[string]int)` or `(map[string]int {"one" 1})`
- collection helpers that build fresh dynamic arrays or maps, such as
  `arr.map`, `arr.filter`, `arr.partition`, `arr.range`, `map.keys`,
  `map.vals`, `arr.group-by`, and `arr.frequencies`
- file-read bytes from `io.read` or `os.read_entire_file`

Common borrowed or plain non-owning values:

- fixed arrays such as `[4]int`
- plain structs, unions, enums, numbers, and booleans
- slices returned by view helpers such as `slice`, `arr.take`, `arr.drop`, and
  `arr.split-at`
- elements returned by helpers such as `arr.first` and `arr.last`

Strings and slices are views. Their backing storage may be borrowed or owned,
depending on how they were produced. For example, a string literal is static,
`str` returns an owned string, and trimming helpers commonly return borrowed
views.

Two ownership edges are worth calling out explicitly:

- `arr.partition`, `arr.partition-all`, and `arr.partition-by` return an owned
  outer dynamic array whose inner chunks are borrowed slices. Delete the outer
  array only.
- `tap>` returns its input. It does not change ownership. If you tap an owned
  value, the result is still owned.

Allocator scopes are explicit:

```clojure
(with-allocator [allocator expr]
  body...)

(with-temp-allocator [allocator]
  body...)
```

`with-allocator` temporarily overrides `context.allocator` and restores it with
`defer`.

`with-temp-allocator` starts a temp allocator scope, restores the previous
allocator state at scope exit, and rejects obvious owned values that would
escape that short-lived allocation scope.

Allocator scopes can also produce a value when the surrounding context provides
the result type:

```clojure
(let [count: int (with-temp-allocator [allocator]
                   (parse-count input))]
  count)
```

The compiler also has coded ownership warnings for obvious mistakes. These
warnings are advisory. They do not turn native values into an automatic
ownership system, and they do not add hidden native cleanup to generated Odin.

Normal commands report definite findings. Add `--ownership-audit` to include
conservative findings from the flow analysis:

```text
warning[KVO001]: owned result from arr.range is discarded; bind it, delete it, or return it
warning[KVO002, conservative]: owned local xs is never deleted or returned; add (defer (delete xs)) or return it
warning[KVO004]: owned local xs is overwritten before cleanup; delete it or return it before set!
warning[KVO003, conservative]: owned local xs is used after ownership transfer
warning[KVO005, conservative]: borrowed value escapes owner xs
```

Equivalent findings at the same source location are printed once. The compiler
API retains every warning with its stable `code` and `confidence` fields so
tools can choose their own policy. Explicit deferred destructors whose names
identify destroy, free, close, or release operations are recognized as cleanup.

The audit pass is intentionally conservative. It recognizes allocating return
paths, known owned-result helpers such as `arr.range`, `arr.empty`,
`map.empty`, and `set.union`; borrowed views that alias compatible inputs or
known view helpers such as `slice`, `arr.slice`, and `arr.rest`; and ownership
transfers such as `delete`, returning an owned local, and passing an owned local
into a consuming operation inferred from its body.

For example:

```clojure
(defn bad-view [] -> []int
  (let [xs (arr.range 0 10) :defer]
    (arr.slice xs 0 3)))
```

This warns because the returned slice is a borrowed view into `xs`, and `xs` is
deleted when the `let` scope exits.

Valid local use of the same borrowed view does not warn:

```clojure
(defn local-view-use [] -> int
  (let [xs (arr.range 0 10) :defer]
    (count (arr.slice xs 0 3))))
```

See `examples/collections/ownership-warnings.kvist` for a small warning
surface tour:

```sh
kvist check examples/collections/ownership-warnings.kvist
kvist check examples/collections/ownership-warnings.kvist --ownership-audit
```

### The Implicit `context`

Like Odin, Kvist code runs with an implicit `context` value in scope. This is
where allocator-sensitive code usually gets its default allocator from:

```clojure
context.allocator
context.temp_allocator
```

Most code does not need to thread allocators through every call manually.
Instead, helper functions and package code often read `context.allocator`
directly when calling Odin APIs that allocate:

```clojure
(os.read_entire_file path context.allocator)
(chan.create (type chan.Chan int) 1 context.allocator)
```

Use `context.temp_allocator` when you explicitly want temporary scratch
allocation rather than ordinary long-lived allocation.

### Custom Allocators In Functions

If a function should let the caller choose the allocator, take the allocator as
an ordinary typed argument and pass it through to the allocating API:

```clojure
(import mem "core:mem")

(defn read-with [path: string, allocator: mem.Allocator] -> [data: []byte, err: os.Error]
  (os.read_entire_file path allocator))
```

Then the caller can choose:

```clojure
(read-with path context.allocator)
(read-with path context.temp_allocator)
```

That is the basic pattern for allocator-aware helper functions: keep the normal
path simple by using `context.allocator`, and add an explicit allocator argument
when the caller genuinely needs control.

### Lexically Overriding The Current Allocator

When many operations in one block should share the same allocator, `with-allocator`
is usually cleaner than passing the allocator through every helper manually:

```clojure
(with-allocator [allocator context.temp_allocator]
  (let [scratch (make [dynamic]int 0 64) :defer]
    ...))
```

## Pointers And Addressing

Pointer types and pointer operations stay close to Odin. `^T` and `(ptr T)` are
equivalent type spellings; use whichever is clearer in context.

```clojure
(defn init [state: (ptr App-State)]
  ...)

(defn bump! [x: ^int]
  (mut! x^ += 1))

(addr value)
&value
(deref ptr)
ptr^
```

Use `addr` or `&value` to take an address. Use `ptr^` or `(deref ptr)` to read
or write through a pointer.

As a style rule, keep values as values unless shared identity or shared mutable
access is actually required.

- pass small plain data by value
- pass large or shared mutable values by pointer
- use slices for shared contiguous read/write data
- use address-of and dereference only when identity or mutation through a
  reference is the real goal

Examples:

```clojure
(defn counter-value [counter: ^Counter] -> int
  counter^.value)

(defn counter-after-bump [] -> int
  (let [counter (Counter {value: 41})]
    (bump! (addr counter.value))
    (counter-value (addr counter))))
```

Kvist does not add a borrow checker or automatic pointer-versus-value
recommendations. Its ownership analysis can diagnose known escapes and
use-after-transfer errors, but pointer use stays explicit.

## Core Forms And Built-In Helpers

### Operators And Expression Helpers

Operators lower to ordinary Odin expressions:

```clojure
(+ a b)
(- total discount)
(* x y)
(% index width)
(min x y)
(max x y)
(and ok ready)
(or cached? fresh?)
(not done)
(bit.and flags mask)
(bit.shift-left major 22)
```

`and`, `or`, and `not` are boolean operators. They lower to Odin `&&`, `||`,
and `!`; they do not return one of their input values.

This is intentionally different from Clojure:

```clojure
; Kvist: boolean expression
(or cached? fresh?)

; Kvist: optional-ok fallback
(or-else (lookup-cache key) fallback)
```

The Clojure pattern of returning the first non-false/nil value does not work in
Kvist:

```clojure
; Clojure-style, not Kvist
(or cached-value fallback-value)
```

Use `or-else` when the expression returns `[value, ok]` and you want a fallback
value. Kvist does not treat arbitrary values as conditions; condition
expressions must be boolean.

`+`, `*`, `/`, and `%` take two or more operands. `-` also has a unary form.
`min` and `max` take two or more operands.

`=`, `==`, `<`, `<=`, `>`, and `>=` support two or more operands and compare
adjacent values once:

```clojure
(= a b c)
(< a b c d)
```

`!=` is intentionally binary.

Bit operations live in `kvist:bit` and lower to ordinary Odin integer
operators:

```clojure
(import bit "kvist:bit")

(bit.and a b c)          ; a & b & c
(bit.or a b c)           ; a | b | c
(bit.xor a b)            ; a ~ b
(bit.not mask)           ; ~mask
(bit.shift-left x n)     ; x << n
(bit.shift-right x n)    ; x >> n
(bit.and-not flags mask) ; flags & ~mask
(bit.test flags index)   ; bit at index is set
(bit.set flags index)    ; set bit at index
(bit.clear flags index)  ; clear bit at index
(bit.flip flags index)   ; toggle bit at index
```

Directive expression wrappers attach Odin call directives to a call:

```clojure
(inc 41 #force_inline)
(inc x #force_inline)
```

`transmute` is explicit and lowers to Odin's `transmute(T)value` form:

```clojure
(transmute []byte text)
```

`type-assert` lowers to Odin's selector assertion `value.(T)` form:

```clojure
(type-assert handler.next ^h.Handler)
```

### Threading And Core Helpers

Small core helpers are auto-exposed. Prefer the bare spelling:

```clojure
(println value)
(count xs)
(get xs i)
(get lookup key default)
(slice xs start end)
(slice xs start)
(slice xs)
(empty? xs)
(contains? lookup key)
(or-else maybe fallback)
(nil? value)
(tap> value)
(tap> "label" value)
(doc 'println)
(-> value steps...)
(->> value steps...)
(cond-> value test step...)
(as-> value name expr...)
(doto value setup-calls...)
```

`->` threads a value into the next form as the first argument. `->>` threads it
as the last argument.

`cond->` conditionally applies first-argument thread steps. It is useful when
one value is refined by several independent flags and each enabled branch should
continue from the value produced by earlier enabled branches:

```clojure
(cond-> req
  json? (assoc .content-type :json)
  auth? (assoc .authenticated? true)
  trace? (update .trace-id + 10))
```

The conditions and steps are evaluated in order. Each condition controls exactly
one step. A true condition applies the step as if it were written with `->`; a
false condition leaves the current value unchanged. The result has the same
shape as the initial value because every step is a first-argument refinement of
that value. When several updates share one condition, use an ordinary `if` or a
helper function instead of repeating that condition in `cond->`.

`as->` binds a name to the current value and rebinds that same name after each
step expression. Use it when the value does not naturally thread into only the
first or last argument position, or when the pipeline ends by projecting the
threaded value into a different type:

```clojure
(as-> user x
  (visit x)
  (attach-bonus bonus x)
  (+ x.age x.profile.visits))
```

The name is visible anywhere inside each step, including field access such as
`x.profile.visits`. Each step receives the result of the previous step through
that name, and the result of the whole form is the final step expression. Unlike
`->` and `cond->`, `as->` can change type across steps; the example starts with
a `User` and returns an `int`.

`doto` evaluates a value once, passes it as the first argument to each setup
call, and returns the original value. Use it for Odin-style mutating setup APIs
whose calls return void or status values rather than the configured object:

```clojure
(let [configured (doto (addr cfg)
                   (set-port! 6969)
                   (enable-secure!))]
  configured^.port)
```

`count` lowers to Odin `len`. `count` is the canonical Kvist spelling.
`empty?` checks whether the lowered Odin length is zero.

`contains?` is the cross-family membership predicate:

```clojure
(contains? lookup key)   ; map/set-style membership
(contains? xs value)     ; array/slice/dynamic-array equality scan
(contains? text needle)  ; string contains, when needle is string
```

Use `(not (contains? collection value))` for absence. When membership depends
on a predicate instead of equality, use an array helper such as `arr.some?`:

```clojure
(arr.some? (fn [x: int] -> bool (> x 10)) xs)
```

`or-else` expects a `[value, ok]` expression and returns either the value or the
fallback. `nil?` lowers to a direct `nil` comparison.

`tap>` prints a value for inspection and returns that same value unchanged. The
labeled form requires a string literal label:

```clojure
(tap> user)
(tap> "user" user)
```

`doc` expects a quoted declaration name and prints the attached doc text for
that declaration:

```clojure
(doc 'parse-port)
```

## Shipped Packages

Broader helpers are packages, not hidden language behavior. Import them
explicitly.

### Arrays

`kvist:arr` is the main collection package:

```clojure
(import arr "kvist:arr")

(defn add [x: int, y: int] -> int
  (+ x y))

(let [numbers (arr.range 0 10) :defer
      even (arr.filter (fn [x: int] -> bool (= (% x 2) 0)) numbers) :defer
      squares (arr.map (fn [x: int] -> int (* x x)) even) :defer]
  (println (arr.reduce add 0 squares)))
```

`range`, `map`, and `filter` build owned dynamic arrays in ordinary expression
position. `reduce`, `find`, `some?`, and `every?` scan without building an
output. Names ending in `!` mutate existing storage:

```clojure
(arr.push! numbers 10)
(arr.sort! numbers)
```

View helpers such as `take`, `drop`, and `rest` return borrowed slices.
Partition helpers return an owned outer array of borrowed slices. See
[sequences.md](sequences.md) for constructors, eager builders, scans,
producers, views, and ownership.

### Maps, Sets, And Strings

`kvist:map`, `kvist:set`, and `kvist:str` provide construction and common
operations:

```clojure
(import map "kvist:map")
(import set "kvist:set")
(import str "kvist:str")

(let [scores (map.of string int {"Ada" 42}) :defer
      roles (set.of keyword [:admin :author]) :defer
      words (str.split "one,two,three" ",") :defer]
  (println (map.get scores "Ada" 0)
           (set.contains? roles :admin)
           words))
```

Non-mutating map and set operations return new owned values. Their `!` variants
mutate. String slicing and trimming borrow; joining, replacing, and changing
case return owned strings. See [sequences.md](sequences.md).

### Data And EDN

`kvist:data` works with immutable heterogeneous `Data`. `kvist:edn` reads and
writes its EDN representation:

```clojure
(import data "kvist:data")
(import edn "kvist:edn")

(let [config (edn.read "{:port 8080 :features [:query :pull]}")]
  (println (data.int (:port config)))
  (edn.prn config))
```

`Data` is compiler-managed. See [data.md](data.md) for construction, traversal,
updates, destructuring, validation, and typed boundaries.

### Regular Expressions

`kvist:regex` provides a simple one-shot API and explicit compiled values:

```clojure
(import regex "kvist:regex")

(regex.matches? #"^[a-z]+$" "kvist")

(let [[pattern err] (regex.compile #"^[a-z]+$")]
  (when (= err nil)
    (let [owned pattern :defer-with regex.destroy!]
      (println (regex.matches-compiled? owned "kvist")))))
```

Compiled regexes and captures use their package cleanup functions. See the
[package source](../src/kvist/regex/regex.kvist) for matching and capture APIs.

### Parallel Work And Tests

`kvist:parallel` runs tasks or bounded collection work:

```clojure
(import p "kvist:parallel")

(let [squares (p.map square values) :defer]
  (println squares))
```

`kvist:test` provides declarations and assertions:

```clojure
(import t "kvist:test")

(t.deftest addition
  (t.is (= (+ 2 3) 5)))
```

See [parallel.md](parallel.md) and [testing.md](testing.md).

### Struct Of Arrays

`kvist:soa` exposes Odin's struct-of-arrays layout. It stores each struct field
as a separate contiguous column:

```clojure
(import soa "kvist:soa")

(let [particles (soa.make Particle 1024) :defer]
  (soa.push! &particles (Particle {x: 1 y: 2 mass: 3}))
  (soa.scale! particles .mass 0.5)
  (println particles.mass[0]))
```

See [Struct Of Arrays](sequences.md#struct-of-arrays) for the storage forms and
column operations.

`kvist:bit` is covered with the core operators above. See
[packages.md](packages.md) for the complete package index.

## Compile-Time Forms

### Iterators And Transforms

`defiter` defines a reusable stateful producer for `for`, `into`, and
`transduce`. The header names both types: the opener state returned by the
generated function, and the item type yielded by `:next`.

```clojure
(defstruct File_Source {
  items: []string
  index: int
})

(defn next-file [src: ^File_Source] -> [path: string ok: bool]
  (if (< src.index (count src.items))
    (let [path src.items[src.index]]
      (set! src.index (+ src.index 1))
      (return path true))
    (return "" false)))

(defn dispose-files [src: ^File_Source]
  (set! src.index 0))

(defiter files [items: []string] -> File_Source :yield string
  :next next-file
  :dispose dispose-files
  (File_Source {items: items index: 0}))
```

This emits an ordinary opener function:

```clojure
(files items) ; returns File_Source
```

Consumers call `:next` with `^File_Source` until `ok` is false. `:dispose`,
when present, must take `^File_Source` and return no value; consumers defer it
after opening the iterator.

Iterators are consumed by `for`, `into`, and `transduce`:

```clojure
(for [path (files items)]
  (println path))

(into [dynamic]string
  (comp
    (filter odin-path?))
  (files items))

(transduce
  (comp
    (filter odin-path?)
    (map path-length))
  + 0
  (files items))
```

`deftransform` defines reusable compile-time transform structure. A transform
can be collected with `into` or reduced with `transduce`; both lower to fused
Odin loops rather than intermediate arrays.

```clojure
(deftransform paid-order-totals
  (filter paid?)
  (map order-total)
  (filter positive?))

(into [dynamic]int paid-order-totals orders)
(transduce paid-order-totals + 0 orders)

(for [total orders :transform paid-order-totals]
  (println total))
```

See [transforms.md](transforms.md) for supported steps, sources, outputs, and
ownership.

### Macros

`defmacro` defines source macros over Kvist forms:

```clojure
(defmacro name [arg ...]
  ...)
```

Macros expand before ordinary parse and lowering. Macro code should emit current
Kvist syntax.

Use macros when the source shape matters more than runtime values.

See [macros.md](macros.md) for the full macro authoring surface.

## Documentation And Comments

Use `;` for line comments; repeated semicolons such as `;;` are conventional
for standalone comments. Ignoring the next form is supported with `#_`:

```clojure
#_(+ 1 2 3)
```

Immediately preceding comments without a blank line also attach as doc text.
Supported declarations may also take inline docstrings:

```clojure
;; Parse a port number from a string.
(defn parse-port
  "Parse a port number from a string."
  [s: string] -> int
  ...)

(def port
  "Default port number."
  8080)
```

Anything wrapped in `(comment ...)` is ignored:

```clojure
(comment
  (parse-port "8080"))
```

The `comment` form is useful for scratch expressions, examples, and eval-driven
notes that should remain in the source file but not reach lowering or runtime.

## Related Docs

- [data.md](data.md) - immutable heterogeneous data
- [sequences.md](sequences.md) - collection helpers and ownership details
- [packages.md](packages.md) - shipped `kvist:*` package index
- [odin.md](odin.md) - direct Odin package use
- [transforms.md](transforms.md) - `deftransform`,
  `into`, `transduce`
- [macros.md](macros.md) - macro authoring
- [tooling.md](tooling.md) - CLI and editor tooling
- [examples/README.md](../examples/README.md) - runnable language and package examples
- [Odin Overview](https://odin-lang.org/docs/overview/) - Odin's value,
  package, pointer, allocator, and procedure model
