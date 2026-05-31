package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "base:runtime"

Imported_Symbol_Entry :: struct {
    alias: string,
    path:  string,
}

Imported_Symbol_Record :: struct {
    name:   string,
    record: string,
    rank:   int,
}

Builtin_Source_Entry :: struct {
    name:     string,
    relative: string,
    snippet:  string,
}

Package_Source_Entry :: struct {
    import_path: string,
    member:      string,
    relative:    string,
    snippet:     string,
}

Language_Source_Entry :: struct {
    name:     string,
    kind:     string,
    relative: string,
    snippet:  string,
}

KVIST_CANONICAL_IMPORTS_FOR_EDITOR :: [8]Imported_Symbol_Entry{
    {alias = "arr", path = "kvist:arr"},
    {alias = "str", path = "kvist:str"},
    {alias = "map", path = "kvist:map"},
    {alias = "set", path = "kvist:set"},
    {alias = "struct", path = "kvist:struct"},
    {alias = "io", path = "kvist:io"},
    {alias = "json", path = "kvist:json"},
    {alias = "http", path = "kvist:http"},
}

BUILTIN_SOURCE_ENTRIES :: []Builtin_Source_Entry{
    {name = "when-let", relative = "src/kvist/macroexpand.odin", snippet = "expand_when_let_form :: proc"},
    {name = "if-let", relative = "src/kvist/macroexpand.odin", snippet = "expand_if_let_form :: proc"},
    {name = "when-ok", relative = "src/kvist/macroexpand.odin", snippet = "expand_when_ok_form :: proc"},
    {name = "if-ok", relative = "src/kvist/macroexpand.odin", snippet = "expand_if_ok_form :: proc"},
    {name = "println", relative = "src/kvist/emit.odin", snippet = "if form.items[0].text == \"println\" || form.items[0].text == \"doc\""},
    {name = "doc", relative = "src/kvist/emit.odin", snippet = "case \"doc\":"},
    {name = "or-else", relative = "src/kvist/emit.odin", snippet = "if head.text == \"or-else\""},
    {name = "update!", relative = "src/kvist/emit.odin", snippet = "case \"update!\":"},
    {name = "update", relative = "src/kvist/emit.odin", snippet = "case \"update\":"},
    {name = "type", relative = "src/kvist/parse.odin", snippet = "if is_symbol(form.items[0], \"type\")"},
}

PACKAGE_SOURCE_ENTRIES :: []Package_Source_Entry{
    {import_path = "kvist:arr", member = "count", relative = "packages/arr/package.kvist", snippet = "(defmacro count [xs]"},
    {import_path = "kvist:arr", member = "map", relative = "packages/arr/package.kvist", snippet = "(defmacro map [f xs]"},
    {import_path = "kvist:arr", member = "filter", relative = "packages/arr/package.kvist", snippet = "(defmacro filter [pred xs]"},
    {import_path = "kvist:arr", member = "remove", relative = "packages/arr/package.kvist", snippet = "(defmacro remove [pred xs]"},
    {import_path = "kvist:arr", member = "reduce", relative = "packages/arr/package.kvist", snippet = "(defmacro reduce [f init xs]"},
    {import_path = "kvist:arr", member = "empty", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/empty\""},
    {import_path = "kvist:arr", member = "dynamic", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/dynamic\""},
    {import_path = "kvist:arr", member = "fixed", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/fixed\""},
    {import_path = "kvist:arr", member = "get", relative = "packages/arr/package.kvist", snippet = "(defmacro get [xs index]"},
    {import_path = "kvist:arr", member = "slice", relative = "packages/arr/package.kvist", snippet = "(defmacro slice [xs start & rest]"},
    {import_path = "kvist:arr", member = "push!", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/push!\""},
    {import_path = "kvist:arr", member = "range", relative = "packages/arr/package.kvist", snippet = "(defmacro range [& rest]"},
    {import_path = "kvist:arr", member = "map-indexed", relative = "src/kvist/emit.odin", snippet = "emit_core_map_indexed_helper :: proc"},
    {import_path = "kvist:arr", member = "keep", relative = "src/kvist/emit.odin", snippet = "emit_core_keep_helper :: proc"},
    {import_path = "kvist:arr", member = "mapcat", relative = "src/kvist/emit.odin", snippet = "emit_core_mapcat_helper :: proc"},
    {import_path = "kvist:arr", member = "first", relative = "packages/arr/package.kvist", snippet = "(defmacro first [xs]"},
    {import_path = "kvist:arr", member = "second", relative = "packages/arr/package.kvist", snippet = "(defmacro second [xs]"},
    {import_path = "kvist:arr", member = "last", relative = "packages/arr/package.kvist", snippet = "(defmacro last [xs]"},
    {import_path = "kvist:arr", member = "nth", relative = "packages/arr/package.kvist", snippet = "(defmacro nth [xs index]"},
    {import_path = "kvist:arr", member = "rest", relative = "packages/arr/package.kvist", snippet = "(defmacro rest [xs]"},
    {import_path = "kvist:arr", member = "butlast", relative = "packages/arr/package.kvist", snippet = "(defmacro butlast [xs]"},
    {import_path = "kvist:arr", member = "map!", relative = "src/kvist/emit.odin", snippet = "emit_core_map_in_place_helper :: proc"},
    {import_path = "kvist:arr", member = "map-indexed!", relative = "src/kvist/emit.odin", snippet = "emit_core_map_indexed_in_place_helper :: proc"},
    {import_path = "kvist:arr", member = "filter!", relative = "src/kvist/emit.odin", snippet = "emit_core_filter_in_place_helper :: proc"},
    {import_path = "kvist:arr", member = "remove!", relative = "src/kvist/emit.odin", snippet = "emit_core_remove_in_place_helper :: proc"},
    {import_path = "kvist:arr", member = "keep!", relative = "src/kvist/emit.odin", snippet = "emit_core_keep_in_place_helper :: proc"},
    {import_path = "kvist:arr", member = "into", relative = "src/kvist/emit.odin", snippet = "emit_core_into_helper :: proc"},
    {import_path = "kvist:arr", member = "into!", relative = "src/kvist/emit.odin", snippet = "if head.text == \"arr/into!\""},
    {import_path = "kvist:arr", member = "interpose", relative = "src/kvist/emit.odin", snippet = "emit_core_interpose_helper :: proc"},
    {import_path = "kvist:arr", member = "interleave", relative = "src/kvist/emit.odin", snippet = "emit_core_interleave_helper :: proc"},
    {import_path = "kvist:arr", member = "reverse", relative = "src/kvist/emit.odin", snippet = "emit_core_reverse_helper :: proc"},
    {import_path = "kvist:arr", member = "reverse!", relative = "src/kvist/emit.odin", snippet = "emit_core_reverse_in_place_helper :: proc"},
    {import_path = "kvist:arr", member = "shuffle", relative = "src/kvist/emit.odin", snippet = "emit_core_shuffle_helper :: proc"},
    {import_path = "kvist:arr", member = "shuffle!", relative = "src/kvist/emit.odin", snippet = "emit_core_shuffle_in_place_helper :: proc"},
    {import_path = "kvist:arr", member = "take", relative = "packages/arr/package.kvist", snippet = "(defmacro take [n xs]"},
    {import_path = "kvist:arr", member = "drop", relative = "packages/arr/package.kvist", snippet = "(defmacro drop [n xs]"},
    {import_path = "kvist:arr", member = "drop-last", relative = "packages/arr/package.kvist", snippet = "(defmacro drop-last [n xs]"},
    {import_path = "kvist:arr", member = "take-while", relative = "packages/arr/package.kvist", snippet = "(defmacro take-while [pred xs]"},
    {import_path = "kvist:arr", member = "drop-while", relative = "packages/arr/package.kvist", snippet = "(defmacro drop-while [pred xs]"},
    {import_path = "kvist:arr", member = "split-at", relative = "src/kvist/emit.odin", snippet = "emit_core_split_at_helper :: proc"},
    {import_path = "kvist:arr", member = "partition", relative = "src/kvist/emit.odin", snippet = "emit_core_partition_helper :: proc"},
    {import_path = "kvist:arr", member = "partition-all", relative = "src/kvist/emit.odin", snippet = "emit_core_partition_all_helper :: proc"},
    {import_path = "kvist:arr", member = "partition-by", relative = "src/kvist/emit.odin", snippet = "emit_core_partition_by_helper :: proc"},
    {import_path = "kvist:arr", member = "index-by", relative = "src/kvist/emit.odin", snippet = "emit_core_index_by_helper :: proc"},
    {import_path = "kvist:arr", member = "group-by", relative = "src/kvist/emit.odin", snippet = "emit_core_group_by_helper :: proc"},
    {import_path = "kvist:arr", member = "count-by", relative = "src/kvist/emit.odin", snippet = "emit_core_count_by_helper :: proc"},
    {import_path = "kvist:arr", member = "sum-by", relative = "src/kvist/emit.odin", snippet = "emit_core_sum_by_helper :: proc"},
    {import_path = "kvist:arr", member = "frequencies", relative = "src/kvist/emit.odin", snippet = "emit_core_frequencies_helper :: proc"},
    {import_path = "kvist:arr", member = "distinct", relative = "src/kvist/emit.odin", snippet = "emit_core_distinct_helper :: proc"},
    {import_path = "kvist:arr", member = "distinct-by", relative = "src/kvist/emit.odin", snippet = "emit_core_distinct_by_helper :: proc"},
    {import_path = "kvist:arr", member = "take-nth", relative = "packages/arr/package.kvist", snippet = "(proc take-nth [n: int, xs: []$T] -> [dynamic]T #force_inline"},
    {import_path = "kvist:arr", member = "repeat", relative = "packages/arr/package.kvist", snippet = "(proc repeat [n: int, value: $T] -> [dynamic]T #force_inline"},
    {import_path = "kvist:arr", member = "repeatedly", relative = "packages/arr/package.kvist", snippet = "(proc repeatedly [n: int, f: (proc [] -> $T)] -> [dynamic]T #force_inline"},
    {import_path = "kvist:arr", member = "iterate", relative = "packages/arr/package.kvist", snippet = "(proc iterate [n: int, f: (proc [x: $T] -> T), init: T] -> [dynamic]T #force_inline"},
    {import_path = "kvist:arr", member = "cycle", relative = "packages/arr/package.kvist", snippet = "(proc cycle [n: int, xs: []$T] -> [dynamic]T #force_inline"},
    {import_path = "kvist:arr", member = "find", relative = "packages/arr/package.kvist", snippet = "(defmacro find [pred xs]"},
    {import_path = "kvist:arr", member = "some?", relative = "packages/arr/package.kvist", snippet = "(defmacro some? [pred xs]"},
    {import_path = "kvist:arr", member = "every?", relative = "packages/arr/package.kvist", snippet = "(defmacro every? [pred xs]"},
    {import_path = "kvist:arr", member = "sort", relative = "src/kvist/emit.odin", snippet = "emit_core_sort_helper :: proc"},
    {import_path = "kvist:arr", member = "sort!", relative = "src/kvist/emit.odin", snippet = "emit_core_sort_in_place_helper :: proc"},
    {import_path = "kvist:arr", member = "sort-by", relative = "src/kvist/emit.odin", snippet = "emit_core_sort_by_helper :: proc"},
    {import_path = "kvist:arr", member = "sort-by!", relative = "src/kvist/emit.odin", snippet = "emit_core_sort_by_in_place_helper :: proc"},
    {import_path = "kvist:str", member = "count", relative = "packages/str/package.kvist", snippet = "(proc count [s: string] -> int #force_inline"},
    {import_path = "kvist:str", member = "get", relative = "packages/str/package.kvist", snippet = "(defmacro get [s index]"},
    {import_path = "kvist:str", member = "slice", relative = "packages/str/package.kvist", snippet = "(defmacro slice [s start & rest]"},
    {import_path = "kvist:str", member = "contains?", relative = "packages/str/package.kvist", snippet = "(proc contains? [s: string, needle: string] -> bool #force_inline"},
    {import_path = "kvist:str", member = "split", relative = "packages/str/package.kvist", snippet = "(defmacro split [s separator]"},
    {import_path = "kvist:str", member = "join", relative = "packages/str/package.kvist", snippet = "(defmacro join [parts separator]"},
    {import_path = "kvist:str", member = "trim", relative = "packages/str/package.kvist", snippet = "(proc trim [s: string] -> string #force_inline"},
    {import_path = "kvist:str", member = "trim-prefix", relative = "packages/str/package.kvist", snippet = "(proc trim-prefix [s: string, prefix: string] -> string #force_inline"},
    {import_path = "kvist:str", member = "trim-suffix", relative = "packages/str/package.kvist", snippet = "(proc trim-suffix [s: string, suffix: string] -> string #force_inline"},
    {import_path = "kvist:str", member = "starts-with?", relative = "packages/str/package.kvist", snippet = "(proc starts-with? [s: string, prefix: string] -> bool #force_inline"},
    {import_path = "kvist:str", member = "ends-with?", relative = "packages/str/package.kvist", snippet = "(proc ends-with? [s: string, suffix: string] -> bool #force_inline"},
    {import_path = "kvist:str", member = "index-of", relative = "packages/str/package.kvist", snippet = "(proc index-of [s: string, needle: string] -> int #force_inline"},
    {import_path = "kvist:str", member = "last-index-of", relative = "packages/str/package.kvist", snippet = "(proc last-index-of [s: string, needle: string] -> int #force_inline"},
    {import_path = "kvist:str", member = "replace", relative = "packages/str/package.kvist", snippet = "(defmacro replace [s old new & rest]"},
    {import_path = "kvist:str", member = "lower", relative = "packages/str/package.kvist", snippet = "(proc lower [s: string] -> string #force_inline"},
    {import_path = "kvist:str", member = "upper", relative = "packages/str/package.kvist", snippet = "(proc upper [s: string] -> string #force_inline"},
    {import_path = "kvist:map", member = "empty", relative = "packages/map/package.kvist", snippet = "(defmacro empty [key-type value-type & rest]"},
    {import_path = "kvist:map", member = "of", relative = "packages/map/package.kvist", snippet = "(defmacro of [key-type value-type entries]"},
    {import_path = "kvist:map", member = "get", relative = "packages/map/package.kvist", snippet = "(defmacro get [m key & rest]"},
    {import_path = "kvist:map", member = "contains?", relative = "packages/map/package.kvist", snippet = "(proc contains? [m: map[$K]$V, key: K] -> bool #force_inline"},
    {import_path = "kvist:map", member = "keys", relative = "packages/map/package.kvist", snippet = "(proc keys [m: map[$K]$V] -> [dynamic]K #force_inline"},
    {import_path = "kvist:map", member = "vals", relative = "packages/map/package.kvist", snippet = "(proc vals [m: map[$K]$V] -> [dynamic]V #force_inline"},
    {import_path = "kvist:map", member = "zip", relative = "packages/map/package.kvist", snippet = "(proc zip [ks: []$K, vs: []$V] -> map[K]V #force_inline"},
    {import_path = "kvist:map", member = "merge", relative = "packages/map/package.kvist", snippet = "(proc merge [lhs: map[$K]$V, rhs: map[$K]$V] -> map[K]V #force_inline"},
    {import_path = "kvist:map", member = "merge!", relative = "packages/map/package.kvist", snippet = "(defmacro merge! [target source]"},
    {import_path = "kvist:set", member = "empty", relative = "packages/set/package.kvist", snippet = "(defmacro empty [elem-type & rest]"},
    {import_path = "kvist:set", member = "of", relative = "packages/set/package.kvist", snippet = "(defmacro of [elem-type values]"},
    {import_path = "kvist:set", member = "contains?", relative = "packages/set/package.kvist", snippet = "(proc contains? [s: set[$T], value: T] -> bool #force_inline"},
    {import_path = "kvist:set", member = "add!", relative = "packages/set/package.kvist", snippet = "(defmacro add! [s value]"},
    {import_path = "kvist:set", member = "remove!", relative = "packages/set/package.kvist", snippet = "(defmacro remove! [s value]"},
    {import_path = "kvist:set", member = "union", relative = "packages/set/package.kvist", snippet = "(proc union [lhs: set[$T], rhs: set[$T]] -> set[T] #force_inline"},
    {import_path = "kvist:set", member = "intersection", relative = "packages/set/package.kvist", snippet = "(proc intersection [lhs: set[$T], rhs: set[$T]] -> set[T] #force_inline"},
    {import_path = "kvist:set", member = "difference", relative = "packages/set/package.kvist", snippet = "(proc difference [lhs: set[$T], rhs: set[$T]] -> set[T] #force_inline"},
    {import_path = "kvist:set", member = "union!", relative = "packages/set/package.kvist", snippet = "(defmacro union! [target source]"},
    {import_path = "kvist:set", member = "intersection!", relative = "packages/set/package.kvist", snippet = "(defmacro intersection! [target source]"},
    {import_path = "kvist:set", member = "difference!", relative = "packages/set/package.kvist", snippet = "(defmacro difference! [target source]"},
    {import_path = "kvist:set", member = "subset?", relative = "packages/set/package.kvist", snippet = "(proc subset? [lhs: set[$T], rhs: set[$T]] -> bool #force_inline"},
    {import_path = "kvist:set", member = "superset?", relative = "packages/set/package.kvist", snippet = "(proc superset? [lhs: set[$T], rhs: set[$T]] -> bool #force_inline"},
    {import_path = "kvist:set", member = "disjoint?", relative = "packages/set/package.kvist", snippet = "(proc disjoint? [lhs: set[$T], rhs: set[$T]] -> bool #force_inline"},
    {import_path = "kvist:set", member = "add", relative = "packages/set/package.kvist", snippet = "(proc add [s: set[$T], value: T] -> set[T] #force_inline"},
    {import_path = "kvist:set", member = "remove", relative = "packages/set/package.kvist", snippet = "(proc remove [s: set[$T], value: T] -> set[T] #force_inline"},
    {import_path = "kvist:struct", member = "fields", relative = "src/kvist/emit.odin", snippet = "if head.text == \"struct/fields\" || head.text == \"struct/types\""},
    {import_path = "kvist:struct", member = "types", relative = "src/kvist/emit.odin", snippet = "if head.text == \"struct/fields\" || head.text == \"struct/types\""},
    {import_path = "kvist:io", member = "read", relative = "packages/io/io.kvist", snippet = "(defn read"},
    {import_path = "kvist:io", member = "write", relative = "packages/io/io.kvist", snippet = "(defn write"},
    {import_path = "kvist:json", member = "write", relative = "packages/json/json.kvist", snippet = "(defn write"},
    {import_path = "kvist:json", member = "read-as", relative = "packages/json/json.kvist", snippet = "(defn read-as"},
    {import_path = "kvist:http", member = "with-router", relative = "packages/http/http.kvist", snippet = "(defmacro with-router"},
    {import_path = "kvist:http", member = "get", relative = "packages/http/http.kvist", snippet = "(defmacro get"},
    {import_path = "kvist:http", member = "post", relative = "packages/http/http.kvist", snippet = "(defmacro post"},
    {import_path = "kvist:http", member = "put", relative = "packages/http/http.kvist", snippet = "(defmacro put"},
    {import_path = "kvist:http", member = "delete", relative = "packages/http/http.kvist", snippet = "(defmacro delete"},
    {import_path = "kvist:http", member = "all", relative = "packages/http/http.kvist", snippet = "(defmacro all"},
    {import_path = "kvist:http", member = "listen", relative = "packages/http/http.kvist", snippet = "(defmacro listen"},
    {import_path = "kvist:http", member = "respond", relative = "packages/http/http.kvist", snippet = "(defmacro respond"},
    {import_path = "kvist:http", member = "respond-plain", relative = "packages/http/http.kvist", snippet = "(defmacro respond-plain"},
    {import_path = "kvist:http", member = "respond-html", relative = "packages/http/http.kvist", snippet = "(defmacro respond-html"},
    {import_path = "kvist:http", member = "respond-json", relative = "packages/http/http.kvist", snippet = "(defmacro respond-json"},
    {import_path = "kvist:http", member = "respond-file", relative = "packages/http/http.kvist", snippet = "(defmacro respond-file"},
    {import_path = "kvist:http", member = "respond-dir", relative = "packages/http/http.kvist", snippet = "(defmacro respond-dir"},
}

LANGUAGE_SOURCE_ENTRIES :: []Language_Source_Entry{
    {name = "package", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"package\":"},
    {name = "import", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"import\":"},
    {name = "defconst", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"defconst\", \"defconst-\":\""},
    {name = "defvar", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"defvar\", \"defvar-\":\""},
    {name = "defstruct", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"defstruct\", \"defstruct-\":\""},
    {name = "defenum", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"defenum\", \"defenum-\":\""},
    {name = "defunion", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"defunion\", \"defunion-\":\""},
    {name = "defn", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"defn\", \"defn-\":\""},
    {name = "odin", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"odin\":"},
    {name = "let", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"let\":"},
    {name = "do", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"do\":"},
    {name = "if", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_if_like :: proc"},
    {name = "when", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"when\":"},
    {name = "cond", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_cond_stmt :: proc"},
    {name = "switch", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_switch_stmt :: proc"},
    {name = "set!", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"set!\":"},
    {name = "return", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"return\":"},
    {name = "defer", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"defer\":"},
    {name = "for", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"for\":"},
    {name = "each", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"each\":"},
    {name = "update", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"update\":"},
    {name = "update!", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"update!\":"},
    {name = "comment", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "case \"comment\":"},
    {name = "new", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"new\""},
    {name = "make", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"make\""},
    {name = "get", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"get\""},
    {name = "nil?", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"nil?\""},
    {name = "type", kind = "kvist form", relative = "src/kvist/parse.odin", snippet = "if is_symbol(form.items[0], \"type\")"},
    {name = "in", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if op == \"in\" || op == \"not-in\""},
    {name = "not-in", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if op == \"in\" || op == \"not-in\""},
    {name = "break", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"break\":"},
    {name = "continue", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "case \"continue\":"},
    {name = "with-allocator", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_with_allocator_stmt :: proc"},
    {name = "with-temp-allocator", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_with_temp_allocator_stmt :: proc"},
    {name = "tap>", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "if head.text == \"tap>\""},
    {name = "->", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_thread_expr :: proc"},
    {name = "->>", kind = "kvist form", relative = "src/kvist/emit.odin", snippet = "emit_thread_expr :: proc"},
    {name = "slice", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "if head.text == \"slice\" || head.text == \"arr/slice\""},
    {name = "empty?", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "head.text == \"empty?\" || head.text == \"count\""},
    {name = "count", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "head.text == \"empty?\" || head.text == \"count\""},
    {name = "contains?", kind = "kvist helper", relative = "src/kvist/emit.odin", snippet = "if op == \"in?\" || op == \"contains?\""},
}

import_path_text :: proc(form: CST_Form) -> string {
    if form.kind != .String {
        return ""
    }
    return unquote_string(form.text)
}

builtin_symbols_write_entry :: proc(builder: ^strings.Builder, kind, name, signature, doc: string) {
    doc_lines := symbols_doc_lines_from_string(doc)
    defer delete(doc_lines)
    symbols_write_record_doc(builder, kind, name, "", Span{start = 0, end = 0, source = .File}, "", signature, doc_lines[:])
}

builtin_symbols_append :: proc(builder: ^strings.Builder) {
    builtin_symbols_write_entry(builder, "kvist macro", "when-let", "(when-let [value bool expr] body...)", "Bind a value and explicit boolean result from a multi-return expression. Run the body only when the boolean is true. Expands to a destructuring let plus when.")
    builtin_symbols_write_entry(builder, "kvist macro", "if-let", "(if-let [value bool expr] then else)", "Bind a value and explicit boolean result from a multi-return expression. Evaluate the then branch when the boolean is true, otherwise the else branch. Expands to a destructuring let plus if.")
    builtin_symbols_write_entry(builder, "kvist macro", "when-ok", "(when-ok [value err expr] body...)", "Bind a value and Odin error result from a multi-return expression. Run the body only when the error equals Odin's zero value {}. Expands to a destructuring let plus when.")
    builtin_symbols_write_entry(builder, "kvist macro", "if-ok", "(if-ok [value err expr] then else)", "Bind a value and Odin error result from a multi-return expression. Evaluate the then branch when the error equals Odin's zero value {}, otherwise the else branch. Expands to a destructuring let plus if.")
    builtin_symbols_write_entry(builder, "kvist core", "println", "(println value...)", "Print one or more values. Kvist lowers this to fmt output and auto-imports core:fmt when needed.")
    builtin_symbols_write_entry(builder, "kvist core", "doc", "(doc 'symbol)", "Print the stored docstring for a declaration name.")
    builtin_symbols_write_entry(builder, "kvist form", "or-else", "(or-else expr fallback)", "Evaluate an Odin optional-ok expression and return its value when ok is true, otherwise return the fallback value.")
    builtin_symbols_write_entry(builder, "kvist form", "update!", "(update! target key-or-field value-or-updater ...)", "Mutate a struct field, array/slice slot, or map key in place. Supports replacement and updater forms such as inc or +.")
    builtin_symbols_write_entry(builder, "kvist form", "update", "(update target key-or-field value-or-updater ...)", "Return an updated copy. Currently supported for struct fields.")
    builtin_symbols_write_entry(builder, "kvist form", "type", "(type Head Arg...)", "Instantiate an Odin polymorphic type constructor. For example, (type chan.Chan int) lowers to chan.Chan(int) in both type and value positions.")
}

builtin_symbols_source :: proc() -> string {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n")
    builtin_symbols_append(&builder)
    return strings.clone(strings.to_string(builder), result_allocator)
}

language_symbols_source :: proc() -> string {
    result_allocator := context.allocator
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n")
    for entry in LANGUAGE_SOURCE_ENTRIES {
        symbols_write_record_doc(&builder, entry.kind, entry.name, entry.relative, Span{start = 0, end = 0, source = .File}, "", "", nil)
    }
    return strings.clone(strings.to_string(builder), result_allocator)
}

import_entry_from_form :: proc(form: CST_Form) -> (Imported_Symbol_Entry, bool) {
    if form.kind != .List || len(form.items) == 0 || !is_symbol(form.items[0], "import") {
        return {}, false
    }
    if len(form.items) == 2 && form.items[1].kind == .String {
        path := import_path_text(form.items[1])
        alias := import_default_alias(path)
        if alias == "" {
            return {}, false
        }
        return Imported_Symbol_Entry{alias = alias, path = path}, true
    }
    if len(form.items) == 3 && form.items[1].kind == .Symbol && form.items[2].kind == .String {
        path := import_path_text(form.items[2])
        return Imported_Symbol_Entry{alias = map_name(form.items[1].text), path = path}, true
    }
    return {}, false
}

odin_root_path :: proc() -> (string, bool) {
    state, stdout, stderr, err := os.process_exec(
        os.Process_Desc{command = {"odin", "root"}},
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    if err != nil || !state.exited || state.exit_code != 0 {
        return "", false
    }
    return strings.trim_space(string(stdout)), true
}

odin_import_dir :: proc(root, import_path: string) -> (string, bool) {
    switch {
    case strings.has_prefix(import_path, "core:"):
        path, err := os.join_path({root, "core", import_path[5:]}, context.allocator)
        if err != nil {
            return "", false
        }
        return path, true
    case strings.has_prefix(import_path, "vendor:"):
        path, err := os.join_path({root, "vendor", import_path[7:]}, context.allocator)
        if err != nil {
            return "", false
        }
        return path, true
    case:
        return "", false
    }
}

trim_line_ws :: proc(text: string) -> string {
    return strings.trim_space(text)
}

line_start_offset :: proc(source: string, line_start: int) -> int {
    if line_start <= 0 {
        return 0
    }
    line := 1
    for i := 0; i < len(source); i += 1 {
        if line == line_start {
            return i
        }
        if source[i] == '\n' {
            line += 1
        }
    }
    return len(source)
}

odin_line_range :: proc(source: string, line_start: int) -> (start, end: int) {
    start = line_start_offset(source, line_start)
    end = start
    for end < len(source) && source[end] != '\n' {
        end += 1
    }
    return
}

odin_signature_at_line :: proc(source: string, line_start: int) -> string {
    start, end := odin_line_range(source, line_start)
    if start >= len(source) {
        return ""
    }
    line := trim_line_ws(source[start:end])
    if strings.contains(line, ":: proc {") {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, line)
        current := line_start + 1
        for current <= 1000000 {
            next_start, next_end := odin_line_range(source, current)
            if next_start >= len(source) {
                break
            }
            next_line := trim_line_ws(source[next_start:next_end])
            strings.write_string(&builder, " ")
            strings.write_string(&builder, next_line)
            if next_line == "}" {
                break
            }
            current += 1
        }
        return strings.join(strings.fields(strings.to_string(builder))[:], " ", context.allocator)
    }
    compact := trim_line_ws(line)
    brace_idx := strings.index(compact, "{")
    if brace_idx >= 0 {
        compact = trim_line_ws(compact[:brace_idx])
    }
    return strings.join(strings.fields(compact)[:], " ", context.allocator)
}

odin_clean_doc_comment_line :: proc(line: string) -> string {
    text := strings.trim_left(line, " \t")
    if strings.has_prefix(text, "///") {
        return strings.trim_left(text[3:], " \t")
    }
    if strings.has_prefix(text, "//") {
        return strings.trim_left(text[2:], " \t")
    }
    return text
}

odin_clean_block_doc_line :: proc(line: string) -> string {
    text := strings.trim_space(line)
    if strings.has_prefix(text, "*") {
        return strings.trim_left(text[1:], " \t")
    }
    return text
}

odin_clean_block_doc_comment :: proc(text: string) -> string {
    value := text
    if strings.has_prefix(value, "/*") {
        value = value[2:]
    }
    if strings.has_suffix(value, "*/") {
        value = value[:len(value)-2]
    }
    lines := strings.split_lines(value, context.allocator)
    defer delete(lines)
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    seen_content := false
    pending_blank := false
    for line in lines {
        clean := odin_clean_block_doc_line(line)
        if clean == "" {
            if seen_content {
                pending_blank = true
            }
            continue
        }
        if pending_blank {
            strings.write_string(&builder, "\n")
        }
        if seen_content {
            strings.write_string(&builder, "\n")
        }
        strings.write_string(&builder, clean)
        seen_content = true
        pending_blank = false
    }
    return strings.to_string(builder)
}

odin_preceding_doc :: proc(source: string, line_start: int) -> string {
    lines := strings.split_lines(source, context.allocator)
    defer delete(lines)
    if line_start <= 1 || line_start > len(lines)+1 {
        return ""
    }
    docs: [dynamic]string
    defer delete(docs)
    idx := line_start - 2
doc_scan:
    for idx >= 0 {
        line := lines[idx]
        trimmed := strings.trim_space(line)
        switch {
        case strings.has_prefix(trimmed, "//"):
            append(&docs, odin_clean_doc_comment_line(line))
        case strings.has_suffix(trimmed, "*/"):
            builder := strings.builder_make()
            defer strings.builder_destroy(&builder)
            strings.write_string(&builder, line)
            idx -= 1
            for idx >= 0 {
                strings.write_string(&builder, "\n")
                strings.write_string(&builder, lines[idx])
                if strings.contains(lines[idx], "/*") {
                    break
                }
                idx -= 1
            }
            append(&docs, odin_clean_block_doc_comment(strings.to_string(builder)))
        case trimmed == "":
            break doc_scan
        case:
            break doc_scan
        }
        idx -= 1
    }
    if len(docs) == 0 {
        return ""
    }
    for i, j := 0, len(docs)-1; i < j; i, j = i+1, j-1 {
        docs[i], docs[j] = docs[j], docs[i]
    }
    return strings.join(docs[:], "\n", context.allocator)
}

odin_trim_doc :: proc(text: string) -> string {
    if text == "" {
        return ""
    }
    lines := strings.split_lines(text, context.allocator)
    defer delete(lines)
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    line_count := 0
    truncated := false
    for line in lines {
        clean := strings.trim_space(line)
        if clean == "" {
            break
        }
        if line_count >= 4 {
            truncated = true
            break
        }
        if line_count > 0 {
            strings.write_string(&builder, "\n")
        }
        strings.write_string(&builder, clean)
        line_count += 1
        if len(strings.to_string(builder)) >= 320 {
            truncated = true
            break
        }
    }
    out := strings.to_string(builder)
    if truncated && !strings.has_suffix(out, "...") {
        out = fmt.tprintf("%s...", out)
    }
    return out
}

odin_decl_rank :: proc(file, name: string) -> int {
    rank := 0
    if strings.contains(file, "/old/") {
        rank += 100
    }
    if strings.has_suffix(file, "_js.odin") {
        rank += 10
    }
    if strings.contains(file, "/example.odin") {
        rank += 200
    }
    if name == "main" {
        rank += 500
    }
    if strings.contains(name, "_") && len(name) > 0 && name[0] >= 'a' && name[0] <= 'z' {
        rank += 120
    }
    if strings.has_prefix(name, "fmt_") || strings.has_prefix(name, "int_from_") {
        rank += 120
    }
    return rank
}

odin_symbol_visible_to_tooling :: proc(file, name: string) -> bool {
    if name == "" || name == "main" {
        return false
    }
    if strings.contains(file, "/example.odin") || strings.contains(file, "/old/") {
        return false
    }
    if strings.has_suffix(file, "_js.odin") || strings.has_suffix(file, "_wasm.odin") {
        return false
    }
    if len(name) > 0 && name[0] == '_' {
        return false
    }
    if strings.contains(name, "_") && len(name) > 0 && name[0] >= 'a' && name[0] <= 'z' {
        return false
    }
    return true
}

imported_symbols_scan_odin_dir :: proc(builder: ^strings.Builder, alias, import_path, dir: string) {
    if !os.exists(dir) {
        return
    }
    entries, err := os.read_directory_by_path(dir, -1, context.allocator)
    if err != nil {
        return
    }
    defer os.file_info_slice_delete(entries, context.allocator)

    best := make(map[string]string)
    defer delete(best)
    best_rank := make(map[string]int)
    defer delete(best_rank)

    for entry in entries {
        if entry.type != .Regular || !strings.has_suffix(entry.name, ".odin") {
            continue
        }
        path, join_err := os.join_path({dir, entry.name}, context.allocator)
        if join_err != nil {
            continue
        }
        defer delete(path)
        data, read_err := os.read_entire_file_from_path(path, context.allocator)
        if read_err != nil {
            continue
        }
        source := string(data)
        defer delete(data)
        lines := strings.split_lines(source, context.allocator)
        defer delete(lines)
        for line, idx in lines {
            trimmed_left := strings.trim_left(line, " \t")
            name_end := strings.index(trimmed_left, "::")
            if name_end <= 0 {
                continue
            }
            name := strings.trim_space(trimmed_left[:name_end])
            if name == "" || name[0] == '_' || strings.contains(name, " ") || strings.contains(name, "\t") {
                continue
            }
            if !odin_symbol_visible_to_tooling(path, name) {
                continue
            }
            signature := odin_signature_at_line(source, idx+1)
            doc := odin_trim_doc(odin_preceding_doc(source, idx+1))
            rank := odin_decl_rank(path, name)
            key_slash := fmt.tprintf("%s/%s", alias, name)
            existing_rank, found_rank := best_rank[key_slash]
            if found_rank && existing_rank <= rank {
                delete(signature)
                delete(doc)
                continue
            }
            if prev, found := best[key_slash]; found {
                delete(prev)
            }
            if prev, found := best[fmt.tprintf("%s.%s", alias, name)]; found {
                delete(prev)
            }
            record_slash := strings.clone(fmt.tprintf("odin\t%s/%s\t%d\t1\t%s\t%s\t%s\t%s\n", alias, name, idx+1, import_path, signature, symbols_escape_doc_text(doc), path))
            record_dot := strings.clone(fmt.tprintf("odin\t%s.%s\t%d\t1\t%s\t%s\t%s\t%s\n", alias, name, idx+1, import_path, signature, symbols_escape_doc_text(doc), path))
            best[key_slash] = record_slash
            best[fmt.tprintf("%s.%s", alias, name)] = record_dot
            best_rank[key_slash] = rank
            best_rank[fmt.tprintf("%s.%s", alias, name)] = rank
        }
    }

    records: [dynamic]Imported_Symbol_Record
    defer delete(records)
    for name, record in best {
        rank := best_rank[name]
        append(&records, Imported_Symbol_Record{name = name, record = record, rank = rank})
    }
    sort.sort(sort.Interface{
        collection = rawptr(&records),
        len = proc(it: sort.Interface) -> int {
            items := (^([dynamic]Imported_Symbol_Record))(it.collection)
            return len(items^)
        },
        less = proc(it: sort.Interface, i, j: int) -> bool {
            items := (^([dynamic]Imported_Symbol_Record))(it.collection)
            if items[i].rank != items[j].rank {
                return items[i].rank < items[j].rank
            }
            return items[i].name < items[j].name
        },
        swap = proc(it: sort.Interface, i, j: int) {
            items := (^([dynamic]Imported_Symbol_Record))(it.collection)
            items[i], items[j] = items[j], items[i]
        },
    })
    for item in records {
        strings.write_string(builder, item.record)
    }
}

symbols_escape_doc_text :: proc(text: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    lines := symbols_doc_lines_from_string(text)
    defer delete(lines)
    symbols_write_escaped_doc(&builder, lines[:])
    return strings.to_string(builder)
}

symbols_record_name :: proc(line: string) -> string {
    first_tab := strings.index(line, "\t")
    if first_tab < 0 {
        return ""
    }
    rest := line[first_tab+1:]
    second_tab := strings.index(rest, "\t")
    if second_tab < 0 {
        return ""
    }
    return rest[:second_tab]
}

symbols_record_key :: proc(line: string) -> string {
    fields, ok := symbols_split_record_fields(line)
    if !ok || len(fields) < 2 {
        return ""
    }
    return fmt.tprintf("%s\t%s", fields[0], fields[1])
}

symbols_record_detail :: proc(line: string) -> string {
    first_tab := strings.index(line, "\t")
    if first_tab < 0 {
        return ""
    }
    rest := line[first_tab+1:]
    for _ in 0..<3 {
        tab := strings.index(rest, "\t")
        if tab < 0 {
            return ""
        }
        rest = rest[tab+1:]
    }
    tab := strings.index(rest, "\t")
    if tab < 0 {
        return rest
    }
    return rest[:tab]
}

symbols_append_unique_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, output: string) {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile" {
            continue
        }
        key := symbols_record_key(line)
        if key == "" {
            continue
        }
        if seen[key] {
            continue
        }
        seen[key] = true
        strings.write_string(builder, line)
        strings.write_byte(builder, '\n')
    }
}

symbols_split_record_fields :: proc(line: string) -> (fields: [dynamic]string, ok: bool) {
    rest := line
    for {
        tab := strings.index(rest, "\t")
        if tab < 0 {
            append(&fields, rest)
            break
        }
        append(&fields, rest[:tab])
        rest = rest[tab+1:]
    }
    return fields, len(fields) >= 7
}

symbols_top_level_kind_exported :: proc(kind: string) -> bool {
    switch kind {
    case "const", "var", "struct", "enum", "union", "proc", "macro":
        return true
    case:
        return false
    }
}

symbols_append_source_package_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, import_path, alias, package_file, output: string) {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile" {
            continue
        }
        fields, ok_fields := symbols_split_record_fields(line)
        if !ok_fields {
            delete(fields)
            continue
        }
        kind := fields[0]
        name := fields[1]
        if !symbols_top_level_kind_exported(kind) {
            delete(fields)
            continue
        }
        if symbols_record_detail(line) == "private" {
            delete(fields)
            continue
        }
        line_text := fields[2]
        column_text := fields[3]
        signature := fields[5]
        doc := fields[6]
        slash_name := fmt.tprintf("%s/%s", alias, name)
        if !seen[slash_name] {
            seen[slash_name] = true
            fmt.sbprintf(builder, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", kind, slash_name, line_text, column_text, import_path, signature, doc, package_file)
        }
        dot_name := fmt.tprintf("%s.%s", alias, name)
        if !seen[dot_name] {
            seen[dot_name] = true
            fmt.sbprintf(builder, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", kind, dot_name, line_text, column_text, import_path, signature, doc, package_file)
        }
        delete(fields)
    }
}

source_package_anchor_file :: proc(files: []Package_File) -> string {
    for file in files {
        _, name := os.split_path(file.path)
        if name == "main.kvist" || name == "package.kvist" {
            return file.path
        }
    }
    if len(files) > 0 {
        return files[0].path
    }
    return ""
}

symbols_append_source_package_import_record :: proc(builder: ^strings.Builder, seen: ^map[string]bool, alias, import_path, file_path: string) {
    if alias == "" || file_path == "" {
        return
    }
    key := fmt.tprintf("source import\t%s", alias)
    if seen[key] {
        delete(key)
        return
    }
    seen[key] = true
    temp := strings.builder_make()
    defer strings.builder_destroy(&temp)
    doc_lines := symbols_doc_lines_from_string(fmt.tprintf("Source package import %s.", import_path))
    defer delete(doc_lines)
    symbols_write_record_doc_file(&temp, "source import", alias, 1, 1, import_path, fmt.tprintf("(import %s \"%s\")", alias, import_path), doc_lines[:], file_path)
    strings.write_string(builder, strings.to_string(temp))
    strings.write_byte(builder, '\n')
    delete(key)
}

symbols_append_local_package_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, file_path, output: string) {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile" {
            continue
        }
        fields, ok_fields := symbols_split_record_fields(line)
        if !ok_fields {
            delete(fields)
            continue
        }
        kind := fields[0]
        name := fields[1]
        line_text := fields[2]
        column_text := fields[3]
        detail := fields[4]
        signature := fields[5]
        doc := fields[6]
        temp := strings.builder_make()
        defer strings.builder_destroy(&temp)
        fmt.sbprintf(&temp, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", kind, name, line_text, column_text, detail, signature, doc, file_path)
        symbols_append_unique_records(builder, seen, strings.to_string(temp))
        delete(fields)
    }
}

editor_root_package_files :: proc(path, source: string) -> ([]Package_File, bool) {
    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        _ = err_forms
        return nil, false
    }
    package_name := ""
    for top in forms {
        if decl_head_name(top.form) == "package" && len(top.form.items) == 2 && top.form.items[1].kind == .Symbol {
            package_name = top.form.items[1].text
            break
        }
    }
    if package_name == "" {
        return nil, false
    }

    dir, file_name := os.split_path(path)
    if dir == "" {
        return nil, false
    }

    entries, dir_err := os.read_directory_by_path(dir, -1, context.allocator)
    if dir_err != nil {
        return nil, false
    }
    defer delete(entries)

    has_anchor := false
    matched: [dynamic]Package_File
    for entry in entries {
        if entry.type != .Regular || !strings.has_suffix(entry.name, ".kvist") {
            continue
        }
        file_path, join_err := os.join_path({dir, entry.name}, context.allocator)
        if join_err != nil {
            return nil, false
        }
        if entry.name == file_name {
            append(&matched, Package_File{path = file_path, source = source, package_name = package_name, forms = forms})
            continue
        }
        data, read_err := os.read_entire_file_from_path(file_path, context.allocator)
        if read_err != nil {
            continue
        }
        file_source := string(data)
        file_forms, _, ok_file_forms := read_top_forms(file_source)
        if !ok_file_forms {
            continue
        }
        file_package_name := ""
        for top in file_forms {
            if decl_head_name(top.form) == "package" && len(top.form.items) == 2 && top.form.items[1].kind == .Symbol {
                file_package_name = top.form.items[1].text
                break
            }
        }
        if file_package_name != package_name {
            continue
        }
        if entry.name == "main.kvist" || entry.name == "package.kvist" {
            has_anchor = true
        }
        append(&matched, Package_File{path = file_path, source = file_source, package_name = file_package_name, forms = file_forms})
    }

    if len(matched) == 0 {
        return nil, false
    }
    if !has_anchor {
        files: [dynamic]Package_File
        append(&files, Package_File{path = path, source = source, package_name = package_name, forms = forms})
        return files[:], true
    }
    return matched[:], true
}

source_package_symbols_source :: proc(importer_path, import_path: string) -> (package_file, output: string, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    resolved, err_resolve, ok_resolve := resolve_source_import_path(importer_path, import_path)
    if !ok_resolve {
        return "", "", clone_compile_error(err_resolve, result_allocator), false
    }
    defer delete(resolved)
    files, err_files, ok_files := read_package_files(resolved)
    if !ok_files {
        return "", "", clone_compile_error(err_files, result_allocator), false
    }
    _, err_package, ok_package := validate_package_files(resolved, files[:])
    if !ok_package {
        return "", "", clone_compile_error(err_package, result_allocator), false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n")
    seen := make(map[string]bool)
    defer delete(seen)
    for file in files {
        context.allocator = result_allocator
        package_output, package_err, ok_package_output := symbols_source(file.source)
        context.allocator = context.temp_allocator
        if !ok_package_output {
            return "", "", clone_compile_error(package_err, result_allocator), false
        }
        symbols_append_source_package_records(&builder, &seen, import_path, import_default_alias(import_path), file.path, package_output)
        delete(package_output)
    }
    resolved_copy, _ := strings.clone(resolved, result_allocator)
    output_copy, _ := strings.clone(strings.to_string(builder), result_allocator)
    return resolved_copy, output_copy, Compile_Error{}, true
}

repo_root_for_path :: proc(path: string) -> (string, bool) {
    current := path
    owned_current := ""
    if current != "" && !os.is_absolute_path(current) {
        absolute, abs_err := os.get_absolute_path(current, context.allocator)
        if abs_err == nil {
            current = absolute
            owned_current = absolute
        }
    }
    if !os.is_dir(current) {
        dir, _ := os.split_path(current)
        current = dir
    }
    for current != "" {
        marker, err := os.join_path({current, "cmd", "kvist", "main.odin"}, context.allocator)
        if err == nil {
            if os.exists(marker) {
                delete(marker)
                root := strings.clone(current)
                if owned_current != "" {
                    delete(owned_current)
                }
                return root, true
            }
            delete(marker)
        }
        parent, _ := os.split_path(strings.trim_right(current, "/"))
        if parent == "" || parent == current {
            break
        }
        current = parent
    }
    if owned_current != "" {
        delete(owned_current)
    }
    return "", false
}

file_location_for_snippet :: proc(root, relative, snippet: string) -> (file: string, line, column: int, ok: bool) {
    path, join_err := os.join_path({root, relative}, context.allocator)
    if join_err != nil {
        return "", 0, 0, false
    }
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        delete(path)
        return "", 0, 0, false
    }
    source := string(data)
    idx := strings.index(source, snippet)
    if idx < 0 {
        delete(data)
        delete(path)
        return "", 0, 0, false
    }
    line, column, _, _ = source_position(source, idx)
    delete(data)
    return path, line, column, true
}

symbols_write_record_doc_file :: proc(builder: ^strings.Builder, kind, name: string, line, column: int, detail, signature: string, doc_lines: []string, file: string) {
    fmt.sbprintf(builder, "%s\t%s\t%d\t%d\t%s\t%s\t", kind, name, line, column, detail, signature)
    symbols_write_escaped_doc(builder, doc_lines)
    fmt.sbprintf(builder, "\t%s\n", file)
}

editor_builtin_symbols_append :: proc(builder: ^strings.Builder, seen: ^map[string]bool, repo_root: string) {
    for entry in BUILTIN_SOURCE_ENTRIES {
        temp := strings.builder_make()
        defer strings.builder_destroy(&temp)
        file, line, column, ok := file_location_for_snippet(repo_root, entry.relative, entry.snippet)
        if !ok {
            continue
        }
        switch entry.name {
        case "when-let":
            symbols_write_record_doc_file(&temp, "kvist macro", entry.name, line, column, "", "(when-let [value bool expr] body...)", symbols_doc_lines_from_string("Bind a value and explicit boolean result from a multi-return expression. Run the body only when the boolean is true. Expands to a destructuring let plus when.")[:], file)
        case "if-let":
            symbols_write_record_doc_file(&temp, "kvist macro", entry.name, line, column, "", "(if-let [value bool expr] then else)", symbols_doc_lines_from_string("Bind a value and explicit boolean result from a multi-return expression. Evaluate the then branch when the boolean is true, otherwise the else branch. Expands to a destructuring let plus if.")[:], file)
        case "when-ok":
            symbols_write_record_doc_file(&temp, "kvist macro", entry.name, line, column, "", "(when-ok [value err expr] body...)", symbols_doc_lines_from_string("Bind a value and Odin error result from a multi-return expression. Run the body only when the error equals Odin's zero value {}. Expands to a destructuring let plus when.")[:], file)
        case "if-ok":
            symbols_write_record_doc_file(&temp, "kvist macro", entry.name, line, column, "", "(if-ok [value err expr] then else)", symbols_doc_lines_from_string("Bind a value and Odin error result from a multi-return expression. Evaluate the then branch when the error equals Odin's zero value {}, otherwise the else branch. Expands to a destructuring let plus if.")[:], file)
        case "println":
            symbols_write_record_doc_file(&temp, "kvist core", entry.name, line, column, "", "(println value...)", symbols_doc_lines_from_string("Print one or more values. Kvist lowers this to fmt output and auto-imports core:fmt when needed.")[:], file)
        case "doc":
            symbols_write_record_doc_file(&temp, "kvist core", entry.name, line, column, "", "(doc 'symbol)", symbols_doc_lines_from_string("Print the stored docstring for a declaration name.")[:], file)
        case "or-else":
            symbols_write_record_doc_file(&temp, "kvist form", entry.name, line, column, "", "(or-else expr fallback)", symbols_doc_lines_from_string("Evaluate an Odin optional-ok expression and return its value when ok is true, otherwise return the fallback value.")[:], file)
        case "update!":
            symbols_write_record_doc_file(&temp, "kvist form", entry.name, line, column, "", "(update! target key-or-field value-or-updater ...)", symbols_doc_lines_from_string("Mutate a struct field, array/slice slot, or map key in place. Supports replacement and updater forms such as inc or +.")[:], file)
        case "update":
            symbols_write_record_doc_file(&temp, "kvist form", entry.name, line, column, "", "(update target key-or-field value-or-updater ...)", symbols_doc_lines_from_string("Return an updated copy. Currently supported for struct fields.")[:], file)
        case "type":
            symbols_write_record_doc_file(&temp, "kvist form", entry.name, line, column, "", "(type Head Arg...)", symbols_doc_lines_from_string("Instantiate an Odin polymorphic type constructor. For example, (type chan.Chan int) lowers to chan.Chan(int) in both type and value positions.")[:], file)
        case:
        }
        symbols_append_unique_records(builder, seen, strings.to_string(temp))
        delete(file)
    }
}

editor_package_symbols_append :: proc(builder: ^strings.Builder, seen: ^map[string]bool, repo_root, import_path, alias: string) {
    for entry in PACKAGE_SOURCE_ENTRIES {
        if entry.import_path != import_path {
            continue
        }
        file, line, column, ok := file_location_for_snippet(repo_root, entry.relative, entry.snippet)
        if !ok {
            continue
        }
        signature, doc, ok_doc := package_entry_signature_doc(import_path, entry.member)
        if !ok_doc {
            delete(file)
            continue
        }
        doc_lines := symbols_doc_lines_from_string(doc)
        defer delete(doc_lines)
        temp := strings.builder_make()
        defer strings.builder_destroy(&temp)
        symbols_write_record_doc_file(&temp, "kvist package", fmt.tprintf("%s/%s", alias, entry.member), line, column, import_path, signature, doc_lines[:], file)
        symbols_write_record_doc_file(&temp, "kvist package", fmt.tprintf("%s.%s", alias, entry.member), line, column, import_path, signature, doc_lines[:], file)
        symbols_append_unique_records(builder, seen, strings.to_string(temp))
        delete(file)
    }
}

package_entry_signature_doc :: proc(import_path, member: string) -> (signature, doc: string, ok: bool) {
    switch import_path {
    case "kvist:arr":
        switch member {
        case "count": return "(arr/count xs)", "Count elements in an array, fixed array, or slice.", true
        case "empty": return "(arr/empty T [capacity])", "Construct an empty dynamic array, optionally with capacity.", true
        case "dynamic": return "(arr/dynamic T [v1 v2 ...])", "Construct a dynamic array from a vector literal.", true
        case "fixed": return "(arr/fixed T [v1 v2 ...])", "Construct a fixed array from a vector literal.", true
        case "get": return "(arr/get xs index)", "Index into an array-family value.", true
        case "slice": return "(arr/slice xs start [end])", "Take a slice view over an array-family value.", true
        case "push!": return "(arr/push! xs value...)", "Append one or more values to a dynamic array.", true
        case "map": return "(arr/map f xs)", "Map over an array-family input and return an owned dynamic array.", true
        case "filter": return "(arr/filter pred xs)", "Filter an array-family input and return an owned dynamic array.", true
        case "remove": return "(arr/remove pred xs)", "Remove matching values from an array-family input and return an owned dynamic array.", true
        case "map-indexed": return "(arr/map-indexed f xs)", "Map with index over an array-family input and return an owned dynamic array.", true
        case "keep": return "(arr/keep f xs)", "Keep callback results where the callback returns ok=true.", true
        case "mapcat": return "(arr/mapcat f xs)", "Map each item to a slice and append the results into one owned dynamic array.", true
        case "reduce": return "(arr/reduce f init xs)", "Reduce an array-family input to a scalar.", true
        case "first": return "(arr/first xs)", "Return the first element of an array-family value.", true
        case "rest": return "(arr/rest xs)", "Return a slice view without the first element.", true
        case "map!": return "(arr/map! f xs)", "Map in place over a dynamic array.", true
        case "map-indexed!": return "(arr/map-indexed! f xs)", "Map in place with index over a dynamic array.", true
        case "filter!": return "(arr/filter! pred xs)", "Filter in place over a dynamic array.", true
        case "remove!": return "(arr/remove! pred xs)", "Remove matching values in place from a dynamic array.", true
        case "keep!": return "(arr/keep! f xs)", "Keep callback results in place in a dynamic array.", true
        case "into": return "(arr/into [dynamic]T xs)", "Copy a collection into a new dynamic array of the requested type.", true
        case "into!": return "(arr/into! target xs)", "Append one collection into an existing dynamic array.", true
        case "interpose": return "(arr/interpose sep xs)", "Insert a separator between array elements and return an owned dynamic array.", true
        case "interleave": return "(arr/interleave xs ys)", "Interleave two arrays into an owned dynamic array.", true
        case "reverse": return "(arr/reverse xs)", "Return a reversed owned dynamic array.", true
        case "reverse!": return "(arr/reverse! xs)", "Reverse a dynamic array in place.", true
        case "shuffle": return "(arr/shuffle pick xs)", "Return a shuffled owned dynamic array.", true
        case "shuffle!": return "(arr/shuffle! pick xs)", "Shuffle a dynamic array in place.", true
        case "take": return "(arr/take n xs)", "Take a leading slice or owned result from an array-family input.", true
        case "drop": return "(arr/drop n xs)", "Drop a leading prefix from an array-family input.", true
        case "drop-last": return "(arr/drop-last n xs)", "Drop a trailing suffix from an array-family input.", true
        case "split-at": return "(arr/split-at n xs)", "Split an array-family input into left and right slice views.", true
        case "partition": return "(arr/partition n xs)", "Partition an array-family input into borrowed chunks.", true
        case "partition-all": return "(arr/partition-all n xs)", "Partition an array-family input into borrowed chunks, keeping a short tail chunk.", true
        case "partition-by": return "(arr/partition-by f xs)", "Partition an array-family input when the callback result changes.", true
        case "index-by": return "(arr/index-by f xs)", "Build a map from key function to original array values.", true
        case "group-by": return "(arr/group-by f xs)", "Build a map from key function to grouped owned dynamic arrays.", true
        case "count-by": return "(arr/count-by f xs)", "Count items by key into a map.", true
        case "sum-by": return "(arr/sum-by key-f value-f xs)", "Sum values by key into a map.", true
        case "frequencies": return "(arr/frequencies xs)", "Count occurrences of array values into a map.", true
        case "distinct": return "(arr/distinct xs)", "Return an owned dynamic array with duplicate values removed.", true
        case "distinct-by": return "(arr/distinct-by f xs)", "Return an owned dynamic array with duplicate callback keys removed.", true
        case "take-nth": return "(arr/take-nth n xs)", "Sample every nth item into an owned dynamic array.", true
        case "sort": return "(arr/sort xs)", "Return a sorted owned array.", true
        case "sort!": return "(arr/sort! xs)", "Sort a dynamic array in place.", true
        case "sort-by": return "(arr/sort-by f xs)", "Return an owned array sorted by callback key.", true
        case "sort-by!": return "(arr/sort-by! f xs)", "Sort a dynamic array in place by callback key.", true
        }
    case "kvist:str":
        switch member {
        case "count": return "(str/count s)", "Count characters or bytes in a string.", true
        case "get": return "(str/get s index)", "Index into a string.", true
        case "slice": return "(str/slice s start [end])", "Take a string slice.", true
        case "contains?": return "(str/contains? s needle)", "Return true when the string contains the needle.", true
        case "split": return "(str/split s sep)", "Split a string into an owned dynamic array of string slices.", true
        case "join": return "(str/join parts sep)", "Join a string collection into one owned string.", true
        case "trim": return "(str/trim s)", "Trim surrounding whitespace from a string slice.", true
        case "trim-prefix": return "(str/trim-prefix s prefix)", "Trim a prefix from a string slice when present.", true
        case "trim-suffix": return "(str/trim-suffix s suffix)", "Trim a suffix from a string slice when present.", true
        case "starts-with?": return "(str/starts-with? s prefix)", "Return true when the string starts with the prefix.", true
        case "ends-with?": return "(str/ends-with? s suffix)", "Return true when the string ends with the suffix.", true
        case "index-of": return "(str/index-of s needle)", "Return the byte index of the first matching substring, or -1.", true
        case "last-index-of": return "(str/last-index-of s needle)", "Return the byte index of the last matching substring, or -1.", true
        case "replace": return "(str/replace s old new [count])", "Return an owned string with substring replacements applied.", true
        case "lower": return "(str/lower s)", "Return an owned lowercased string.", true
        case "upper": return "(str/upper s)", "Return an owned uppercased string.", true
        }
    case "kvist:map":
        switch member {
        case "empty": return "(map/empty K V [capacity])", "Construct an empty map, optionally with capacity.", true
        case "of": return "(map/of K V {k1 v1 ...})", "Construct a map from a brace literal.", true
        case "get": return "(map/get m key [default])", "Look up a key in a map, optionally with a default.", true
        case "contains?": return "(map/contains? m key)", "Return true when the map contains the key.", true
        case "keys": return "(map/keys m)", "Return an owned dynamic array of map keys.", true
        case "vals": return "(map/vals m)", "Return an owned dynamic array of map values.", true
        case "zip": return "(map/zip keys vals)", "Build a map from key and value collections.", true
        case "merge": return "(map/merge lhs rhs)", "Return an owned map containing entries from both inputs.", true
        case "merge!": return "(map/merge! target source)", "Insert all entries from source into target in place.", true
        }
    case "kvist:set":
        switch member {
        case "empty": return "(set/empty T [capacity])", "Construct an empty set, optionally with capacity.", true
        case "of": return "(set/of T [v1 v2 ...])", "Construct a set from a vector literal.", true
        case "contains?": return "(set/contains? s value)", "Return true when the set contains the value.", true
        case "union": return "(set/union lhs rhs)", "Return an owned set containing values from both inputs.", true
        case "intersection": return "(set/intersection lhs rhs)", "Return an owned set containing values present in both inputs.", true
        case "difference": return "(set/difference lhs rhs)", "Return an owned set containing values from lhs not present in rhs.", true
        case "union!": return "(set/union! target source)", "Insert all values from source into target in place.", true
        case "intersection!": return "(set/intersection! target source)", "Remove values from target that are not present in source.", true
        case "difference!": return "(set/difference! target source)", "Remove every value from target that is present in source.", true
        case "subset?": return "(set/subset? lhs rhs)", "Return true when every lhs value is present in rhs.", true
        case "superset?": return "(set/superset? lhs rhs)", "Return true when lhs contains every value from rhs.", true
        case "disjoint?": return "(set/disjoint? lhs rhs)", "Return true when the sets share no values.", true
        case "add": return "(set/add s value)", "Return an owned set with the value inserted.", true
        case "add!": return "(set/add! s value)", "Insert a value into a set.", true
        case "remove": return "(set/remove s value)", "Return an owned set with the value removed.", true
        case "remove!": return "(set/remove! s value)", "Remove a value from a set in place.", true
        }
    case "kvist:struct":
        switch member {
        case "fields": return "(struct/fields target)", "Return source-level field names for a struct type or value.", true
        case "types": return "(struct/types target)", "Return source-level field types for a struct type or value.", true
        }
    case "kvist:io":
        switch member {
        case "read": return "(io/read path)", "Read a file into owned bytes using the current allocator.", true
        case "write": return "(io/write path data)", "Write bytes or text to a file.", true
        }
    case "kvist:json":
        switch member {
        case "write": return "(json/write path value)", "Encode a value as JSON and write it to a file.", true
        case "read-as": return "(json/read-as T path)", "Read JSON from a file and decode it into a typed value.", true
        }
    case "kvist:http":
        switch member {
        case "with-router": return "(http/with-router [router] body...)", "Bind a vendored HTTP router, initialize it, and destroy it on scope exit.", true
        case "get": return "(http/get router pattern [req res] body...)", "Register a GET route with a typed request/response handler.", true
        case "post": return "(http/post router pattern [req res] body...)", "Register a POST route with a typed request/response handler.", true
        case "put": return "(http/put router pattern [req res] body...)", "Register a PUT route with a typed request/response handler.", true
        case "delete": return "(http/delete router pattern [req res] body...)", "Register a DELETE route with a typed request/response handler.", true
        case "all": return "(http/all router pattern [req res] body...)", "Register a catch-all route with a typed request/response handler.", true
        case "listen": return "(http/listen port router)", "Start a loopback HTTP server for a configured router.", true
        case "respond": return "(http/respond res status)", "Send a response with a status code and no body.", true
        case "respond-plain": return "(http/respond-plain res text [status])", "Send a plain-text HTTP response.", true
        case "respond-html": return "(http/respond-html res html [status])", "Send an HTML HTTP response.", true
        case "respond-json": return "(http/respond-json res value [status])", "Send a JSON HTTP response.", true
        case "respond-file": return "(http/respond-file res path [mime])", "Send a file response.", true
        case "respond-dir": return "(http/respond-dir res base target request)", "Serve a directory path response.", true
        }
    }
    return "", "", false
}

editor_language_symbols_append :: proc(builder: ^strings.Builder, seen: ^map[string]bool, repo_root: string) {
    for entry in LANGUAGE_SOURCE_ENTRIES {
        file, line, column, ok := file_location_for_snippet(repo_root, entry.relative, entry.snippet)
        if !ok {
            continue
        }
        temp := strings.builder_make()
        defer strings.builder_destroy(&temp)
        symbols_write_record_doc_file(&temp, entry.kind, entry.name, line, column, entry.relative, "", nil, file)
        symbols_append_unique_records(builder, seen, strings.to_string(temp))
        delete(file)
    }
}

imported_symbols_source :: proc(path, source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return "", clone_compile_error(err_forms, result_allocator), false
    }
    odin_root, have_odin_root := odin_root_path()
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n")
    seen := make(map[string]bool)
    defer delete(seen)
    for top in forms {
        entry, ok_import := import_entry_from_form(top.form)
        if !ok_import {
            continue
        }
        _, import_path, ok_source_import := source_import_alias_and_path(top.form)
        if ok_source_import {
            resolved, err_resolve, ok_resolve := resolve_source_import_path(path, import_path)
            if !ok_resolve {
                return "", clone_compile_error(err_resolve, result_allocator), false
            }
            files, err_files, ok_files := read_package_files(resolved)
            if !ok_files {
                delete(resolved)
                return "", clone_compile_error(err_files, result_allocator), false
            }
            _, err_package, ok_package := validate_package_files(resolved, files[:])
            if !ok_package {
                delete(resolved)
                return "", clone_compile_error(err_package, result_allocator), false
            }
            anchor := source_package_anchor_file(files[:])
            symbols_append_source_package_import_record(&builder, &seen, entry.alias, import_path, anchor)
            for file in files {
                context.allocator = result_allocator
                package_output, package_err, ok_package_output := symbols_source(file.source)
                context.allocator = context.temp_allocator
                if !ok_package_output {
                    delete(resolved)
                    return "", clone_compile_error(package_err, result_allocator), false
                }
                symbols_append_source_package_records(&builder, &seen, import_path, entry.alias, file.path, package_output)
                delete(package_output)
            }
            delete(resolved)
            continue
        }
        if strings.has_prefix(entry.path, "kvist:") {
            if package_symbols_append(&builder, entry.path, entry.alias) {
                continue
            }
            continue
        }
        if !have_odin_root {
            continue
        }
        dir, ok_dir := odin_import_dir(odin_root, entry.path)
        if !ok_dir {
            continue
        }
        imported_symbols_scan_odin_dir(&builder, entry.alias, entry.path, dir)
        delete(dir)
    }
    return strings.clone(strings.to_string(builder), result_allocator), {}, true
}

editor_symbols_source :: proc(path, source: string) -> (output: string, err: Compile_Error, ok: bool) {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n")

    seen := make(map[string]bool)
    defer delete(seen)
    repo_root, _ := repo_root_for_path(path)
    if !os.exists(path) {
        cwd_repo_root, ok_cwd_repo_root := repo_root_for_path(".")
        if ok_cwd_repo_root {
            if repo_root != "" {
                delete(repo_root)
            }
            repo_root = cwd_repo_root
        }
    }
    if repo_root != "" {
        defer delete(repo_root)
    }

    package_files, ok_package_files := editor_root_package_files(path, source)
    if ok_package_files {
        for file in package_files {
            local_output, local_err, ok_local := symbols_source(file.source)
            if !ok_local {
                return "", local_err, false
            }
            symbols_append_local_package_records(&builder, &seen, file.path, local_output)
            delete(local_output)
        }
    } else {
        forms, err_forms, ok_forms := read_top_forms(source)
        if !ok_forms {
            return "", clone_compile_error(err_forms, context.allocator), false
        }
        local_output, local_err, ok_local := symbols_source(source)
        if !ok_local {
            return "", local_err, false
        }
        symbols_append_local_package_records(&builder, &seen, path, local_output)
        delete(local_output)

        for entry in KVIST_CANONICAL_IMPORTS_FOR_EDITOR {
            if repo_root != "" {
                editor_package_symbols_append(&builder, &seen, repo_root, entry.path, entry.alias)
            }
            package_output, ok_package := package_symbols_source(entry.path, entry.alias)
            if !ok_package {
                continue
            }
            symbols_append_unique_records(&builder, &seen, package_output)
            delete(package_output)
        }

        for top in forms {
            entry, ok_import := import_entry_from_form(top.form)
            if !ok_import {
                continue
            }
            _, import_path, ok_source_import := source_import_alias_and_path(top.form)
            if ok_source_import {
                resolved, err_resolve, ok_resolve := resolve_source_import_path(path, import_path)
                if !ok_resolve {
                    return "", err_resolve, false
                }
                files, err_files, ok_files := read_package_files(resolved)
                if !ok_files {
                    delete(resolved)
                    return "", err_files, false
                }
                _, err_package, ok_package := validate_package_files(resolved, files[:])
                if !ok_package {
                    delete(resolved)
                    return "", err_package, false
                }
                anchor := source_package_anchor_file(files[:])
                symbols_append_source_package_import_record(&builder, &seen, entry.alias, import_path, anchor)
                for file in files {
                    package_output, package_err, ok_package_output := symbols_source(file.source)
                    if !ok_package_output {
                        delete(resolved)
                        return "", package_err, false
                    }
                    symbols_append_source_package_records(&builder, &seen, import_path, entry.alias, file.path, package_output)
                    delete(package_output)
                }
                delete(resolved)
                continue
            }
            if !strings.has_prefix(entry.path, "kvist:") {
                continue
            }
            if repo_root != "" && entry.path != "kvist:hiccup" {
                editor_package_symbols_append(&builder, &seen, repo_root, entry.path, entry.alias)
            }
            package_output, ok_package := package_symbols_source(entry.path, entry.alias)
            if ok_package {
                symbols_append_unique_records(&builder, &seen, package_output)
                delete(package_output)
            }
        }
        imported_output, imported_err, ok_imported := imported_symbols_source(path, source)
        if !ok_imported {
            return "", imported_err, false
        }
        symbols_append_unique_records(&builder, &seen, imported_output)
        delete(imported_output)

        if repo_root != "" {
            editor_builtin_symbols_append(&builder, &seen, repo_root)
            editor_language_symbols_append(&builder, &seen, repo_root)
        }
        builtin_output := builtin_symbols_source()
        symbols_append_unique_records(&builder, &seen, builtin_output)
        delete(builtin_output)
        language_output := language_symbols_source()
        symbols_append_unique_records(&builder, &seen, language_output)
        delete(language_output)
        return strings.clone(strings.to_string(builder)), {}, true
    }

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return "", clone_compile_error(err_forms, context.allocator), false
    }
    for entry in KVIST_CANONICAL_IMPORTS_FOR_EDITOR {
        if repo_root != "" {
            editor_package_symbols_append(&builder, &seen, repo_root, entry.path, entry.alias)
        }
        package_output, ok_package := package_symbols_source(entry.path, entry.alias)
        if !ok_package {
            continue
        }
        symbols_append_unique_records(&builder, &seen, package_output)
        delete(package_output)
    }
    for top in forms {
        entry, ok_import := import_entry_from_form(top.form)
        if !ok_import || !strings.has_prefix(entry.path, "kvist:") {
            continue
        }
        if repo_root != "" {
            editor_package_symbols_append(&builder, &seen, repo_root, entry.path, entry.alias)
        }
        package_output, ok_package := package_symbols_source(entry.path, entry.alias)
        if ok_package {
            symbols_append_unique_records(&builder, &seen, package_output)
            delete(package_output)
        }
        if repo_root != "" {
            continue
        }
        _, import_path, ok_source_import := source_import_alias_and_path(top.form)
        if ok_source_import {
            resolved, err_resolve, ok_resolve := resolve_source_import_path(path, import_path)
            if !ok_resolve {
                return "", err_resolve, false
            }
            files, err_files, ok_files := read_package_files(resolved)
            if !ok_files {
                delete(resolved)
                return "", err_files, false
            }
            _, err_package, ok_package := validate_package_files(resolved, files[:])
            if !ok_package {
                delete(resolved)
                return "", err_package, false
            }
            for file in files {
                package_output, package_err, ok_package_output := symbols_source(file.source)
                if !ok_package_output {
                    delete(resolved)
                    return "", package_err, false
                }
                symbols_append_source_package_records(&builder, &seen, import_path, entry.alias, file.path, package_output)
                delete(package_output)
            }
            delete(resolved)
        }
    }
    imported_output, imported_err, ok_imported := imported_symbols_source(path, source)
    if !ok_imported {
        return "", imported_err, false
    }
    symbols_append_unique_records(&builder, &seen, imported_output)
    delete(imported_output)
    if repo_root != "" {
        editor_builtin_symbols_append(&builder, &seen, repo_root)
        editor_language_symbols_append(&builder, &seen, repo_root)
    }
    builtin_output := builtin_symbols_source()
    symbols_append_unique_records(&builder, &seen, builtin_output)
    delete(builtin_output)
    language_output := language_symbols_source()
    symbols_append_unique_records(&builder, &seen, language_output)
    delete(language_output)
    return strings.clone(strings.to_string(builder)), {}, true
}

package_symbols_write_entry :: proc(builder: ^strings.Builder, alias, import_path, member, signature, doc: string) {
    doc_lines := symbols_doc_lines_from_string(doc)
    defer delete(doc_lines)
    symbols_write_record_doc(builder, "kvist package", fmt.tprintf("%s/%s", alias, member), "", Span{start = 0, end = 0, source = .File}, import_path, signature, doc_lines[:])
    symbols_write_record_doc(builder, "kvist package", fmt.tprintf("%s.%s", alias, member), "", Span{start = 0, end = 0, source = .File}, import_path, signature, doc_lines[:])
}

package_symbols_append :: proc(builder: ^strings.Builder, import_path, alias: string) -> bool {
    wrote_any := false
    for entry in PACKAGE_SOURCE_ENTRIES {
        if entry.import_path != import_path {
            continue
        }
        signature, doc, ok := package_entry_signature_doc(import_path, entry.member)
        if !ok {
            continue
        }
        package_symbols_write_entry(builder, alias, import_path, entry.member, signature, doc)
        wrote_any = true
    }
    return wrote_any
}

package_symbols_source :: proc(import_path, alias: string) -> (output: string, ok: bool) {
    result_allocator := context.allocator

    resolved_alias := alias
    if resolved_alias == "" {
        resolved_alias = import_default_alias(import_path)
    }
    if resolved_alias == "" {
        return "", false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n")
    if package_symbols_append(&builder, import_path, resolved_alias) {
        return strings.clone(strings.to_string(builder), result_allocator), true
    }
    resolved, err_resolve, ok_resolve := resolve_source_import_path(".", import_path)
    if !ok_resolve {
        _ = err_resolve
        return "", false
    }
    defer delete(resolved)
    files, err_files, ok_files := read_package_files(resolved)
    if !ok_files {
        _ = err_files
        return "", false
    }
    _, err_package, ok_package := validate_package_files(resolved, files[:])
    if !ok_package {
        _ = err_package
        return "", false
    }
    seen := make(map[string]bool)
    defer delete(seen)
    for file in files {
        package_output, package_err, ok_package_output := symbols_source(file.source)
        if !ok_package_output {
            _ = package_err
            return "", false
        }
        symbols_append_source_package_records(&builder, &seen, import_path, resolved_alias, file.path, package_output)
        delete(package_output)
    }
    return strings.clone(strings.to_string(builder), result_allocator), true
}

import_default_alias :: proc(path: string) -> string {
    end := len(path)
    for end > 0 && path[end-1] == '/' {
        end -= 1
    }
    start := end
    for start > 0 {
        ch := path[start-1]
        if ch == '/' || ch == ':' {
            break
        }
        start -= 1
    }
    if start >= end {
        return ""
    }
    return map_name(path[start:end])
}

is_static_kvist_package :: proc(import_path: string) -> bool {
    switch import_path {
    case "kvist:arr", "kvist:str", "kvist:map", "kvist:set", "kvist:struct", "kvist:io", "kvist:json", "kvist:http":
        return true
    case:
        return false
    }
}

symbols_write_record :: proc(builder: ^strings.Builder, kind, name: string, source: string, span: Span, detail: string = "") {
    line, column := 1, 1
    if source != "" {
        line, column, _, _ = source_position(source, span.start)
    }
    fmt.sbprintf(builder, "%s\t%s\t%d\t%d\t%s\t\t\n", kind, name, line, column, detail)
}

symbols_clean_doc_line :: proc(line: string) -> string {
    text := line
    if len(text) >= 2 && text[0] == '/' && text[1] == '/' {
        text = text[2:]
    }
    if len(text) > 0 && text[0] == ' ' {
        text = text[1:]
    }
    return text
}

symbols_write_escaped_doc :: proc(builder: ^strings.Builder, doc_lines: []string) {
    for line, i in doc_lines {
        if i > 0 {
            strings.write_string(builder, "\\n")
        }
        text := symbols_clean_doc_line(line)
        for ch in text {
            switch ch {
            case '\\':
                strings.write_string(builder, "\\\\")
            case '\t':
                strings.write_string(builder, "\\t")
            case '\r':
                strings.write_string(builder, "\\r")
            case '\n':
                strings.write_string(builder, "\\n")
            case:
                strings.write_rune(builder, ch)
            }
        }
    }
}

symbols_write_record_doc :: proc(builder: ^strings.Builder, kind, name: string, source: string, span: Span, detail: string, signature: string, doc_lines: []string) {
    line, column := 1, 1
    if source != "" {
        line, column, _, _ = source_position(source, span.start)
    }
    fmt.sbprintf(builder, "%s\t%s\t%d\t%d\t%s\t%s\t", kind, name, line, column, detail, signature)
    symbols_write_escaped_doc(builder, doc_lines)
    strings.write_byte(builder, '\n')
}

symbols_proc_signature :: proc(name: string, decl: Proc_Decl) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    fmt.sbprintf(&builder, "(%s [", name)
    for param, idx in decl.params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s: %s", param.name, param.ty)
    }
    strings.write_string(&builder, "]")

    #partial switch decl.returns.kind {
    case .Single:
        fmt.sbprintf(&builder, " -> %s", decl.returns.single_ty)
    case .Named:
        strings.write_string(&builder, " -> [")
        for field, idx in decl.returns.named {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            fmt.sbprintf(&builder, "%s: %s", field.name, field.ty)
        }
        strings.write_string(&builder, "]")
    case:
    }

    strings.write_string(&builder, ")")
    return strings.to_string(builder)
}

symbols_struct_signature :: proc(name: string, fields: []Struct_Field) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    strings.write_string(&builder, "(")
    strings.write_string(&builder, name)
    strings.write_string(&builder, " {")
    for field, idx in fields {
        if idx > 0 {
            strings.write_string(&builder, " ")
        }
        strings.write_string(&builder, ":")
        strings.write_string(&builder, field.source_name)
        strings.write_string(&builder, " ")
        strings.write_string(&builder, field.ty)
    }
    strings.write_string(&builder, "})")
    return strings.to_string(builder)
}

symbols_doc_lines_from_string :: proc(text: string) -> (lines: [dynamic]string) {
    start := 0
    for i := 0; i <= len(text); i += 1 {
        if i == len(text) || text[i] == '\n' {
            line := text[start:i]
            append(&lines, fmt.tprintf("// %s", line))
            start = i + 1
        }
    }
    if len(lines) == 0 {
        append(&lines, "// ")
    }
    return lines
}

symbols_append_doc_lines :: proc(base, extra: []string) -> (lines: [dynamic]string) {
    for line in base {
        append(&lines, line)
    }
    for line in extra {
        append(&lines, line)
    }
    return lines
}

symbols_write_fields :: proc(builder: ^strings.Builder, source, parent: string, fields: CST_Form) {
    if fields.kind != .Brace {
        return
    }
    i := 0
    for i < len(fields.items) {
        if i+1 >= len(fields.items) {
            return
        }
        key := fields.items[i]
        if key.kind == .Keyword && len(key.text) > 1 {
            name := fmt.tprintf("%s.%s", parent, key.text[1:])
            symbols_write_record(builder, "field", name, source, key.span, parent)
        }
        i += 2
    }
}

symbols_write_enum_variants :: proc(builder: ^strings.Builder, source, parent: string, variants: CST_Form) {
    #partial switch variants.kind {
    case .Vector:
        for item in variants.items {
            if item.kind == .Symbol {
                name := fmt.tprintf("%s.%s", parent, item.text)
                symbols_write_record(builder, "variant", name, source, item.span, parent)
            }
        }
    case .Brace:
        i := 0
        for i < len(variants.items) {
            if i+1 >= len(variants.items) {
                return
            }
            key := variants.items[i]
            if key.kind == .Keyword && len(key.text) > 1 {
                name := fmt.tprintf("%s.%s", parent, key.text[1:])
                symbols_write_record(builder, "variant", name, source, key.span, parent)
            }
            i += 2
        }
    case:
    }
}

symbols_write_union_variants :: proc(builder: ^strings.Builder, source, parent: string, variants: CST_Form) {
    if variants.kind != .Brace {
        return
    }
    i := 0
    for i < len(variants.items) {
        if i+1 >= len(variants.items) {
            return
        }
        key := variants.items[i]
        if key.kind == .Keyword && len(key.text) > 1 {
            name := fmt.tprintf("%s.%s", parent, key.text[1:])
            symbols_write_record(builder, "variant", name, source, key.span, parent)
        }
        i += 2
    }
}

symbols_source :: proc(source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return "", clone_compile_error(err_forms, result_allocator), false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n")

    for top in forms {
        form := top.form
        if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
            continue
        }
        head := form.items[0].text
        switch head {
        case "import":
            if len(form.items) == 2 && form.items[1].kind == .String {
                path := import_path_text(form.items[1])
                alias := import_default_alias(path)
                if alias != "" {
                    symbols_write_record_doc(&builder, "import", alias, source, form.items[1].span, path, "", top.doc_lines[:])
                }
            } else if len(form.items) == 3 && form.items[1].kind == .Symbol && form.items[2].kind == .String {
                alias := form.items[1].text
                path := import_path_text(form.items[2])
                symbols_write_record_doc(&builder, "import", alias, source, form.items[1].span, path, "", top.doc_lines[:])
            }
        case "defconst", "defconst-":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                if len(form.items) > 3 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                detail := ""
                if head == "defconst-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "const", form.items[1].text, source, form.items[1].span, detail, "", doc_lines[:])
            }
        case "defvar", "defvar-":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                if len(form.items) > 3 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                detail := ""
                if head == "defvar-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "var", form.items[1].text, source, form.items[1].span, detail, "", doc_lines[:])
            }
        case "defstruct", "defstruct-":
            if (len(form.items) == 3 || len(form.items) == 4) && form.items[1].kind == .Symbol {
                name := form.items[1].text
                doc_lines := top.doc_lines
                field_index := 2
                if len(form.items) == 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                    field_index = 3
                }
                signature := ""
                fields_sig, err_fields, ok_fields_sig := parse_defstruct_fields(form.items[field_index])
                if ok_fields_sig {
                    signature = symbols_struct_signature(name, fields_sig[:])
                } else {
                    _ = err_fields
                }
                detail := ""
                if head == "defstruct-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "struct", name, source, form.items[1].span, detail, signature, doc_lines[:])
                symbols_write_fields(&builder, source, name, form.items[field_index])
            }
        case "defstate":
            if (len(form.items) == 3 || len(form.items) == 4 || len(form.items) == 5) && form.items[1].kind == .Symbol {
                name := form.items[1].text
                doc_lines := top.doc_lines
                field_index := 2
                if len(form.items) >= 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                    field_index = 3
                }
                signature := ""
                fields_sig, err_fields, ok_fields_sig := parse_defstruct_fields(form.items[field_index])
                if ok_fields_sig {
                    signature = symbols_struct_signature(name, fields_sig[:])
                } else {
                    _ = err_fields
                }
                symbols_write_record_doc(&builder, "struct", name, source, form.items[1].span, "state", signature, doc_lines[:])
                symbols_write_fields(&builder, source, name, form.items[field_index])
            }
        case "defenum", "defenum-":
            if (len(form.items) == 3 || len(form.items) == 4) && form.items[1].kind == .Symbol {
                name := form.items[1].text
                doc_lines := top.doc_lines
                variant_index := 2
                if len(form.items) == 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                    variant_index = 3
                }
                detail := ""
                if head == "defenum-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "enum", name, source, form.items[1].span, detail, "", doc_lines[:])
                symbols_write_enum_variants(&builder, source, name, form.items[variant_index])
            }
        case "defunion", "defunion-":
            if (len(form.items) == 3 || len(form.items) == 4) && form.items[1].kind == .Symbol {
                name := form.items[1].text
                doc_lines := top.doc_lines
                variant_index := 2
                if len(form.items) == 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                    variant_index = 3
                }
                detail := ""
                if head == "defunion-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "union", name, source, form.items[1].span, detail, "", doc_lines[:])
                symbols_write_union_variants(&builder, source, name, form.items[variant_index])
            }
        case "defn", "defn-":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                proc_form := form
                if len(form.items) > 3 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                    items: [dynamic]CST_Form
                    append(&items, form.items[0], form.items[1])
                    for item in form.items[3:] {
                        append(&items, item)
                    }
                    proc_form = CST_Form{kind = .List, items = items, span = form.span}
                }
                signature := ""
                proc_decl, err_proc, ok_proc := parse_proc_decl(proc_form)
                if ok_proc {
                    signature = symbols_proc_signature(form.items[1].text, proc_decl)
                } else {
                    _ = err_proc
                }
                detail := ""
                if head == "defn-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "proc", form.items[1].text, source, form.items[1].span, detail, signature, doc_lines[:])
            }
        case "defmacro", "defmacro-":
            if len(form.items) >= 3 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                if len(form.items) > 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                signature := fmt.tprintf("(%s ...)", form.items[1].text)
                if len(form.items) >= 3 && form.items[2].kind == .Vector {
                    signature = fmt.tprintf("(%s %s)", form.items[1].text, macro_form_text(form.items[2]))
                } else if len(form.items) >= 4 && form.items[3].kind == .Vector {
                    signature = fmt.tprintf("(%s %s)", form.items[1].text, macro_form_text(form.items[3]))
                }
                detail := ""
                if head == "defmacro-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "macro", form.items[1].text, source, form.items[1].span, detail, signature, doc_lines[:])
            }
        case:
        }
    }

    context.allocator = result_allocator
    return strings.clone(strings.to_string(builder), result_allocator), {}, true
}
