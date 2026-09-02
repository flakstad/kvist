package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
compile_defstruct_rejects_bad_metadata :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Broken
  [tags: [slice]
   scores: [array int]])`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "expects one element type") || strings.contains(err.message, "invalid defstruct field type metadata"), true)
}

@(test)
compile_defstruct_rejects_package_shaped_type_metadata :: proc(t: ^testing.T) {
    sources := []string{
        `(package main)

(defstruct Broken
  [items: [arr int]])`,
        `(package main)

(defstruct Broken
  [items: [fixed-arr 4 int]])`,
        `(package main)

(defstruct Broken
  [items: [set int]])`,
    }
    for source in sources {
        _, err, ok := kvist.compile_source(source)
        testing.expect_value(t, ok, false)
        if ok {
            continue
        }
        defer delete(err.message)
        testing.expect_value(t, strings.contains(err.message, "invalid defstruct field type metadata"), true)
    }
}

@(test)
compile_quote_as_first_class_data :: proc(t: ^testing.T) {
    source := `(package main)

(def config
  '{:port 8080
    :features #{:query :pull}})

(def query
  '[:find ?name :where [?e :user/name ?name]])

(def aggregate-query
  '[:find (count ?e) . :where [?e :object/name ?name]])

(defn inspect [] -> int
  (let [features (get config :features)]
    (if (contains? features :query)
      (+ (int (data.int (get config :port))) (count query))
      0)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "config: Data = Data{kind = .Map"), true)
    testing.expect_value(t, strings.contains(output, "query: Data = Data{kind = .Vector"), true)
    testing.expect_value(t, strings.contains(output, "aggregate_query: Data = Data{kind = .Vector"), true)
    testing.expect_value(t, strings.contains(output, "text = \"count\""), true)
    testing.expect_value(t, strings.contains(output, "text = \"odin-call\""), false)
    testing.expect_value(t, strings.contains(output, "kvist_data_get(config, Data{kind = .Keyword, payload = {text = \":features\"}})"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_contains(features, Data{kind = .Keyword, payload = {text = \":query\"}})"), true)
    testing.expect_value(t, strings.contains(output, "Data_Kind :: enum"), true)
    testing.expect_value(t, strings.contains(output, "Data_Payload :: struct #raw_union"), true)
    testing.expect_value(t, strings.contains(output, "payload: Data_Payload"), true)
    testing.expect_value(t, strings.contains(output, "Data_Node :: struct"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_retain :: proc"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_release :: proc"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_same_backing :: proc"), true)
    testing.expect_value(t, strings.contains(output, "case .String, .Symbol, .Keyword: return a.payload.text == b.payload.text\n        case .Tagged:\n            if kvist_data_same_backing(a, b) { return true }"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_freeze_unique_map :: proc"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_data_retain(entry.value), true"), true)
    testing.expect_value(t, strings.contains(output, "if found_index >= 0 && kvist_data_equal(collection.payload.entries[found_index].value, value) { return kvist_data_retain(collection) }"), true)
    testing.expect_value(t, strings.contains(output, "if found_index < 0 { return kvist_data_retain(collection) }"), true)
    testing.expect_value(t, strings.contains(output, "import kvist_sync \"core:sync\""), true)
}

@(test)
compile_data_let_destructuring :: proc(t: ^testing.T) {
    source := `(package main)

(defn contact-name [contact: Data] -> Data
  (let [{:keys [name]
         :person/keys [email]
         :strs [external-id]
         :syms [status]
         :or {name "Anonymous"}
         :as original}
        contact]
    name))

(defn second-item [items: Data] -> Data
  (let [[first second & remaining :as original] items]
    second))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_data_get_present"), true)
    testing.expect_value(t, strings.contains(output, "\":person/email\""), true)
    testing.expect_value(t, strings.contains(output, "\"external-id\""), true)
    testing.expect_value(t, strings.contains(output, "kind = .Symbol"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_rest_from"), true)
    testing.expect_value(t, strings.contains(output, "defer kvist_data_release(name)"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_data_retain(name)"), true)
}

@(test)
reject_duplicate_data_destructuring_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn invalid [value: Data]
  (let [[item {:keys [item]}] value]
    item))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "duplicate Data pattern binding `item`")
}

@(test)
compile_structural_data_match :: proc(t: ^testing.T) {
    source := `(package main)

(defn dispatch [message: Data] -> Data
  (match message
    {:op :query :query query}
    query

    (as whole (kind :vector [head & tail]))
    head

    #{:ready :running}
    :active

    :else
    nil))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, ".kind == .Map"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_contains(message"), false)
    testing.expect_value(t, strings.contains(output, "kvist_data_contains("), true)
    testing.expect_value(t, strings.contains(output, ".kind == .Vector"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_rest_from"), true)
    testing.expect_value(t, strings.contains(output, "defer kvist_data_release(query)"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_data_retain(query)"), true)
}

@(test)
reject_non_exhaustive_data_match :: proc(t: ^testing.T) {
    source := `(package main)

(defn dispatch [message: Data] -> Data
  (match message
    {:op :query}
    :query))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "final :else or _"), true)
}

@(test)
compile_every_data_kind_match_pattern :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [value: Data] -> int
  (match value
    (kind :nil _) 0
    (kind :bool x) 1
    (kind :int x) 2
    (kind :float x) 3
    (kind :string x) 4
    (kind :symbol x) 5
    (kind :keyword x) 6
    (kind :list x) 7
    (kind :vector x) 8
    (kind :map x) 9
    (kind :set x) 10
    (kind :tagged x) 11
    :else 12))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, ".kind == .Nil"), true)
    testing.expect_value(t, strings.contains(output, ".kind == .Tagged"), true)
}

@(test)
reject_duplicate_exact_literal_data_match_arm :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [value: Data] -> int
  (match value
    :ready 1
    :ready 2
    :else 0))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "duplicate exact literal match arm")
}

@(test)
compile_eval_data_destructuring_and_match :: proc(t: ^testing.T) {
    source := `(package main)

(def input '{:name "Ada"})`

    output, err, ok := kvist.compile_eval_source(
        source,
        `(let [{:keys [name]} input]
           (match name
             "Ada" :known
             :else :unknown))`,
        false,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "kvist_data_get_present"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_equal"), true)
}

@(test)
reject_invalid_data_match_pattern_shapes :: proc(t: ^testing.T) {
    source := `(package main)

(defn invalid [value: Data] -> int
  (match value
    {runtime-key captured} 1
    :else 0))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "match map keys must be compile-time Data literals")
}

@(test)
compile_data_destructuring_for :: proc(t: ^testing.T) {
    source := `(package main)

(defn total-ids [rows: Data] -> i64
  (let [total: i64 0]
    (for [[id title] rows]
      (set! total (+ total (data.int id))))
    (for [index [id title] rows]
      (set! total (+ total (i64 index))))
    total))

(defn native-names [rows: []Data] -> int
  (let [seen: int 0]
    (for [{:keys [name]} rows]
      (set! seen (+ seen (if (data.nil? name) 0 1))))
    seen))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "Data for source must be nil, list, vector, or set"), true)
    testing.expect_value(t, strings.contains(output, ".payload.items {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_nth_or_nil"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_get_present"), true)
    testing.expect_value(t, strings.contains(output, ", index in"), true)
}

@(test)
compile_runtime_data_def_retains_borrowed_result :: proc(t: ^testing.T) {
    source := `(package main)

(def base '{:answer 42})

(defn identity-data [value: Data] -> Data
  value)

(def copy (identity-data base))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "copy = identity_data(base)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_release(copy)"), true)
}

@(test)
compile_imported_data_runtime_uses_required_import_aliases :: proc(t: ^testing.T) {
    source := `(package main)
(import edn "kvist:edn")

(defn render [text: string] -> string
  (edn.write (edn.read text)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "Data_Kind :: enum"), true)
    testing.expect_value(t, strings.contains(output, "import kvist_runtime \"base:runtime\""), true)
    testing.expect_value(t, strings.contains(output, "import kvist_sync \"core:sync\""), true)
    testing.expect_value(t, strings.contains(output, "items := make([dynamic]Data)"), true)
    testing.expect_value(t, strings.contains(output, "edn__data__append_retained_bang(&items, item)"), true)
    testing.expect_value(t, strings.contains(output, "result = edn__data__append(result, item)"), false)
}

@(test)
compile_manages_data_local_bindings_and_returns :: proc(t: ^testing.T) {
    source := `(package main)

(def config '{:port 8080})

(defn identity-data [value: Data] -> Data
  value)

(defn config-copy [] -> Data
  (let [copy config]
    copy))

(defn port-data [] -> Data
  (get config :port))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return kvist_data_retain(value)"), true)
    testing.expect_value(t, strings.contains(output, "copy := kvist_data_retain(config)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_release(kvist_place^)"), true)
    testing.expect_value(t, strings.contains(output, "return (proc(kvist_value: Data, kvist_owner: ^bool) -> Data"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_value })(copy, &kvist_owner_"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_data_retain(kvist_data_get(config"), true)
}

@(test)
compile_manages_data_assignment_places :: proc(t: ^testing.T) {
    source := `(package main)

(def config '{:port 8080})

(defstruct Box [
  value: Data
])

(defn make-data [] -> Data
  config)

(defn replace [input: Data]
  (let [local config
        box (Box :value config)
        values: [1]Data [config]]
    (set! local input)
    (set! box.value input)
    (set! values[0] input)
    (set! local (make-data))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_data_assign(&(local), input)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_assign(&(box.value), input)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_assign(&((values)["), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_move_assign(&(local), make_data())"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_assign :: proc(place: ^Data, value: Data)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_move_assign :: proc(place: ^Data, value: Data)"), true)
}

@(test)
compile_manages_data_fields_in_native_structs :: proc(t: ^testing.T) {
    source := `(package main)

(def config '{:port 8080})

(defstruct Box [
  value: Data
])

(defstruct Envelope [
  box: Box
  label: string
  revision: int
])

(defn make-box [value: Data] -> Box
  (Box :value value))

(defn copy-box [box: Box] -> Box
  (let [copy box]
    copy))

(defn wrap [box: Box] -> Envelope
  (Envelope :box box :label "config" :revision 1))

(defn with-value [box: Box, value: Data] -> Box
  (copy-with box .value value))

(defn with-label [envelope: Envelope, label: string] -> Envelope
  (copy-with envelope .label label))

(defn revise [envelope: Envelope] -> Envelope
  (copy-update envelope .revision inc))

(defn observe [box: Box] -> int
  (discard box)
  1)

(defn nested [value: Data] -> int
  (observe (make-box value)))

(defn discard-box [value: Data]
  (discard (make-box value)))

(defn maybe-box [value: Data] -> [box: Box, ok: bool]
  (return (make-box value) true))

(defn receive-box [value: Data]
  (let [[box ok] (maybe-box value)]
    (discard box ok)))

(defn replace [box: Box, replacement: Box]
  (let [local box]
    (set! local replacement)
    (set! local (make-box config))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_managed_clone_Box :: proc(value: Box) -> Box"), true)
    testing.expect_value(t, strings.contains(output, "out.value = kvist_data_retain(value.value)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_managed_destroy_Box :: proc(value: Box)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_release(value.value)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_managed_assign_Box :: proc(place: ^Box, value: Box)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_managed_move_assign_Box :: proc(place: ^Box, value: Box)"), true)
    testing.expect_value(t, strings.contains(output, "return Box{value = kvist_data_retain(value)}"), true)
    testing.expect_value(t, strings.contains(output, "copy := kvist_managed_clone_Box(box)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_managed_destroy_Box(kvist_place^)"), true)
    testing.expect_value(t, strings.contains(output, "return (proc(kvist_value: Box, kvist_owner: ^bool) -> Box"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_value })(copy, &kvist_owner_"), true)
    testing.expect_value(t, strings.contains(output, "out.box = kvist_managed_clone_Box(value.box)"), true)
    testing.expect_value(t, strings.contains(output, "return Envelope{box = kvist_managed_clone_Box(box), label = \"config\", revision = 1}"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_1 := kvist_managed_clone_Box(kvist_target)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_assign(&(kvist_update_1.value), kvist_value)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_2 := kvist_managed_clone_Envelope(kvist_target)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_2.label = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_3 := kvist_managed_clone_Envelope(kvist_target)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_3.revision = (kvist_target.revision) + 1"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_4 := make_box(value)"), true)
    testing.expect_value(t, strings.contains(output, "defer kvist_managed_destroy_Box(kvist_thread_4)"), true)
    testing.expect_value(t, strings.contains(output, "observe(kvist_thread_4)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_5 := make_box(value)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_managed_destroy_Box(kvist_thread_5)"), true)
    testing.expect_value(t, strings.contains(output, "defer kvist_managed_destroy_Box(box)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_managed_assign_Box(&(local), replacement)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_managed_move_assign_Box(&(local), make_box(config))"), true)
}

@(test)
managed_data_struct_results_do_not_warn_for_automatic_cleanup :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Box [
  value: Data
])

(defn make-box [value: Data] -> Box
  (Box :value value))

(defn use [value: Data]
  (discard (make-box value)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 0)
    testing.expect_value(t, strings.contains(result.output, "kvist_managed_destroy_Box(kvist_thread_"), true)
}

@(test)
owned_data_locals_move_into_struct_fields_without_an_extra_retain :: proc(
    t: ^testing.T,
) {
    source := `(package main)

(import data "kvist:data")

(defstruct Report [
  root: Data
  child: Data
])

(defn make-report [] -> Report
  (let [root: Data {:items [1 2 3]}
        child (data.get-in root [:items])]
    (Report :root root :child child)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(
        t,
        strings.contains(
            output,
            "root = (proc(kvist_value: Data, kvist_owner: ^bool) -> Data",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            "child = (proc(kvist_value: Data, kvist_owner: ^bool) -> Data",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            "kvist_data_retain((proc(kvist_value: Data, kvist_owner: ^bool)",
        ),
        false,
    )
}

@(test)
compile_data_decode_infers_owned_string_struct_fields :: proc(t: ^testing.T) {
    source := `(package main)
(import data "kvist:data")

(defstruct Person [
  name: string
])

(defn decode-person [value: Data] -> [person: Person, err: data.Decode-Error, ok: bool]
  (data.decode Person value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "delete(value.name)"), true)
}

@(test)
compile_data_decode_rejects_native_string_arrays :: proc(t: ^testing.T) {
    source := `(package main)
(import data "kvist:data")

(defstruct Names [
  values: [dynamic]string
])

(defn decode-names [value: Data] -> [names: Names, err: data.Decode-Error, ok: bool]
  (data.decode Names value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    delete(output)
    defer delete(err.message)
    testing.expect_value(
        t,
        err.message,
        "data.decode field values has unsupported dynamic-array element type string; supported elements are Data, bool, integer and floating-point scalars, Kvist enums, and Kvist structs",
    )
}

@(test)
compile_data_decode_diagnostic_uses_plain_type_syntax :: proc(t: ^testing.T) {
    source := `(package main)
(import data "kvist:data")

(defstruct Native-Handle [
  value: ^int
])

(defn decode-handle [value: Data] -> [handle: Native-Handle, err: data.Decode-Error, ok: bool]
  (data.decode Native-Handle value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    delete(output)
    defer delete(err.message)
    testing.expect_value(
        t,
        err.message,
        "data.decode field Native_Handle.value has unsupported type ^int; supported fields are string, Data, bool, integer and floating-point scalars, enums, nested Kvist structs, and dynamic arrays of supported non-string values",
    )
    testing.expect_value(t, strings.contains(err.message, "(owned "), false)
}

@(test)
compile_data_decode_direct_dynamic_arrays :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_path_with_map("examples/data/direct-collection-decode.kvist")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_data_make_items(Data_Kind.Vector, []Data{Data{kind = .Int",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(result.output, "defer kvist_data_release(kvist_thread_"),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "-> (decoded: [dynamic]i64, err: data__Decode_Error, ok: bool)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_data_append(kvist_error_path_0, kvist_index_key_0)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "proc(kvist_items: []Data) -> [dynamic]i64",
        ),
        true,
    )
    testing.expect_value(t, strings.contains(result.output, "defer delete(ids)"), true)
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "-> (decoded: [dynamic]Endpoint, err: data__Decode_Error, ok: bool)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_data_append(kvist_error_path_1, kvist_index_key_0)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "for kvist_item in kvist_values { kvist_managed_destroy_Endpoint(kvist_item) }; delete(kvist_values)",
        ),
        true,
    )
}

@(test)
compile_data_validate_reuses_type_directed_shape :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_path_with_map("examples/data/validated-shapes.kvist")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(result.output, "message: Data = kvist_data_make_map("),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "-> (err: data__Decode_Error, ok: bool)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "-> (decoded: Message, err: data__Decode_Error, ok: bool)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_data_append(kvist_error_path_7, kvist_index_key_5)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "-> (decoded: [dynamic]Endpoint, err: data__Decode_Error, ok: bool)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "defer kvist_managed_destroy_data__Decode_Error(err)",
        ),
        true,
    )
    testing.expect_value(t, strings.contains(result.output, "return Message{"), false)
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "make([dynamic]Endpoint, 0, len(kvist_items))",
        ),
        false,
    )
}

@(test)
compile_type_directed_data_struct_decode :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_path_with_map("examples/data/typed-struct-decode.kvist")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "-> (decoded: Settings, err: data__Decode_Error, ok: bool)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `Endpoint{host_id = 6, display_name = strings.clone("unnamed"), secure = false, tags = kvist_data_retain(`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_present_2 := kvist_data_contains(kvist_value, kvist_key_2)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "ratio = kvist_present_2 ? f64(kvist_field_2.payload.float_value) : 1.0",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `display_name = kvist_present_6 ? strings.clone(kvist_field_6.payload.text) : strings.clone("unnamed")`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "tags = kvist_present_8 ? kvist_data_retain(kvist_field_8) : kvist_data_retain(",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "mode = kvist_present_9 ? kvist_enum_9 : .Manual",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_present_10 && (kvist_field_11.kind != .Int)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `fallback_endpoint = kvist_present_10 ? Endpoint{`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "for kvist_item_15, kvist_index_15 in kvist_field_15.payload.items",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_data_append(kvist_error_path_15, kvist_index_key_15)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "proc(kvist_items: []Data) -> [dynamic]i64",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "out.scores = (proc(kvist_values: [dynamic]i64) -> [dynamic]i64",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "out.raw_items = (proc(kvist_values: [dynamic]Data) -> [dynamic]Data",
        ),
        true,
    )
    testing.expect_value(t, strings.contains(result.output, "delete(value.scores)"), true)
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "for kvist_item in kvist_values { kvist_data_release(kvist_item) }; delete(kvist_values)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_item_19.payload.text != ":manual"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `data__decode_enum_error(kvist_enum_error_path_19, "Mode", kvist_item_19)`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "proc(kvist_items: []Data) -> [dynamic]Mode",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "for kvist_item_20, kvist_index_20 in kvist_field_20.payload.items",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_data_append(kvist_error_path_21, kvist_index_key_20)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "proc(kvist_items: []Data) -> [dynamic]Endpoint",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "out.endpoints = (proc(kvist_values: [dynamic]Endpoint) -> [dynamic]Endpoint",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "for kvist_item in kvist_values { kvist_managed_destroy_Endpoint(kvist_item) }; delete(kvist_values)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "data__decode_error(kvist_error_path_7, .Bool, kvist_field_7.kind)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_data_move_assign(&kvist_error_path_7, kvist_data_append(kvist_error_path_7, kvist_key_4))",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_data_move_assign(&kvist_error_path_7, kvist_data_append(kvist_error_path_7, kvist_key_7))",
        ),
        true,
    )
    testing.expect_value(t, strings.contains(result.output, `case ":read-only": kvist_enum_9 = .Read_Only`), true)
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `data__decode_enum_error(kvist_enum_error_path_9, "Mode", kvist_field_9)`,
        ),
        true,
    )
    testing.expect_value(t, strings.contains(result.output, "out.actual_value = kvist_data_retain(value.actual_value)"), true)
    testing.expect_value(t, strings.contains(result.output, "out.display_name = strings.clone(value.display_name)"), true)
    testing.expect_value(t, strings.contains(result.output, "delete(value.display_name)"), true)
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_replacement := strings.clone(kvist_value); kvist_previous := kvist_place^",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(result.output, ".endpoint.display_name = strings.clone(kvist_value)"),
        true,
    )
    testing.expect_value(t, strings.contains(result.output, "defer kvist_managed_destroy_Settings(settings)"), true)
    testing.expect_value(
        t,
        strings.contains(result.output, "defer kvist_managed_destroy_data__Decode_Error(err)"),
        true,
    )
}

@(test)
compile_data_decode_qualifies_support_inside_nested_source_packages :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-nested-data-decode-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    helper_dir, helper_dir_err := os.join_path({dir, "helper"}, context.allocator)
    testing.expect_value(t, helper_dir_err == nil, true)
    if helper_dir_err != nil {
        return
    }
    defer delete(helper_dir)
    app_dir, app_dir_err := os.join_path({dir, "app"}, context.allocator)
    testing.expect_value(t, app_dir_err == nil, true)
    if app_dir_err != nil {
        return
    }
    defer delete(app_dir)
    testing.expect_value(t, os.make_directory_all(helper_dir) == nil, true)
    testing.expect_value(t, os.make_directory_all(app_dir) == nil, true)

    helper_path, helper_path_err := os.join_path({helper_dir, "helper.kvist"}, context.allocator)
    testing.expect_value(t, helper_path_err == nil, true)
    if helper_path_err != nil {
        return
    }
    defer delete(helper_path)
    helper_source := `(package helper)
(import data "kvist:data")
(defn size [value: Data] -> int (count value))`
    testing.expect_value(t, os.write_entire_file_from_string(helper_path, helper_source) == nil, true)

    app_path, app_path_err := os.join_path({app_dir, "app.kvist"}, context.allocator)
    testing.expect_value(t, app_path_err == nil, true)
    if app_path_err != nil {
        return
    }
    defer delete(app_path)
    app_source := `(package app)
(import helper "../helper")
(import data "kvist:data")
(defstruct Command [ name: string ])
(defn run [] -> bool
  (let [payload: Data {:name "Ro"}
        [command err ok] (data.decode Command payload [:command])]
    (discard err)
    (and ok (= (helper.size payload) 1) (= command.name "Ro"))))`
    testing.expect_value(t, os.write_entire_file_from_string(app_path, app_source) == nil, true)

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)
(import app "./app")
(defn main [] (assert (app.run)))`
    testing.expect_value(t, os.write_entire_file_from_string(main_path, main_source) == nil, true)

    result, err, ok := kvist.compile_path_with_map(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    testing.expect_value(t, strings.contains(result.output, "data__Decode_Error :: app__data__Decode_Error"), true)
    testing.expect_value(t, strings.contains(result.output, "data__decode_error :: app__data__decode_error"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_managed_destroy_data__Decode_Error :: kvist_managed_destroy_app__data__Decode_Error"), true)
}

@(test)
compile_exposes_explicit_data_lifetime_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import data "kvist:data")

(defstruct Holder [ value: Data ])

(defn hold [value: Data] -> Holder
  (Holder :value (data.retain value)))

(defn release-holder [holder: Holder]
  (data.release holder.value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_data_retain(value)"), true)
    testing.expect_value(t, strings.contains(output, "release(holder.value)"), true)
}

@(test)
compile_honors_managed_data_return_contracts :: proc(t: ^testing.T) {
    source := `(package main)

(def config '{:port 8080})

(defn borrowed-data [value: Data] -> Data
  value)

(defn owned-data [] -> Data
  (odin-call "kvist_data_make_int" 42))

(defn use-values [] -> Data
  (let [borrowed (borrowed-data config)
        owned (owned-data)]
    (discard borrowed)
    owned))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "borrowed_data :: proc(value: Data) -> Data {"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_data_retain(value)"), true)
    testing.expect_value(t, strings.contains(output, "owned_data :: proc() -> Data {"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_data_make_int(42)"), true)
    testing.expect_value(t, strings.contains(output, "borrowed := borrowed_data(config)"), true)
    testing.expect_value(t, strings.contains(output, "owned := owned_data()"), true)
}

@(test)
compile_treats_data_freeze_runtime_results_as_owned :: proc(t: ^testing.T) {
    source := `(package main)

(defn freeze-items [values: ^[dynamic]Data] -> Data
  (odin-call "kvist_data_freeze_items" 2 values))

(defn freeze-map [values: ^[dynamic]Data] -> Data
  (odin-call "kvist_data_freeze_map" values))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(
        t,
        strings.contains(
            output,
            "return kvist_data_freeze_items(2, values)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            "return kvist_data_freeze_map(values)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, "kvist_data_retain(kvist_data_freeze_"),
        false,
    )
}

@(test)
compile_releases_nested_owned_data_arguments :: proc(t: ^testing.T) {
    source := `(package main)

(def config '{:port 8080})

(defn make-data [] -> Data
  (odin-call "kvist_data_make_int" 42))

(defn combine [left: Data, right: Data] -> Data
  left)

(defn nested [] -> Data
  (let [value (combine config (make-data))]
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := make_data()"), true)
    testing.expect_value(t, strings.contains(output, "defer kvist_data_release(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "combine(config, kvist_thread_1)"), true)
}

@(test)
compile_runtime_data_quasiquote :: proc(t: ^testing.T) {
    source := `(package main)

(defn build [entity: Data, name: string] -> Data
  ` + "`" + `[:db/add ~entity :user/name ~name])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_data_make_text(Data_Kind.String, name)"), true)
    testing.expect_value(t, strings.contains(output, "defer kvist_data_release(kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_make_items(Data_Kind.Vector, []Data{"), true)
}

@(test)
compile_runtime_data_quasiquote_struct_field :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Item [id: string])

(defn build [item: Item] -> Data
  ` + "`" + `[:db/add ~item.id :item/rank "1"])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_data_make_text(Data_Kind.String, item.id)"), true)
}

@(test)
compile_runtime_data_quasiquote_loop_struct_field :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Item [id: string])

(defn build [items: []Item]
  (for [item items]
    (discard ` + "`" + `[:db/add ~item.id :item/rank "1"])))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_data_make_text(Data_Kind.String, item.id)"), true)
}

@(test)
compile_runtime_data_quasiquote_splice :: proc(t: ^testing.T) {
    source := `(package main)

(def tail '[2 3])

(defn build [] -> Data
  ` + "`" + `[1 ~@tail 4])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_data_make_items_spliced(Data_Kind.Vector"), true)
    testing.expect_value(t, strings.contains(output, "Data_Piece{value = tail, splice = true}"), true)
}

@(test)
compile_manages_data_returned_by_proc_value :: proc(t: ^testing.T) {
    source := `(package main)

(def config '{:port 8080})

(defn apply-data [f: (fn [value: Data] -> Data)] -> Data
  (let [updated (f config)]
    updated))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "updated := kvist_data_retain(f(config))"), true)
    testing.expect_value(t, strings.contains(output, "defer kvist_data_release(updated)"), true)
    testing.expect_value(t, strings.contains(output, "return (proc(kvist_value: Data, kvist_owner: ^bool) -> Data"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_value })(updated, &kvist_owner_"), true)
}

@(test)
data_returning_overloads_follow_the_managed_calling_convention :: proc(t: ^testing.T) {
    source := `(package main)
(import data "kvist:data")

(def config '{:port 8080})

(defn from-int [value: int] -> Data
  config)

(defn from-string [value: string] -> Data
  config)

(def select (overload from-int from-string))

(defn use [] -> bool
  (let [value (select 42)]
    (data.nil? value)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "value := select(42)"), true)
    testing.expect_value(t, strings.contains(output, "value := kvist_data_retain(select(42))"), false)
    testing.expect_value(t, strings.contains(output, "defer (proc(kvist_place: ^Data, kvist_owner: ^bool)"), true)
}

@(test)
compile_manages_data_in_named_returns :: proc(t: ^testing.T) {
    source := `(package main)

(def config '{:port 8080})

(defn parse [] -> [value: Data, ok: bool]
  (return config true))

(defn parse-nested [fail: bool] -> [value: Data, ok: bool]
  (when fail
    (return config false))
  (return config true))

(defn use [] -> Data
  (let [[value ok] (parse)]
    (discard ok)
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return kvist_data_retain(config), true"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_data_retain(config), false"), true)
    testing.expect_value(t, strings.contains(output, "value, ok := parse()"), true)
    testing.expect_value(t, strings.contains(output, "defer kvist_data_release(value)"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_data_retain(value)"), true)
}

@(test)
compile_normalizes_managed_data_expression_ownership :: proc(t: ^testing.T) {
    source := `(package main)

(def config '{:port 8080})

(defn make-data [] -> Data
  (odin-call "kvist_data_make_int" 42))

(defn choose [use-static: bool] -> Data
  (let [selected: Data (if use-static config (make-data))
        through-block: Data (let [copy selected] copy)]
    through-block))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "selected: Data = (kvist_data_retain(config) if use_static else make_data())"), true)
    testing.expect_value(t, strings.contains(output, "selected := kvist_data_retain(("), false)
    testing.expect_value(t, strings.contains(output, "through_block: Data = copy"), true)
    testing.expect_value(t, strings.contains(output, "through_block := kvist_data_retain(proc("), false)
}

@(test)
compile_releases_data_conditional_used_as_borrowed_call_argument :: proc(t: ^testing.T) {
    source := `(package main)

(import data "kvist:data")

(defn count-data [value: Data] -> int
  (data.count value))

(defn selected-count [kind: string] -> int
  (count-data
    (cond
      (= kind "text") {:kind :text :value "hello"}
      (= kind "flag") {:kind :flag :value true}
      :else {:kind :date :value "2026-07-22"})))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "defer kvist_data_release(kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_retain((kvist_data_make_map"), false)
}

@(test)
compile_normalizes_managed_data_type_case_ownership :: proc(t: ^testing.T) {
    source := `(package main)

(def config '{:port 8080})

(defunion Choice [
  data: Data
  number: int
])

(defn select [choice: Choice] -> Data
  (let [selected: Data
          (type-case choice
            (Data value) value
            config)]
    selected))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "selected: Data = (proc("), true)
    testing.expect_value(t, strings.contains(output, "selected := kvist_data_retain(proc("), false)
    testing.expect_value(t, strings.contains(output, "return kvist_data_retain(value)"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_data_retain(config)"), true)
}

@(test)
compile_local_struct_shadows_package_struct_metadata :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Local [name: string])

(defn local-x [] -> int
  (defstruct Local [x: int])
  (let [value (Local :x 1)]
    value.x))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "Local :: struct {\n    name: string,\n}"), true)
    testing.expect_value(t, strings.contains(output, "    Local :: struct {\n        x: int,\n    }"), true)
    testing.expect_value(t, strings.contains(output, "value := Local{x = 1}"), true)
    testing.expect_value(t, strings.contains(output, "return value.x"), true)
}

@(test)
compile_cond_predicate_with_contextual_data_keeps_setup_inside_else :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Mutation [
  ok?: bool
])

(defn mutation [ok?: bool] -> Mutation
  (Mutation :ok? ok?))

(defn transact! [tx: Data] -> bool
  true)

(defn rename [empty?: bool] -> Mutation
  (cond
    empty? (mutation false)
    (transact! [[:db/add 1]]) (mutation true)
    :else (mutation false)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    setup := strings.index(output, "kvist_thread_1 := kvist_data_make_items")
    nested_if := strings.index(output, "if transact_bang(kvist_thread_2)")
    else_block := strings.index(output, "else {\n        kvist_thread_1")
    testing.expect_value(t, setup >= 0, true)
    testing.expect_value(t, nested_if > setup, true)
    testing.expect_value(t, else_block >= 0, true)
    testing.expect_value(t, strings.contains(output, "else if transact_bang"), false)
}

@(test)
compile_let_rejects_data_destructuring_of_native_struct :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User [
  name: string
  age: int
])

(defn main []
  (let [user (User :name "Ada" :age 36)
        {:name user-name :age user-age} user
        user-name user.name
        user-age user.age]
    (return)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "Data destructuring requires a statically known Data value"), true)
}

@(test)
compile_contextual_data_literals_in_direct_and_overloaded_calls :: proc(t: ^testing.T) {
    source := `(package main)
(import kdata "kvist:data")
(import fmt "core:fmt")

(def product-name "Ro")

(defn accept-data [value: Data] -> Data
  value)

(defn render-data [value: Data] -> int
  (count value))

(defn render-string [value: string] -> int
  (count value))

(def render (overload render-data render-string))

(defn card [title: string, ready?: bool] -> Data
  (accept-data
    [:article {:class "card" :hidden false}
     [:h1 title]
     (if ready?
       [:p "Ready"]
       nil)]))

(defn card-size [title: string] -> int
  (render [:article {:class "card"} [:h1 title]]))

(defn contact-tx [id: i64, name: string, email: string, company: string] -> Data
  [{:db/id id
    :contact/name name
    :contact/email email
    :contact/company company}])

(defn add-attention [tx: Data, condition-id: i64, instant: string] -> Data
  (kdata.conj tx
    [:db/add [:ro/id condition-id] :attention/not-before instant]))

(defn measurements [count: int, ratio: f64] -> Data
  [(+ count 1) (+ 1 ratio)])

(defn heading [count: int] -> Data
  [:header
   [:style product-name]
   [:h1 (fmt.tprintf "%d matters" count)]
   [:p (fmt.aprintf "%d owned" count)]])

(defn append-owned-local [tx: Data, prefix: string] -> Data
  (let [option-id (fmt.aprintf "option-%s" prefix)]
    (kdata.conj tx
      {:db/id option-id
       :ro/id option-id})))

(defn append-data [tx: Data, value: Data] -> Data
  (kdata.conj tx value))

(defn append-keyword-map [tx: Data, id: string] -> Data
  (append-data tx {:db/id id :ro/id id}))

(defn source-int [value: int] -> Data
  [value])

(defn source-string [value: string] -> Data
  [value])

(def source (overload source-int source-string))

(defn source-contains? [value: string] -> bool
  (let [result (source value)]
    (contains? result [value])))

(defn indexed-values [values: []string] -> Data
  (let [result: Data []]
    (for [value index values]
      (set! result (kdata.conj result [value index])))
    result))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "accept_data(kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_make_map([]Data{"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_make_text(Data_Kind.String, title)"), true)
    testing.expect_value(t, strings.contains(output, "render(kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "contact_name"), false)
    testing.expect_value(t, strings.contains(output, "kvist_data_make_int(i64(id))"), true)
    testing.expect_value(t, strings.contains(output, "kdata__conj(tx, kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "append_data(tx, kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "defer kvist_data_release(kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_make_int(i64((count) + (1)))"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_make_float(f64((1) + (ratio)))"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_make_text(Data_Kind.String, product_name)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_lift(fmt.tprintf(\"%d matters\", count))"), true)
    testing.expect_value(t, strings.contains(output, ":= fmt.aprintf(\"%d owned\", count)"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_lift(kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_make_text(Data_Kind.String, option_id)"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_data_contains(result, kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_make_text(Data_Kind.String, value)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_make_int(i64(index))"), true)
}

@(test)
compile_fused_data_collection_transform_owns_intermediates :: proc(t: ^testing.T) {
    source := `(package main)
(import data "kvist:data")

(defn increment [value: Data] -> Data
  (data.from-int (+ (data.int value) 1)))

(defn above-two? [value: Data] -> bool
  (> (data.int value) 2))

(defn add-value [total: i64, value: Data] -> i64
  (+ total (data.int value)))

(defn duplicate [value: Data] -> Data
  [value value])

(deftransform selected
  (map increment)
  (filter above-two?))

(deftransform duplicated
  (mapcat duplicate)
  (filter above-two?))

(deftransform unique
  (distinct))

(deftransform unique-by-value
  (distinct-by increment))

(defn collect [values: Data] -> Data
  (into Data selected values))

(defn collect-duplicates [values: Data] -> Data
  (into Data duplicated values))

(defn collect-unique [values: Data] -> Data
  (into Data unique values))

(defn collect-unique-by [values: Data] -> Data
  (into Data unique-by-value values))

(defn total [values: Data] -> i64
  (transduce (filter above-two?) add-value (i64 0) values))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc(kvist_source: Data) -> Data"), true)
    testing.expect_value(t, strings.contains(output, "make([dynamic]Data, 0, kvist_data_count(kvist_source))"), true)
    testing.expect_value(t, strings.contains(output, "for kvist_item in kvist_source.payload.items"), true)
    testing.expect_value(t, strings.contains(output, "defer kvist_data_release(kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_append_retained(&kvist_out, kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_data_freeze_items(.Vector, &kvist_out)"), true)
    testing.expect_value(t, strings.contains(output, "Data mapcat transform callback expects nil, list, vector, or set"), true)
    testing.expect_value(t, strings.contains(output, "for kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, ".payload.items"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_slice_contains"), true)
    testing.expect_value(t, strings.contains(output, "make([dynamic]Data)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_append_retained(&kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_data_retain((proc(kvist_source: Data) -> Data"), false)
    testing.expect_value(t, strings.contains(output, "kvist_data_get_or :: proc"), true)
    testing.expect_value(t, strings.contains(output, "if value.kind == .Set { for item in value.payload.items"), true)
    testing.expect_value(t, strings.contains(output, "value.kind == .List || value.kind == .Vector { for item in value.payload.items"), false)
}

@(test)
package_artifacts_keep_quoted_data_literals_package_unique :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-package-data-literals-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    support_dir, support_dir_err := os.join_path({dir, "support"}, context.allocator)
    main_path, main_err := os.join_path({dir, "main.kvist"}, context.allocator)
    support_path, support_err := os.join_path({support_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, support_dir_err == nil && main_err == nil && support_err == nil, true)
    if support_dir_err != nil || main_err != nil || support_err != nil {
        return
    }
    defer delete(support_dir)
    defer delete(main_path)
    defer delete(support_path)
    testing.expect_value(t, os.make_directory_all(support_dir) == nil, true)
    testing.expect_value(t, os.write_entire_file_from_string(main_path, `(package main)
(import support "support")
(defn root-value [] -> Data '[])
(defn main [] (println (root-value) (support.value)))`) == nil, true)
    testing.expect_value(t, os.write_entire_file_from_string(support_path, `(package support)
(defn value [] -> Data '())`) == nil, true)

    result, err, ok := kvist.compile_path_with_package_artifacts(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer kvist.package_emit_result_delete(&result)

    support_literal_prefix := ""
    shared_output := ""
    for artifact in result.artifacts {
        if strings.contains(artifact.output, "support__value") {
            support_literal_prefix = fmt.tprintf("kvist_data_literal_%s_", artifact.id)
        }
        if artifact.id == "kvp_shared" {
            shared_output = artifact.output
        }
    }
    testing.expect_value(t, support_literal_prefix != "", true)
    testing.expect_value(t, shared_output != "", true)
    testing.expect_value(t, strings.contains(shared_output, support_literal_prefix), true)
    testing.expect_value(t, strings.contains(result.root.output, support_literal_prefix), false)
    testing.expect_value(t, strings.contains(shared_output, "kind = .List"), true)
    testing.expect_value(t, strings.contains(shared_output, "kind = .Vector"), true)
}

@(test)
borrowed_data_results_become_safe_managed_locals :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-data-provenance-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package main)
(import data "kvist:data")

(defn view [value: Data] -> Data
  (data.nth value 0))

(defn use [value: Data] -> bool
  (let [item (view value)]
    (data.nil? item)))`
    testing.expect_value(t, os.write_entire_file_from_string(path, source) == nil, true)

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(
        t,
        strings.contains(
            output,
            "data__nth :: #force_inline proc(value: Data, index: int) -> Data {\n    return kvist_data_retain(kvist_data_get(",
        ),
        true,
    )
    testing.expect_value(t, strings.contains(output, "item := view(value)"), true)
    testing.expect_value(t, strings.contains(output, "defer (proc(kvist_place: ^Data, kvist_owner: ^bool)"), true)
}

@(test)
decoded_struct_fields_infer_structural_cleanup :: proc(t: ^testing.T) {
    source := `(package main)
(import data "kvist:data")

 (defstruct Record [
  name: string
  values: [dynamic]int
  value: Data
])

(defn decode-record [value: Data] -> Record
  (data.decode Record value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_managed_destroy_Record :: proc(value: Record)"), true)
    testing.expect_value(t, strings.contains(output, "delete(value.name)"), true)
    testing.expect_value(t, strings.contains(output, "delete(value.values)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_release(value.value)"), true)
}

@(test)
native_struct_named_data_does_not_enable_shared_data_runtime :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Data [
  id: int
  payload: string
])

(defn accept [value: Data] -> int
  value.id)

(defn demo [] -> int
  (accept (Data :id 7 :payload "native")))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "Data :: struct"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_retain"), false)
    testing.expect_value(t, strings.contains(output, "kvist_data_release"), false)
    testing.expect_value(t, strings.contains(output, "accept(Data{id = 7, payload = \"native\"})"), true)
}
