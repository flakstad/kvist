package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
compile_typed_multiform_when_expression :: proc(t: ^testing.T) {
    source := `(package main)

(defn pick [second?: bool] -> int
  (let [index: int (when second?
                     (println "picked")
                     1)]
    index))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "index: int = "), true)
    testing.expect_value(t, strings.contains(output, "if second_p else int{}"), true)
}

@(test)
infer_untyped_multiform_when_expression :: proc(t: ^testing.T) {
    source := `(package main)

(defn pick [second?: bool] -> int
  (let [index (when second?
                (println "picked")
                1)]
    index))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "index := "), true)
    testing.expect_value(t, strings.contains(output, "proc() -> int"), true)
}

@(test)
infer_untyped_do_expression_from_final_form :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo []
  (let [value (do
                (println "side")
                1)]
    (println value)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "value := "), true)
    testing.expect_value(t, strings.contains(output, "proc() -> int"), true)
}

@(test)
compile_numeric_operator_propagates_context_into_block_operands :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")
(import fmt "core:fmt")

(defn base-count [] -> int
  5)

(defn owned-label [] -> string
  (fmt.aprintf "ada|lin|grace"))

(defn adjusted-count [] -> int
  (+ (base-count)
     (let [label (owned-label) :defer]
       (count label))))

(defn inferred-count-block []
  (let [value (let [label (owned-label) :defer]
                (count label))]
    (fmt.println value)))

(defn contextual-operators [value: int, label: string] -> int
  (+ (block (def contextual-add 1) contextual-add)
     (- value (block (def contextual-subtract 1) contextual-subtract))
     (* value (block (def contextual-multiply 1) contextual-multiply))
     (/ value (block (def contextual-divide 1) contextual-divide))
     (% value (block (def contextual-remainder 1) contextual-remainder))
     (min value (block (def contextual-min 1) contextual-min))
     (max value (block (def contextual-max 1) contextual-max))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc() -> int"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(label)"), true)
    testing.expect_value(t, strings.contains(output, "return len(label)"), true)
}

@(test)
compile_boolean_operator_propagates_context_into_block_operands :: proc(t: ^testing.T) {
    source := `(package main)

(defn both [left: bool, right: bool] -> bool
  (and left
       (block
         (def contextual-and true)
         contextual-and)))

(defn inverted [value: bool] -> bool
  (not (block
         (def contextual-not true)
         contextual-not)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc() -> bool"), true)
    testing.expect_value(t, strings.contains(output, "return contextual_and"), true)
    testing.expect_value(t, strings.contains(output, "return contextual_not"), true)
}

@(test)
compile_operator_context_supports_distinct_and_generic_types :: proc(t: ^testing.T) {
    source := `(package main)
(import intrinsics "base:intrinsics")

(def Count (distinct int))

(defn add-count [left: Count] -> Count
  (+ left
     (block
       (def contextual-count (Count 1))
       contextual-count)))

(defn add-generic [left: $T] -> T
  (where (intrinsics.type-is-numeric T))
  (+ left
     (block
       (defvar contextual-generic: T left)
       contextual-generic)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc() -> Count"), true)
    testing.expect_value(t, strings.contains(output, "proc(left: T) -> T"), true)
    testing.expect_value(t, strings.contains(output, "return contextual_count"), true)
    testing.expect_value(t, strings.contains(output, "return contextual_generic"), true)
}

@(test)
infer_offset_of_intrinsic_as_uintptr :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User [age: int])

(defn age-offset [] -> uintptr
  (let [offset (odin-call "offset_of" User age)]
    (discard (if true offset (uintptr 0)))
    offset))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "offset := offset_of(User, age)"), true)
    testing.expect_value(t, strings.contains(output, "uintptr(0)"), true)
}

@(test)
reject_untyped_block_expression_without_expected_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo []
  (let [value (block
                (def base 1)
                base)]
    (println value)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "block expression needs an expected type; add a let binding type or use it where the type is known")
}

@(test)
reject_if_expression_with_obvious_branch_type_mismatch :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo [flag: bool] -> string
  (let [value: string (if flag "ok" true)]
    value))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "if expression branches have different obvious types: string and bool")
}

@(test)
reject_case_expression_with_obvious_branch_type_mismatch :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo [mode: int] -> string
  (let [value: string (case mode
                        0 "zero"
                        true)]
    value))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "if expression branches have different obvious types: string and bool")
}

@(test)
compile_numeric_if_literal_with_expected_unsigned_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn pick [present: bool value: u64] -> [picked: u64, ok: bool]
  (return (if present value 0) true))

(defn pick-reversed [present: bool value: u64] -> [picked: u64, ok: bool]
  (return (if present 0 value) true))

(defn pick-native [present: bool] -> [picked: i64, ok: bool]
  (return (if present (+ (odin "i64(4)") 1) 2) true))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(
        t,
        strings.contains(output, "return (value if present else 0), true"),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, "return (0 if present else value), true"),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, "i64(4)"),
        true,
    )
}

@(test)
reject_explicit_numeric_if_branch_mismatch_with_expected_unsigned_type :: proc(
    t: ^testing.T,
) {
    source := `(package main)

(defn pick [present: bool value: u64] -> [picked: u64, ok: bool]
  (return (if present value (int 0)) true))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(
        t,
        err.message,
        "if expression branches have different obvious types: u64 and int",
    )
}

@(test)
compile_type_payload_case_expression_with_expected_type :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Connected [id: int])
(defstruct Disconnected [reason: string])
(defunion Event [
  connected: Connected
  disconnected: Disconnected
])

(defn score [event: Event] -> int
  (let [value: int (case event
                    (Connected conn) conn.id
                    (Disconnected _) 0
                    -1)]
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "value: int = (proc(event: Event) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "switch kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "return conn.id"), true)
}

@(test)
compile_repeated_enum_case_expression :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method [Get Head Post])

(defn cost [method: Method] -> int
  (let [value (case method
                .Get 1
                .Head 1
                .Post 2
                3)]
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "== (.Get)"), true)
    testing.expect_value(t, strings.contains(output, "== (.Head)"), true)
    testing.expect_value(t, strings.contains(output, "== (.Post)"), true)
}

@(test)
compile_defstruct_program :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Profile
  "Profile data."
  [name: string
   age: int
   active?: bool
   tags: (map string (struct []))
   scores: [dynamic]int
   home: Point])

(defstruct Point
  [x: float
   y: float])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

// Profile data.
Profile :: struct {
    name: string,
    age: int,
    active_p: bool,
    tags: map[string]struct{},
    scores: [dynamic]int,
    home: Point,
}

Point :: struct {
    x: f64,
    y: f64,
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_defstruct_rejects_duplicate_fields :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Broken
  [name: string
   name: int])`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "duplicate defstruct field name:"), true)
}

@(test)
compile_defstruct_using_field :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Logger [
  level: int
])

(defstruct App [
  logger: Logger :using
  port: int
])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "using logger: Logger,"), true)
    testing.expect_value(t, strings.contains(output, "port: int,"), true)
}

@(test)
compile_struct_constructor_rejects_unknown_field :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person
  [name: string
   age: int])

(defn bad [] -> Person
  (Person :name "Ada" :extra 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "unknown struct constructor field :extra"), true)
}

@(test)
compile_struct_constructor_rejects_duplicate_field :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person
  [name: string
   age: int])

(defn bad [] -> Person
  (Person :name "Ada" :name "Grace"))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "duplicate struct constructor field :name"), true)
}

@(test)
compile_struct_constructor_rejects_literal_type_mismatch :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person
  [name: string
   age: int])

(defn bad [] -> Person
  (Person :name 42 :age "old"))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "struct constructor literal type mismatch for :name") || strings.contains(err.message, "struct constructor literal type mismatch for :age"), true)
}

@(test)
compile_label_fields_for_struct_union_and_enum :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point [
  x: f32
  y: f32
])

(defunion Value [
  i: int
  label: string
])

(defenum Http-Status {
  :OK 200
  :Not-Found 404
})

(defn point [] -> Point
  (Point :x 1.0 :y 2.0))

(defn value [] -> Value
  (Value :i 42))

(defn status [] -> Http-Status
  .OK)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "Point :: struct {"), true)
    testing.expect_value(t, strings.contains(output, "x: f32,"), true)
    testing.expect_value(t, strings.contains(output, "y: f32,"), true)
    testing.expect_value(t, strings.contains(output, "Value :: union {"), true)
    testing.expect_value(t, strings.contains(output, "    int,\n"), true)
    testing.expect_value(t, strings.contains(output, "    string,\n"), true)
    testing.expect_value(t, strings.contains(output, "Http_Status :: enum {"), true)
    testing.expect_value(t, strings.contains(output, "OK = 200,"), true)
    testing.expect_value(t, strings.contains(output, "Not_Found = 404,"), true)
    testing.expect_value(t, strings.contains(output, "return Point{x = 1.0, y = 2.0}"), true)
    testing.expect_value(t, strings.contains(output, "return Value(int(42))"), true)
    testing.expect_value(t, strings.contains(output, "return .OK"), true)
}

@(test)
compile_type_call_position_supports_scalar_conversions :: proc(t: ^testing.T) {
    source := `(package main)

(defn as-f32 [x: int] -> f32
  (f32 x))

(defn as-i32 [x: f64] -> i32
  (i32 x))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return f32(x)"), true)
    testing.expect_value(t, strings.contains(output, "return i32(x)"), true)
}

@(test)
compile_type_call_position_supports_complex_type_heads :: proc(t: ^testing.T) {
    source := `(package main)

(defn ptr-cast [x: rawptr] -> ^f32
  ((ptr f32) x))

(defn slice-cast [xs: []i32] -> (slice i32)
  ((slice i32) xs))

(defn fixed-literal [] -> [3]i32
  ((array 3 i32) [1 2 3]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return (^f32)(x)"), true)
    testing.expect_value(t, strings.contains(output, "return ([]i32)(xs)"), true)
    testing.expect_value(t, strings.contains(output, "return [3]i32{1, 2, 3}"), true)
}

@(test)
compile_generic_type_constructor_form :: proc(t: ^testing.T) {
    source := `(package main)
(odin "Box :: struct($T: typeid) {value: T}")

(defn box [x: i32] -> (Box i32)
  ((Box i32) :value x))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "box :: proc(x: i32) -> Box(i32)"), true)
    testing.expect_value(t, strings.contains(output, "return Box(i32){value = x}"), true)
}

@(test)
compile_typeid_form_defines_polymorphic_type_alias :: proc(t: ^testing.T) {
    source := `(package main)
(odin "Box :: struct($T: typeid) {value: T}")

(def Int-Box (typeid Box i32))

(defn box [x: i32] -> Int-Box
  ((Box i32) :value x))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "Int_Box :: Box(i32)"), true)
    testing.expect_value(t, strings.contains(output, "return Box(i32){value = x}"), true)
}

@(test)
compile_type_call_position_supports_complex_symbol_heads :: proc(t: ^testing.T) {
    source := `(package main)

(defn ptr-cast [x: rawptr] -> ^f32
  (^f32 x))

(defn slice-cast [xs: []f32] -> []f32
  ([]f32 xs))

(defn fixed-literal [] -> [3]i32
  ([3]i32 [1 2 3]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return (^f32)(x)"), true)
    testing.expect_value(t, strings.contains(output, "return ([]f32)(xs)"), true)
    testing.expect_value(t, strings.contains(output, "return [3]i32{1, 2, 3}"), true)
}

@(test)
compile_get_field_selector_and_enum_key :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point [
  x: int
])

(defenum Status [Active Inactive])

(defn score [] -> int
  (let [point (Point :x 4)
        counts (map[Status]int {.Active 7})]
    (+ (get point .x)
       (get counts .Active))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return ((point).x) + (counts[.Active])"), true)
}

@(test)
compile_rejects_duplicate_struct_field_defaults :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Config [
  retries: int :default 1 :default 2
])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    delete(output)
    defer delete(err.message)
    testing.expect_value(t, err.message, "duplicate :default defstruct field modifier")
}

@(test)
compile_validates_struct_field_default_types :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Config [
  retries: int :default "many"
])

(defn config [] -> Config
  (Config []))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    delete(output)
    defer delete(err.message)
    testing.expect_value(t, err.message, "struct field default type mismatch for retries:")
}

@(test)
compile_const_and_enum_forms :: proc(t: ^testing.T) {
    source := `(package main)

;; Default answer for bootstrapping.
(def answer 42)
;; Maximum configured size.
(def max-size: int 1024)

(defenum Method [
  Get
  Post
  Delete
])

(defenum Http-Status {
  :OK 200
  :Not-Found 404
  :Unprocessable-Content 422
})`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

// Default answer for bootstrapping.
answer :: 42

// Maximum configured size.
max_size: int : 1024

Method :: enum {
    Get,
    Post,
    Delete,
}

Http_Status :: enum {
    OK = 200,
    Not_Found = 404,
    Unprocessable_Content = 422,
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_local_typed_defvar_without_initializer :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo [] -> int
  (defvar count: int)
  (set! count 41)
  (+ count 1))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "count: int"), true)
    testing.expect_value(t, strings.contains(output, "count = 41"), true)
    testing.expect_value(t, strings.contains(output, "return (count) + (1)"), true)
}

@(test)
compile_def_type_alias_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Order [
  id: int
])

(def Handle (distinct rawptr))
(def Order-Groups map[int][dynamic]Order)
(def Byte-Slice []byte)
(def Lane #simd[4]f32)

(defn group-count [groups: Order-Groups] -> int
  (count groups))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "Handle :: distinct rawptr"), true)
    testing.expect_value(t, strings.contains(output, "Order_Groups :: map[int][dynamic]Order"), true)
    testing.expect_value(t, strings.contains(output, "Byte_Slice :: []byte"), true)
    testing.expect_value(t, strings.contains(output, "Lane :: #simd[4]f32"), true)
    testing.expect_value(t, strings.contains(output, "group_count :: proc(groups: Order_Groups) -> int"), true)
}

@(test)
compile_rejects_old_typed_def_and_defvar_spelling :: proc(t: ^testing.T) {
    const_source := `(package main)

(def max-size int 1024)`

    output, err, ok := kvist.compile_source(const_source)
    testing.expect_value(t, ok, false)
    if ok {
        delete(output)
    }
    testing.expect_value(t, strings.contains(err.message, "typed def uses shorthand name: Type or full form name : Type"), true)
    delete(err.message)

    var_source := `(package main)

(defvar live-port int 8080)`

    output, err, ok = kvist.compile_source(var_source)
    testing.expect_value(t, ok, false)
    if ok {
        delete(output)
    }
    testing.expect_value(t, strings.contains(err.message, "typed defvar uses shorthand name: Type or full form name : Type"), true)
    delete(err.message)
}

@(test)
compile_accepts_expanded_type_separator :: proc(t: ^testing.T) {
    source := `(package main)

(def answer : int 41)
(defvar counter : int 0)

(defn add-one [value : int] -> [result : int ok: bool]
  (return (+ value 1) true))

(defn main [] -> int
  (let [[result ok] (add-one answer)]
    (if ok result counter)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "answer: int : 41"), true)
    testing.expect_value(t, strings.contains(output, "counter: int"), true)
    testing.expect_value(t, strings.contains(output, "add_one :: proc(value: int) -> (result: int, ok: bool)"), true)
}

@(test)
compile_local_defvar_accepts_expanded_type_separator :: proc(t: ^testing.T) {
    source := `(package main)

(defn initialized [] -> int
  (defvar value : int 41)
  (inc! value)
  value)

(defn zero-initialized [] -> int
  (defvar value : int)
  (set! value 42)
  value)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "value: int = 41"), true)
    testing.expect_value(t, strings.contains(output, "value: int\n"), true)
    testing.expect_value(t, strings.contains(output, "value = 42"), true)
}

@(test)
compile_rejects_removed_layout_and_default_spellings :: proc(t: ^testing.T) {
    sources := []string{
        `(package main) (defstruct User {name: string})`,
        `(package main) (defn greet [name: string = "Ada"] -> string name)`,
        `(package main) (defenum Status {Ready: 1})`,
    }
    messages := []string{
        "defstruct fields use a vector",
        "parameter defaults use :default",
        "explicit enum values use keyword keys",
    }
    for source, index in sources {
        _, err, ok := kvist.compile_source(source)
        testing.expect_value(t, ok, false)
        if ok {
            continue
        }
        testing.expect_value(t, strings.contains(err.message, messages[index]), true)
        delete(err.message)
    }
}

@(test)
compile_rejects_map_as_struct_constructor :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User [name: string])

(defn bad [] -> User
  (User {:name "Ada"}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "receives a map as one value"), true)
}

@(test)
compile_struct_constructor_supports_positional_named_and_vector_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Greet [
  firstname: string
  lastname: string
])

(defn positional [] -> Greet
  (Greet "hello" "there"))

(defn named [] -> Greet
  (Greet :lastname "there" :firstname "hello"))

(defn from-vector [] -> Greet
  (Greet ["hello" "there"]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected_positional := `return Greet{"hello", "there"}`
    expected_named := `return Greet{lastname = "there", firstname = "hello"}`
    testing.expect_value(t, strings.count(output, expected_positional), 2)
    testing.expect_value(t, strings.count(output, expected_named), 1)
}

@(test)
compile_struct_constructor_rejects_empty_call :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Marker [])

(defn marker [] -> Marker
  (Marker))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "zero-value construction uses (zero Marker) or (Marker [])"), true)
}

@(test)
compile_local_struct_validates_constructors :: proc(t: ^testing.T) {
    source := `(package main)

(defn broken [] -> int
  (defstruct Local [x: int])
  (let [value (Local :y 1)]
    0))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "unknown struct constructor field :y"), true)
}

@(test)
compile_type_call_struct_constructor_uses_field_type_context :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Level [platforms: [dynamic]int])

(defn main []
  (let [level (Level :platforms [])]
    level))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "level := Level{platforms = [dynamic]int{}}"), true)
}

@(test)
compile_defenum_and_defunion_aliases :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method
  "HTTP method."
  [Get Post])

(defunion Value
  "Tagged value."
  [i: int
   s: string])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "// HTTP method."), true)
    testing.expect_value(t, strings.contains(output, "Method :: enum {"), true)
    testing.expect_value(t, strings.contains(output, "// Tagged value."), true)
    testing.expect_value(t, strings.contains(output, "Value :: union {"), true)
}

@(test)
compile_canonical_struct_introspection_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Profile
  [name: string
   active?: bool])

(defn main []
  (println (struct-fields 'Profile) (struct-types 'Profile)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "fmt.println([]string{\"name\", \"active?\"}, map[string]string{"), true)
    testing.expect_value(t, strings.contains(output, "\"name\" = \"string\""), true)
    testing.expect_value(t, strings.contains(output, "\"active?\" = \"bool\""), true)
}

@(test)
reject_slash_struct_introspection_compiler_aliases :: proc(t: ^testing.T) {
    fields_source := `(package main)

(defstruct Profile
  [name: string])

(defn main []
  (println (struct/fields 'Profile)))`

    output_fields, err_fields, ok_fields := kvist.compile_source(fields_source)
    testing.expect_value(t, ok_fields, true)
    if !ok_fields {
        testing.expect_value(t, err_fields.message, "")
        return
    }
    defer delete(output_fields)
    testing.expect_value(t, strings.contains(output_fields, "[]string{\"name\"}"), false)
    testing.expect_value(t, strings.contains(output_fields, "struct/fields"), true)

    types_source := `(package main)

(defstruct Profile
  [name: string])

(defn main []
  (println (struct/types 'Profile)))`

    output_types, err_types, ok_types := kvist.compile_source(types_source)
    testing.expect_value(t, ok_types, true)
    if !ok_types {
        testing.expect_value(t, err_types.message, "")
        return
    }
    defer delete(output_types)
    testing.expect_value(t, strings.contains(output_types, "map[string]string{"), false)
    testing.expect_value(t, strings.contains(output_types, "struct/types"), true)
}

@(test)
compile_union_decl_and_constructor :: proc(t: ^testing.T) {
    source := `(package main)

;; Tagged sum for testing constructors.
(defunion Value [
  i: int
  s: string
])

(defn wrap-int [n: int] -> Value
  (Value :i n))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

// Tagged sum for testing constructors.
Value :: union {
    int,
    string,
}

wrap_int :: proc(n: int) -> Value {
    return Value(n)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_case_with_union_type_payload :: proc(t: ^testing.T) {
    source := `(package main)

(defunion Value [
  i: int
  s: string
])

(defn describe [value: Value] -> string
  (case value
    (int _) "int"
    (string v) v
    "nil"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Value :: union {
    int,
    string,
}

describe :: proc(value: Value) -> string {
    switch kvist_case_1 in value {
    case int:
        return "int"
    case string:
        v := kvist_case_1
        return v
    case:
        return "nil"
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_case_with_union_payload_patterns :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Connected [
  id: int
])

(defstruct Disconnected [
  id: int
  reason: string
])

(defstruct Data [
  id: int
  payload: string
])

(defunion Event [
  connected: Connected
  disconnected: Disconnected
  data: Data
])

(defn event-score [event: Event] -> int
  (case event
    (Connected conn) conn.id
    (Disconnected disc) (count disc.reason)
    (Data data) (count data.payload)
    0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "switch kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, " in event {"), true)
    testing.expect_value(t, strings.contains(output, "case Connected:"), true)
    testing.expect_value(t, strings.contains(output, "conn := kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "return conn.id"), true)
    testing.expect_value(t, strings.contains(output, "case Disconnected:"), true)
    testing.expect_value(t, strings.contains(output, "disc := kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "return len(disc.reason)"), true)
    testing.expect_value(t, strings.contains(output, "case Data:"), true)
    testing.expect_value(t, strings.contains(output, "data := kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "return len(data.payload)"), true)
    testing.expect_value(t, strings.contains(output, "case:\n        return 0"), true)
}

@(test)
compile_case_with_ignored_union_payload :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Connected [
  id: int
])

(defstruct Data [
  payload: string
])

(defunion Event [
  connected: Connected
  data: Data
])

(defn event-score [event: Event] -> int
  (case event
    (Connected _) 1
    (Data data) (count data.payload)
    0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "case Connected:\n        return 1"), true)
    testing.expect_value(t, strings.contains(output, "_ := kvist_case_"), false)
    testing.expect_value(t, strings.contains(output, "data := kvist_case_"), true)
}

@(test)
compile_case_flat_union_payload_arm_with_do_body :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Connected [
  id: int
])

(defstruct Disconnected [
  reason: string
])

(defunion Event [
  connected: Connected
  disconnected: Disconnected
])

(defn event-score [event: Event] -> int
  (case event
    (Connected conn) conn.id
    (Disconnected disc) (do
                          (println disc.reason)
                          0)
    -1))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "case Connected:"), true)
    testing.expect_value(t, strings.contains(output, "conn := kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "return conn.id"), true)
    testing.expect_value(t, strings.contains(output, "case Disconnected:"), true)
    testing.expect_value(t, strings.contains(output, "disc := kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(disc.reason)"), true)
    testing.expect_value(t, strings.contains(output, "return 0"), true)
    testing.expect_value(t, strings.contains(output, "case:\n        return -1"), true)
}

@(test)
reject_case_mixing_value_and_type_patterns :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Connected [
  id: int
])

(defunion Event [
  connected: Connected
])

(defn event-score [event: Event] -> int
  (case event
    (Connected conn) conn.id
    .Other 0
    -1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "type-case expects (Type binding)")
}

@(test)
reject_case_value_then_type_pattern :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Connected [
  id: int
])

(defunion Event [
  connected: Connected
])

(defn event-score [event: Event] -> int
  (case event
    nil 0
    (Connected conn) conn.id
    -1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, strings.contains(err.message, "type-case expects (Type binding)"), true)
}

@(test)
reject_case_type_pattern_shape :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Connected [
  id: int
])

(defunion Event [
  connected: Connected
])

(defn event-score [event: Event] -> int
  (case event
    (Connected []) 1
    0))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "type-case expects (Type binding)")
}

@(test)
compile_indexed_field_symbol_places :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Columns [x: [dynamic]f32])

(defn step [cols: Columns, i: int, dx: f32] -> f32
  (mut! cols.x[i] += dx)
  cols.x[i])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(cols.x)[i] += dx"), true)
    testing.expect_value(t, strings.contains(output, "return (cols.x)[i]"), true)
}

@(test)
compile_field_access_on_call_result :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User [
  name: string
  age: int
])

(defn make-user [] -> User
  (User :name "Ada" :age 36))

(defn main [] -> string
  (make-user).name)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return make_user().name"), true)
}

@(test)
compile_proc_params_reject_field_destructuring :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point [
  x: int
  y: int
])

(defn draw [{:keys [x y] :as point} : Point] -> int
  (+ x y))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "field destructuring parameters have been removed"), true)
}

@(test)
compile_typed_block_expression_captures_field_selector_root :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defstruct Bucket
  [entries: []int])

(defn copy-entries [bucket: Bucket] -> [dynamic]int
  (let [copied: [dynamic]int
          (arr.into [dynamic]int (slice bucket.entries 0))]
    copied))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc(bucket: Bucket) -> [dynamic]int"), true)
}

@(test)
compile_fn_types_and_literals :: proc(t: ^testing.T) {
    source := `(package main)

(defn apply [f: (fn [x: int] -> int), x: int] -> int
  (f x))

(defn main []
  (let [out (apply (fn [x: int] -> int
                     (+ x 1))
                   41)]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

apply :: proc(f: proc(x: int) -> int, x: int) -> int {
    return f(x)
}

main :: proc() {
    out := apply(
        proc(x: int) -> int {
            return (x) + (1)
        },
        41
    )
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_matrix_surface_type_constructor :: proc(t: ^testing.T) {
    source := `(package main)
(import linalg "core:math/linalg")

(defn score [] -> f32
  (let [m (matrix[2 2]f32 [1.0 2.0 3.0 4.0])
        ident (linalg.identity (typeid matrix[2 2]f32))
        product (linalg.mul m ident)
        flat (linalg.matrix_flatten product)]
    (+ (get flat 0) (get flat 3))))

(defn quat-score [] -> f64
  (let [q (quaternion [0.0 0.0 0.0 1.0])
        q2 (quaternion 0.0 0.0 0.0 1.0)
        unit (linalg.normalize q)]
    (+ (linalg.dot q unit)
       (linalg.dot q2 q2))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "m := matrix[2, 2]f32{1.0, 2.0, 3.0, 4.0}"), true)
    testing.expect_value(t, strings.contains(output, "ident := linalg.identity(matrix[2, 2]f32)"), true)
    testing.expect_value(t, strings.contains(output, "product := linalg.mul(m, ident)"), true)
    testing.expect_value(t, strings.contains(output, "flat := linalg.matrix_flatten(product)"), true)
    testing.expect_value(t, strings.contains(output, "q := quaternion(x=0.0, y=0.0, z=0.0, w=1.0)"), true)
    testing.expect_value(t, strings.contains(output, "q2 := quaternion(x=0.0, y=0.0, z=0.0, w=1.0)"), true)
    testing.expect_value(t, strings.contains(output, "unit := linalg.normalize(q)"), true)
    testing.expect_value(t, strings.contains(output, "return (linalg.dot(q, unit)) + (linalg.dot(q2, q2))"), true)
}

@(test)
compile_polymorphic_type_form :: proc(t: ^testing.T) {
    source := `(package main)
(import chan "core:sync/chan")

(defstruct Queue [
  jobs: (typeid chan.Chan int)
])

(defn recv-job [jobs: (typeid chan.Chan int)] -> int
  (let [[value ok] (chan.recv jobs)]
    (if ok value 0)))

(defn main []
  (let [[jobs err] (chan.create (typeid chan.Chan int) context.allocator)]
    (defer (chan.destroy jobs))
    (if (= err .None)
      (return)
      (return))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import chan "core:sync/chan"

Queue :: struct {
    jobs: chan.Chan(int),
}

recv_job :: proc(jobs: chan.Chan(int)) -> int {
    value, ok := chan.recv(jobs)
    if ok {
        return value
    }
    else {
        return 0
    }
}

main :: proc() {
    jobs, err := chan.create(chan.Chan(int), context.allocator)
    defer chan.destroy(jobs)
    if (err) == (.None) {
        return
    }
    else {
        return
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_typed_vector_literal_passes_element_type_to_let_items :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Entry [
  attrs: [dynamic]string
])

(defn entries [] -> [dynamic]Entry
  ([dynamic]Entry
    [(let [attrs ([dynamic]string ["name" "email"])]
       (Entry :attrs attrs))]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return [dynamic]Entry{"), true)
    testing.expect_value(t, strings.contains(output, "(proc() -> Entry {"), true)
    testing.expect_value(t, strings.contains(output, "attrs := [dynamic]string{\"name\", \"email\"}"), true)
}

@(test)
compile_type_call_expression_for_positional_odin_aggregates :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn main []
  (rl.SetWindowState (rl.ConfigFlags [.WINDOW_RESIZABLE]))
  (rl.ClearBackground (rl.Color [110 184 168 255])))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import rl "vendor:raylib"

main :: proc() {
    rl.SetWindowState(rl.ConfigFlags{.WINDOW_RESIZABLE})
    rl.ClearBackground(rl.Color{110, 184, 168, 255})
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_typed_odin_aggregate_keyword_labels :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn rect [frame: int width: f32 frames: int height: f32] -> rl.Rectangle
  (rl.Rectangle :x (/ (* (f32 frame) width) (f32 frames))
                 :y 0
                 :width (/ width (f32 frames))
                 :height height))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import rl "vendor:raylib"

rect :: proc(frame: int, width: f32, frames: int, height: f32) -> rl.Rectangle {
    return rl.Rectangle{x = ((f32(frame)) * (width)) / (f32(frames)), y = 0, width = (width) / (f32(frames)), height = height}
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_keyword_literal_and_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn mode [] -> keyword
  :dev)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

mode :: proc() -> keyword {
    return keyword(":dev")
}

keyword :: distinct string
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_namespaced_keyword_literal :: proc(t: ^testing.T) {
    source := `(package main)

(defn status [] -> keyword
  :job/queued)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

status :: proc() -> keyword {
    return keyword(":job/queued")
}

keyword :: distinct string
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_keyword_literal_with_embedded_colon :: proc(t: ^testing.T) {
    source := `(package main)

(defn attribute [] -> keyword
  :data-on:submit__prevent)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, `keyword(":data-on:submit__prevent")`), true)
}

@(test)
compile_keyword_struct_field_and_comparison :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Config [
  mode: keyword
])

(defn dev? [cfg: Config] -> bool
  (= cfg.mode :dev))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Config :: struct {
    mode: keyword,
}

dev_p :: proc(cfg: Config) -> bool {
    return (cfg.mode) == (keyword(":dev"))
}

keyword :: distinct string
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_typed_odin_aggregate_positional_vector_literal :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn platform-collider [pos: rl.Vector2] -> rl.Rectangle
  (rl.Rectangle [pos.x pos.y 96 16]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import rl "vendor:raylib"

platform_collider :: proc(pos: rl.Vector2) -> rl.Rectangle {
    return rl.Rectangle{pos.x, pos.y, 96, 16}
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_accepts_imported_struct_positional_arguments :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn bad [] -> rl.Vector2
  (rl.Vector2 0 0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "return rl.Vector2{0, 0}"), true)
}

@(test)
compile_accepts_local_struct_positional_arguments :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User [
  name: string
  email: string
])

(defn make-user [] -> User
  (User "name1" "email1"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "return User{\"name1\", \"email1\"}"), true)
}

@(test)
compile_accepts_order_independent_named_struct_arguments :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn rect [] -> rl.Rectangle
  (rl.Rectangle :height 1 :x 0 :width 1 :y 0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return rl.Rectangle{height = 1, x = 0, width = 1, y = 0}"), true)
}

@(test)
compile_multiline_composite_literals :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Handler [
  run: (fn [] -> int)
])

(defn main []
  (let [handler (Handler :run (fn [] -> int
                                  42))
        handlers ((slice Handler)
                   [(Handler :run (fn [] -> int
                                      7))])]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Handler :: struct {
    run: proc() -> int,
}

main :: proc() {
    handler := Handler{
        run = proc() -> int {
            return 42
        },
    }
    handlers := []Handler{
        Handler{
            run = proc() -> int {
                return 7
            },
        },
    }
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_pointer_deref_and_address_of :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person [
  name: string
])

(defn ptr-value [x: ^int] -> int
  (deref x))

(defn bump [x: ^int]
  (set! (deref x) (+ (deref x) 1)))

(defn borrow-name [p: ^Person] -> ^string
  &p^.name)

(defn borrow-name-form [p: ^Person] -> ^string
  (addr p^.name))

(defn first-name [people: ^[]Person] -> string
  (deref people)[0].name)

(defn borrow-first-name [people: ^[]Person] -> ^string
  (addr (deref people)[0].name))

(defn borrow-cell [xs: [dynamic]int, i: int] -> ^int
  (addr xs[i]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Person :: struct {
    name: string,
}

ptr_value :: proc(x: ^int) -> int {
    return x^
}

bump :: proc(x: ^int) {
    x^ = (x^) + (1)
}

borrow_name :: proc(p: ^Person) -> ^string {
    return &(p^.name)
}

borrow_name_form :: proc(p: ^Person) -> ^string {
    return &(p^.name)
}

first_name :: proc(people: ^[]Person) -> string {
    return (people^)[0].name
}

borrow_first_name :: proc(people: ^[]Person) -> ^string {
    return &((people^)[0].name)
}

borrow_cell :: proc(xs: [dynamic]int, i: int) -> ^int {
    return &((xs)[i])
}
    `
    testing.expect_value(t, strings.trim_space(output), strings.trim_space(expected))
}

@(test)
compile_shallow_struct_assoc_exprs :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Point [
  x: int
  y: int
  name: string
])

(defn inc [x: int] -> int
  (+ x 1))

(defn add-scaled [x: int, scale: int, offset: int] -> int
  (+ (* x scale) offset))

(defn score [] -> int
  (let [point (Point :x 4 :y 5 :name "old")
        older (assoc point.name "new")
        legacy (assoc older .name "legacy")]
    (+ point.y older.y (count older.name) (count legacy.name))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "older := (proc(kvist_target: Point, kvist_value: string) -> Point {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_1 := kvist_target"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_1.name = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_update_1"), true)
    testing.expect_value(t, strings.contains(output, "})(point, \"new\")"), true)
    testing.expect_value(t, strings.contains(output, "legacy := (proc(kvist_target: Point, kvist_value: string) -> Point {"), true)
    testing.expect_value(t, strings.contains(output, "})(older, \"legacy\")"), true)
}

@(test)
compile_nested_struct_assoc_exprs :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Profile [
  name: string
  age: int
])

(defstruct User [
  profile: Profile
  active?: bool
])

(defn inc [x: int] -> int
  (+ x 1))

(defn score [user: User] -> int
  (let [renamed (assoc user.profile.name "Ada")
        active (assoc renamed .active? true)]
    (+ active.profile.age (count renamed.profile.name))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "renamed := (proc(kvist_target: User, kvist_value: string) -> User {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_1 := kvist_target"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_1.profile.name = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "})(user, \"Ada\")"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_2.active_p = kvist_value"), true)
}

@(test)
compile_threaded_shallow_struct_assoc_exprs :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct User [
  name: string
  age: int
  active?: bool
])

(defn score [user: User] -> int
  (let [updated (-> user
                  (assoc .active? false)
                  (assoc .name "Ada"))]
    (+ updated.age (count updated.name))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_update_1 := kvist_target"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_1.active_p = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_2.name = kvist_value"), true)
}

@(test)
compile_threaded_nested_struct_assoc_exprs :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Profile [
  name: string
  age: int
])

(defstruct User [
  profile: Profile
  active?: bool
])

(defn score [user: User] -> int
  (let [updated (-> user
                  (assoc .profile.name "Ada")
                  (assoc .active? true))]
    (+ updated.profile.age (count updated.profile.name))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_update_1.profile.name = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_2.active_p = kvist_value"), true)
}

@(test)
compile_threaded_shallow_struct_assoc_from_proc_return :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct User [
  name: string
  age: int
])

(defn inc [x: int] -> int
  (+ x 1))

(defn make-user [] -> User
  (User :name "Ada" :age 41))

(defn score [] -> int
  (let [updated (-> (make-user)
                  (assoc .age 42))]
    updated.age))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_update_1.age = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "})(make_user(), 42)"), true)
}

@(test)
compile_threaded_shallow_struct_update_exprs :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct User [
  age: int
])

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [user: User] -> User
  (-> user
    (update .age inc)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_update_1.age = (kvist_target.age) + 1"), true)
}

@(test)
reject_threaded_shallow_struct_assoc_unknown_field :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct User [
  age: int
])

(defn bad [user: User] -> User
  (-> user
    (assoc .missing 1)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "assoc could not find field .missing on User")
}

@(test)
reject_shallow_struct_update_non_field_selector :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point [
  x: int
])

(defn bad [point: Point] -> Point
  (assoc point 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "while expanding macro assoc: while expanding macro field-place: field place helper expects a field place such as user.name or user.address.city")
}

@(test)
compile_shallow_struct_update_exprs :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point [
  x: int
])

(defn good [point: Point] -> Point
  (update point.x + 2))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc(kvist_target: Point, kvist_arg_0: int) -> Point"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_1.x = (kvist_target.x) + (kvist_arg_0)"), true)
    testing.expect_value(t, strings.contains(output, "})(point, 2)"), true)
}

@(test)
compile_nested_struct_update_exprs :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Profile [
  age: int
])

(defstruct User [
  profile: Profile
])

(defn inc [x: int] -> int
  (+ x 1))

(defn good [user: User] -> User
  (core.update user.profile.age inc))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_update_1.profile.age = (kvist_target.profile.age) + 1"), true)
}

@(test)
compile_odin_shaped_type_spellings :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Raw-Types [
  values: []int
  fixed: [3]int
  buffer: [dynamic]int
  lookup: map[string]int
  next: ^Raw-Types
])

(defn values [state: ^Raw-Types] -> []int
  state^.values)

(defn main []
  (let [values ([]int [1 2 3])
        lookup (map[string]int {"one" 1})
        buffer-literal ([dynamic]int [1 2])
        buffer (make [dynamic]int)]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `#+feature dynamic-literals
package main

Raw_Types :: struct {
    values: []int,
    fixed: [3]int,
    buffer: [dynamic]int,
    lookup: map[string]int,
    next: ^Raw_Types,
}

values :: proc(state: ^Raw_Types) -> []int {
    return state^.values
}

main :: proc() {
    values := []int{1, 2, 3}
    lookup := map[string]int{"one" = 1}
    buffer_literal := [dynamic]int{1, 2}
    buffer := make([dynamic]int)
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_compact_type_spellings_inside_vectors :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn first [xs: []int, lookup: map[string]int] -> int
  (let [buffer: [dynamic]int (make [dynamic]int)
        fixed: [3]int ([3]int [1 2 3])
        from-map (get lookup "missing" -1)]
    (+ (get xs 0) from-map)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

first :: proc(xs: []int, lookup: map[string]int) -> int {
    buffer: [dynamic]int = make([dynamic]int)
    fixed: [3]int = [3]int{1, 2, 3}
    from_map := kvist_get_or_default(lookup, "missing", -1)
    return (xs[0]) + (from_map)
}

kvist_get_or_default :: proc(m: map[$K]$V, key: K, default: V) -> V {
    value, ok := m[key]
    if ok {
        return value
    }
    return default
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_unparenthesized_fn_type_spelling :: proc(t: ^testing.T) {
    source := `(package main)

(def default-pred: fn [x: int] -> bool
  (fn [x: int] -> bool
    true))

(defstruct Runner [
  run: fn [x: int] -> bool
])

(defunion Callback [
  pred: fn [x: int] -> bool
])

(defn apply-pred [pred: fn [x: int] -> bool, x: int] -> bool
  (pred x))

(defn always [] -> fn [x: int] -> bool
  (fn [x: int] -> bool
    true))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

default_pred: proc(x: int) -> bool : proc(x: int) -> bool {
    return true
}

Runner :: struct {
    run: proc(x: int) -> bool,
}

Callback :: union {
    proc(x: int) -> bool,
}

apply_pred :: proc(pred: proc(x: int) -> bool, x: int) -> bool {
    return pred(x)
}

always :: proc() -> proc(x: int) -> bool {
    return proc(x: int) -> bool {
        return true
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_typed_let_with_fn_type_spelling :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (let [pred: fn [x: int] -> bool (fn [x: int] -> bool
                                        true)]
    (pred 1)
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

main :: proc() {
    pred: proc(x: int) -> bool = proc(x: int) -> bool {
        return true
    }
    pred(1)
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
reject_typed_def_overload :: proc(t: ^testing.T) {
    source := `(package main)
(def render: int (overload render-int))`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "overload def cannot have an explicit type")
}

@(test)
compile_user_proc_supports_captured_callback_literal :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn apply-one [f: (fn [x: int] -> int), x: int] -> int\n  (f x))\n\n(defn demo [] -> int\n  (let [offset 10]\n    (apply-one (fn [x: int] -> int (+ x offset)) 5)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "apply_one__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "apply_one__kvist_capture_0_1 :: proc(f: proc(c1: $C1, x: int) -> int, kvist_capture_1: C1, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "return f(kvist_capture_1, x)"), true)
}

@(test)
compile_user_proc_supports_field_selector_callback :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defstruct User [name: string])\n\n(defn project-one [f: (fn [x: $T] -> $K), x: T] -> K\n  (f x))\n\n(defn demo [u: User] -> string\n  (project-one .name u))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "return project_one__kvist_field_0_name(type_of(u), type_of((u).name), u)"), true)
    testing.expect_value(t, strings.contains(output, "project_one__kvist_field_0_name :: proc($T: typeid, $K: typeid, x: T) -> K {"), true)
    testing.expect_value(t, strings.contains(output, "return x.name"), true)
}

@(test)
compile_remove_supports_single_captured_local_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: [dynamic]int] -> [dynamic]int\n  (let [limit 10]\n    (arr.remove (fn [x: int] -> bool\n                  (> x limit))\n                xs)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "arr__remove_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(limit: int, x: int) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "arr__remove_impl__kvist_capture_0_1 :: proc(pred: proc(c1: $C1, x: $T) -> bool, kvist_capture_1: C1, xs: []T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_remove_1"), false)
}

@(test)
compile_keep_supports_single_captured_local_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: [dynamic]int] -> [dynamic]int\n  (let [limit 10]\n    (arr.keep (fn [x: int] -> [value: int, ok: bool]\n                (if (> x limit)\n                  (return x true)\n                  (return 0 false)))\n              xs)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "arr__keep_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(limit: int, x: int) -> (value: int, ok: bool) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__keep_impl__kvist_capture_0_1 :: proc(f: proc(c1: $C1, x: $T) -> (value: $U, ok: bool), kvist_capture_1: C1, xs: []T) -> [dynamic]U {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_keep_1"), false)
}

@(test)
compile_parenthesized_nested_fn_type_spelling :: proc(t: ^testing.T) {
    source := `(package main)

(defn identity-factory [f: (fn [x: int] -> fn [y: int] -> bool)] -> (fn [x: int] -> fn [y: int] -> bool)
  f)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

identity_factory :: proc(f: proc(x: int) -> proc(y: int) -> bool) -> proc(x: int) -> proc(y: int) -> bool {
    return f
}
`
    testing.expect_value(t, output, expected)
}

@(test)
type_named_destroy_and_clone_do_not_create_a_protocol :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Handle [
  raw: rawptr
])

(defn Handle-destroy [handle: Handle]
  (discard handle))

(defn Handle-clone [handle: Handle] -> Handle
  handle)

(defn copy [handle: Handle] -> Handle
  handle)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_managed_destroy_Handle"), false)
    testing.expect_value(t, strings.contains(output, "kvist_managed_clone_Handle"), false)
    testing.expect_value(t, strings.contains(output, "copy :: proc(handle: Handle) -> Handle"), true)
}

@(test)
tracked_native_storage_moves_into_ordinary_struct_fields :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Box [
  values: [dynamic]int
])

(defn use-box [] -> int
  (let [values (make [dynamic]int)
        box (Box :values values)]
    (defer (delete box.values))
    (count box.values)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "box := Box{values = values}"), true)
    testing.expect_value(t, strings.contains(output, "kvist_owner^ = false; return kvist_value"), false)
    testing.expect_value(t, strings.contains(output, "defer delete(box.values)"), true)
}
