package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
symbols_source_indexes_top_level_forms :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:strings" :as strings)

;; A user record.
;; Owned by caller.
(defstruct User {
  name: string
  active: bool
})

(defenum Status [
  Active
  Archived
])

(defunion Value {
  i: int
  s: string
})

(def max-age: int 120)

;; Returns true for active users.
;; Used by sequence examples.
(defn active? [user: User] -> bool
  user.active)

(defiter active-users [users: []User] -> User_Source :yield User
  :next next-user
  (open-users users))`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n"), true)
    testing.expect_value(t, strings.contains(output, "import\tstrings\t2\t28\tcore:strings\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "struct\tUser\t6\t12\t\t(User {name: string active: bool})\tA user record.\\nOwned by caller.\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tUser.name\t7\t3\tUser\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "enum\tStatus\t11\t10\t\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "variant\tStatus.Active\t12\t3\tStatus\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "union\tValue\t16\t11\t\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "variant\tValue.i\t17\t3\tValue\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "const\tmax-age\t21\t6\t\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "iterator\tactive-users\t28\t10\t\t(active-users [users: []User] -> User_Source :yield User)\t\n"), true)
    testing.expect_value(t, strings.contains(output, "proc\tactive?\t25\t7\t\t(active? [user: User] -> bool)\tReturns true for active users.\\nUsed by sequence examples.\n"), true)
}

@(test)
symbols_source_indexes_defstruct_docstring :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person
  "Primary profile."
  {name: string
   age: int})`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "struct\tPerson\t3\t12\t\t(Person {name: string age: int})\tPrimary profile.\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tPerson.name\t5\t4\tPerson\t\t\n"), true)
}

@(test)
symbols_source_preserves_struct_field_defaults :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person {
  name: string :default "anonymous"
  active?: bool :default false
  scores: [dynamic]i64 :default []
})`

    output, err, ok := kvist.symbols_source(source)
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
            `(Person {name: string :default "anonymous" active?: bool :default false scores: [dynamic]i64 :default []})`,
        ),
        true,
    )
    testing.expect_value(t, strings.contains(output, "field\tPerson.active?\t5\t3\tPerson\t\t\n"), true)
}

@(test)
symbols_source_indexes_reload_state_as_ordinary_struct_and_alias :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct App_State
  {steps: int
   message: string})

(def Reload_State App_State)`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "struct\tApp_State\t3\t12\t\t(App_State {steps: int message: string})\t\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tApp_State.steps\t4\t4\tApp_State\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tApp_State.message\t5\t4\tApp_State\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "const\tReload_State"), true)
}

@(test)
symbols_source_indexes_defunion_and_defenum :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Status [
  Active
  Archived
])

(defunion Value {
  i: int
  s: string
})`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "enum\tStatus\t3\t10\t\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "variant\tStatus.Active\t4\t3\tStatus\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "union\tValue\t8\t11\t\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "variant\tValue.i\t9\t3\tValue\t\t\n"), true)
}

@(test)
symbols_source_includes_proc_default_values_in_signatures :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!", count: int = (+ 1 2)] -> string
  name)`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc\tgreet\t3\t7\tlifetime=result-borrowed\t(greet [name: string, punctuation: string = \"!\", count: int = (+ 1 2)] -> string)\t\n"), true)
}

@(test)
symbols_source_includes_dot_access_param_signatures :: proc(t: ^testing.T) {
    source := `(package main)

(import fmt "core:fmt")

(defstruct Point {
  x: int
  y: int
})

(defn draw [point: Point] -> int
  (+ point.x point.y))`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(draw [point: Point] -> int)"), true)
}

@(test)
builtin_symbols_source_emits_signatures_and_docs :: proc(t: ^testing.T) {
    output := kvist.builtin_symbols_source()
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n"), true)
    testing.expect_value(t, strings.contains(output, "\tprintln\t"), false)
    testing.expect_value(t, strings.contains(output, "\tdoc\t"), false)
    testing.expect_value(t, strings.contains(output, "\tor-else\t"), false)
    testing.expect_value(t, strings.contains(output, "\tupdate!\t"), false)
    testing.expect_value(t, strings.contains(output, "\twhen-let\t"), false)
    testing.expect_value(t, strings.contains(output, "\tif-let\t"), false)
    testing.expect_value(t, strings.contains(output, "\twhen-ok\t"), false)
    testing.expect_value(t, strings.contains(output, "\tif-ok\t"), false)
}

@(test)
package_symbols_source_supports_shipped_test_package :: proc(t: ^testing.T) {
    output, ok := kvist.package_symbols_source("kvist:test", "t")
    testing.expect_value(t, ok, true)
    if !ok {
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "macro\tt.deftest\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tt.is\t"), true)
}

@(test)
package_symbols_source_emits_core_update_helpers :: proc(t: ^testing.T) {
    output, ok := kvist.package_symbols_source("kvist:core", "core")
    testing.expect_value(t, ok, true)
    if !ok {
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "macro\tcore.update!\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.update\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.assoc\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.len\t"), false)
    testing.expect_value(t, strings.contains(output, "macro\tcore.when\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.cond\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.comment\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.case\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.->\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.->>\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.or-else\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.doc\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.nil?\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.tap>\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.println\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.str\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.when-let\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.if-let\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.when-ok\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.if-ok\t"), true)
}

@(test)
package_symbols_source_emits_bit_helpers :: proc(t: ^testing.T) {
    output, ok := kvist.package_symbols_source("kvist:bit", "bit")
    testing.expect_value(t, ok, true)
    if !ok {
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "macro\tbit.and\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tbit.or\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tbit.shift-left\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tbit.test\t"), true)
}

@(test)
imported_symbols_source_indexes_odin_imports :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt" :as fmt)`

    output, err, ok := kvist.imported_symbols_source("/tmp/imported-symbols-test.kvist", source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println"), true)
    testing.expect_value(t, strings.contains(output, "\tcore:fmt\t"), true)
}

@(test)
editor_symbols_source_merges_context_surfaces :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")

(defstruct Greeting {message: string})

(defn main []
  (let [g (Greeting {message: "hi"})]
    (println g.message)))`

    output, err, ok := kvist.editor_symbols_source("/tmp/editor-symbols-test.kvist", source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n"), true)
    testing.expect_value(t, strings.contains(output, "struct\tGreeting\t"), true)
    testing.expect_value(t, strings.contains(output, "proc\tmain\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tarr.push!\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist package\tcore.println\t"), true)
    testing.expect_value(t, strings.contains(output, "odin\tfmt.println\t"), true)
}

@(test)
editor_symbols_source_indexes_local_defvar_struct_fields :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Animation {
  texture: int
  num-frames: int
  name: string
})

(defn main []
  (defvar player-idle (Animation {texture: 1 num-frames: 3 name: "idle"}))
  (defvar current-anim player-idle))`

    output, err, ok := kvist.editor_symbols_source("/tmp/editor-local-fields-test.kvist", source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "local\tplayer-idle\t10\t11\tAnimation\t\t\t/tmp/editor-local-fields-test.kvist\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tplayer-idle.texture\t10\t11\tAnimation\t\t\t/tmp/editor-local-fields-test.kvist\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tplayer-idle.num-frames\t10\t11\tAnimation\t\t\t/tmp/editor-local-fields-test.kvist\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tcurrent-anim.name\t11\t11\tAnimation\t\t\t/tmp/editor-local-fields-test.kvist\n"), true)
}

@(test)
editor_symbols_source_includes_language_forms_and_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn main []
  (let [x 1]
    (if true
      (arr.map inc [1 2 3])
      (println x))))`

    path, ok_path := repo_temp_test_path(".tmp-editor-symbols-test.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    output, err, ok := kvist.editor_symbols_source(path, source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    for entry in kvist.LANGUAGE_SOURCE_ENTRIES {
        expected := fmt.tprintf("kvist form\t%s\t", entry.name)
        testing.expect_value(t, strings.contains(output, expected), true)
    }
    testing.expect_value(t, strings.contains(output, "kvist form\tlet\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tif\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tdefiter\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\twhen\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist form\tcond\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist form\tcase\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist form\tswitch\t"), false)
    testing.expect_value(t, strings.contains(output, "compatibility syntax\tswitch\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist form\twhile\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tfor\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tdiscard\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tupdate!\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist form\tdelete!\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist form\tget\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist form\tslice\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist form\taddr\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tderef\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tloop\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist helper\tprintln\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist helper\tcase\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist helper\tupdate!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist helper\tdelete!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist helper\tget\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist helper\tslice\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist helper\tcond\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist helper\twhen-let\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist helper\tswitch\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist package\tcore.println\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tarr.map\t"), true)
}

@(test)
editor_symbols_source_includes_proc_default_values_in_signatures :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!", count: int = (+ 1 2)] -> string
  name)`

    output, err, ok := kvist.editor_symbols_source("/tmp/editor-default-signature-test.kvist", source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc\tgreet\t3\t7\tlifetime=result-borrowed\t(greet [name: string, punctuation: string = \"!\", count: int = (+ 1 2)] -> string)\t\t/tmp/editor-default-signature-test.kvist\n"), true)
}

@(test)
editor_symbols_source_includes_dot_access_param_signatures :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  x: int
  y: int
})

(defn draw [point: Point] -> int
  (+ point.x point.y))`

    output, err, ok := kvist.editor_symbols_source("/tmp/editor-dot-signature-test.kvist", source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(draw [point: Point] -> int)"), true)
}

@(test)
editor_symbols_source_includes_expanded_str_and_set_packages :: proc(t: ^testing.T) {
    source := `(package main)
(import str "kvist:str")
(import set "kvist:set")

(defn main []
  (let [parts (str.split "a,b" ",")
        seen (set.empty string)]
    (defer (delete parts))
    (defer (delete seen))
    (set.union! seen (set.of string ["a"]))
    (println (str.trim " ok "))))`

    path, ok_path := repo_temp_test_path(".tmp-str-set-editor-symbols.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    output, err, ok := kvist.editor_symbols_source(path, source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist package\tstr.split\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tstr.replace\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tset.union!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tset.difference!\t"), true)
}

@(test)
editor_symbols_source_includes_core_package_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn main []
  (let [xs [1 2 3]]
    (println (count xs) (empty? xs) (contains? xs 2))))`

    path, ok_path := repo_temp_test_path(".tmp-core-editor-symbols.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    output, err, ok := kvist.editor_symbols_source(path, source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist package\tcore.count\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tcore.empty?\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tcore.contains?\t"), true)
}

@(test)
editor_symbols_source_does_not_preload_unimported_shipped_packages :: proc(t: ^testing.T) {
    source := `(package main)

(defn main [] -> int
  1)`

    path, ok_path := repo_temp_test_path(".tmp-no-shipped-preload-editor-symbols.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    output, err, ok := kvist.editor_symbols_source(path, source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist package\tcore.println\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tarr.map\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist package\tstr.split\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist package\thtml.render\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist package\tcli.flag\t"), false)
}

@(test)
editor_symbols_source_includes_arr_and_map_mutation_packages :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")
(import map "kvist:map")

(defn main []
  (let [xs ([dynamic]int [1 2 3])
        lookup (map.of string int {"seed" 1})]
    (defer (delete xs))
    (defer (delete lookup))
    (arr.map! inc xs)
    (map.assoc! lookup "next" 2)
    (map.dissoc! lookup "seed")
    (println xs lookup)))`

    path, ok_path := repo_temp_test_path(".tmp-arr-map-mutation-editor-symbols.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    output, err, ok := kvist.editor_symbols_source(path, source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist package\tarr.map!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tarr.fill!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tarr.dynamic\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tarr.push!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tarr.sort-by!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tmap.assoc!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tmap.dissoc!\t"), true)
}

@(test)
editor_symbols_source_includes_soa_package_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import soa "kvist:soa")

(defstruct Profile
  {name: string
   active?: bool})

(defn main []
  (let [profiles (soa.make Profile 4)]
    (defer (delete profiles))
    (println (soa.fields 'Profile) (soa.types 'Profile) (count profiles))))`

    path, ok_path := repo_temp_test_path(".tmp-soa-editor-symbols.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    output, err, ok := kvist.editor_symbols_source(path, source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist package\tsoa.fields\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tsoa.types\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tsoa.make\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tsoa.push!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tsoa.update!\t"), true)
}

@(test)
editor_symbols_source_does_not_preload_unimported_relative_packages :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-editor-relative-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    tools_dir, tools_dir_err := os.join_path({dir, "tools"}, context.allocator)
    testing.expect_value(t, tools_dir_err == nil, true)
    if tools_dir_err != nil {
        return
    }
    defer delete(tools_dir)

    mk_tools_err := os.make_directory_all(tools_dir)
    testing.expect_value(t, mk_tools_err == nil, true)
    if mk_tools_err != nil {
        return
    }

    tools_path, tools_path_err := os.join_path({tools_dir, "tools.kvist"}, context.allocator)
    testing.expect_value(t, tools_path_err == nil, true)
    if tools_path_err != nil {
        return
    }
    defer delete(tools_path)
    tools_write_err := os.write_entire_file_from_string(tools_path, `(package tools)

(defn answer [] -> int
  42)`)
    testing.expect_value(t, tools_write_err == nil, true)
    if tools_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)

    main_source := `(package main)

(defn main [] -> int
  1)`
    output, err, ok := kvist.editor_symbols_source(main_path, main_source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist package\ttools.answer\t"), false)
    testing.expect_value(t, strings.contains(output, tools_path), false)
}

@(test)
editor_symbols_source_includes_generic_export_markers :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-editor-export-marker-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, pkg_dir_err := os.join_path({dir, "tools"}, context.allocator)
    testing.expect_value(t, pkg_dir_err == nil, true)
    if pkg_dir_err != nil {
        return
    }
    defer delete(pkg_dir)
    mk_pkg_err := os.make_directory_all(pkg_dir)
    testing.expect_value(t, mk_pkg_err == nil, true)
    if mk_pkg_err != nil {
        return
    }

    pkg_path, pkg_path_err := os.join_path({pkg_dir, "tools.kvist"}, context.allocator)
    testing.expect_value(t, pkg_path_err == nil, true)
    if pkg_path_err != nil {
        return
    }
    defer delete(pkg_path)
    pkg_source := `(package tools)
(@exports [marker])

(defn visible [] -> int
  1)`
    pkg_write_err := os.write_entire_file_from_string(pkg_path, pkg_source)
    testing.expect_value(t, pkg_write_err == nil, true)
    if pkg_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)
(import tools "./tools")

(defn main [] -> int
  (tools.visible))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    output, err, ok := kvist.editor_symbols_source(main_path, main_source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "macro\ttools.marker\t"), true)
    testing.expect_value(t, strings.contains(output, "proc\ttools.visible\t"), true)
}

@(test)
editor_symbols_source_includes_multi_file_root_package_symbols :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-editor-root-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package demo)

(defn main [] -> int
  (helper-value 5))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    helpers_path, helpers_join_err := os.join_path({dir, "helpers.kvist"}, context.allocator)
    testing.expect_value(t, helpers_join_err == nil, true)
    if helpers_join_err != nil {
        return
    }
    defer delete(helpers_path)
    helpers_source := `(package demo)

(defn- secret-bonus [] -> int
  2)

(defn helper-value [n: int] -> int
  (+ n (secret-bonus)))`
    helpers_write_err := os.write_entire_file_from_string(helpers_path, helpers_source)
    testing.expect_value(t, helpers_write_err == nil, true)
    if helpers_write_err != nil {
        return
    }

    output, err, ok := kvist.editor_symbols_source(main_path, main_source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc\tmain\t"), true)
}

@(test)
editor_symbols_source_includes_multi_file_root_package_symbols_from_non_anchor_file :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-editor-root-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package demo)

(defstruct App_State
  {count: int})

(defn main [] -> int
  (helper-value 5))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    app_path, app_join_err := os.join_path({dir, "app.kvist"}, context.allocator)
    testing.expect_value(t, app_join_err == nil, true)
    if app_join_err != nil {
        return
    }
    defer delete(app_path)
    app_source := `(package demo)

(defn helper-value [n: int] -> int
  (+ n 1))`
    app_write_err := os.write_entire_file_from_string(app_path, app_source)
    testing.expect_value(t, app_write_err == nil, true)
    if app_write_err != nil {
        return
    }

    output, err, ok := kvist.editor_symbols_source(app_path, app_source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc\tmain\t"), true)
    testing.expect_value(t, strings.contains(output, "struct\tApp_State\t"), true)
    testing.expect_value(t, strings.contains(output, main_path), true)
}

@(test)
editor_symbols_source_includes_relative_source_package_imports :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-editor-source-import-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package demo)
(import math "support/math")

(defn main [] -> int
  (math.sum-range 0 5))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    support_dir, support_dir_err := os.join_path({dir, "support", "math"}, context.allocator)
    testing.expect_value(t, support_dir_err == nil, true)
    if support_dir_err != nil {
        return
    }
    defer delete(support_dir)
    mk_support_err := os.make_directory_all(support_dir)
    testing.expect_value(t, mk_support_err == nil, true)
    if mk_support_err != nil {
        return
    }

    support_path, support_path_err := os.join_path({support_dir, "math.kvist"}, context.allocator)
    testing.expect_value(t, support_path_err == nil, true)
    if support_path_err != nil {
        return
    }
    defer delete(support_path)
    support_source := `(package math)

(defn sum-range [start: int, end: int] -> int
  (+ start end))`
    support_write_err := os.write_entire_file_from_string(support_path, support_source)
    testing.expect_value(t, support_write_err == nil, true)
    if support_write_err != nil {
        return
    }

    output, err, ok := kvist.editor_symbols_source(main_path, main_source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "source import\tmath\t1\t1\tsupport/math\t(import math \"support/math\")"), true)
    testing.expect_value(t, strings.contains(output, "proc\tmath.sum-range\t"), true)
    testing.expect_value(t, strings.contains(output, support_path), true)
}

@(test)
compile_eval_source_map_marks_eval_runner :: proc(t: ^testing.T) {
    source := `(package main)

(defn add [a: int, b: int] -> int
  (+ a b))`

    result, err, ok := kvist.compile_eval_source_with_map(source, "(add 1 2)")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    found_eval_entry := false
    for entry in result.source_map {
        if entry.source_span.source == .Eval {
            found_eval_entry = true
            break
        }
    }
    testing.expect_value(t, found_eval_entry, true)
}

@(test)
reader_treats_slash_comment_markers_as_symbols :: proc(t: ^testing.T) {
    tokens, err, ok := kvist.tokenize("// /* */")
    defer delete(tokens)

    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, len(tokens), 4)
    testing.expect_value(t, tokens[0].kind, kvist.Token_Kind.Symbol)
    testing.expect_value(t, tokens[0].text, "//")
    testing.expect_value(t, tokens[1].kind, kvist.Token_Kind.Symbol)
    testing.expect_value(t, tokens[1].text, "/*")
    testing.expect_value(t, tokens[2].kind, kvist.Token_Kind.Symbol)
    testing.expect_value(t, tokens[2].text, "*/")
}

@(test)
compile_source_with_declaration_source_map :: proc(t: ^testing.T) {
    source := `(package main)

(def answer 42)

(defn main []
  (return))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    expected := `package main

answer :: 42

main :: proc() {
    return
}
`
    testing.expect_value(t, result.output, expected)
    testing.expect_value(t, len(result.source_map) >= 4, true)
    package_entry, found_package := kvist.source_map_entry_for_generated_line(result.source_map[:], 1)
    testing.expect_value(t, found_package, true)
    testing.expect_value(t, package_entry.source_span.start, 0)

    const_entry, found_const := kvist.source_map_entry_for_generated_line(result.source_map[:], 3)
    testing.expect_value(t, found_const, true)
    testing.expect_value(t, const_entry.source_span.start > package_entry.source_span.start, true)

    proc_entry, found_proc := kvist.source_map_entry_for_generated_line(result.source_map[:], 5)
    testing.expect_value(t, found_proc, true)
    proc_line, _, _, _ := kvist.source_position(source, proc_entry.source_span.start)
    testing.expect_value(t, proc_line, 5)

    return_entry, found_return := kvist.source_map_entry_for_generated_line(result.source_map[:], 6)
    testing.expect_value(t, found_return, true)
    return_line, return_column, _, _ := kvist.source_position(source, return_entry.source_span.start)
    testing.expect_value(t, return_line, 6)
    testing.expect_value(t, return_column, 3)
}

@(test)
compile_source_map_accounts_for_feature_line_and_multiline_raw :: proc(t: ^testing.T) {
    source := `(package main)

(odin "Foreign_Handle :: distinct rawptr\nOther_Handle :: distinct rawptr")

(defn main []
  (let [lookup (map[string]int {"one" 1})]
    (return)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.source_map) >= 5, true)
    package_entry, found_package := kvist.source_map_entry_for_generated_line(result.source_map[:], 2)
    testing.expect_value(t, found_package, true)
    testing.expect_value(t, package_entry.source_span.start, 0)

    raw_entry, found_raw := kvist.source_map_entry_for_generated_line(result.source_map[:], 4)
    testing.expect_value(t, found_raw, true)
    raw_line, _, _, _ := kvist.source_position(source, raw_entry.source_span.start)
    testing.expect_value(t, raw_line, 3)

    proc_entry, found_proc := kvist.source_map_entry_for_generated_line(result.source_map[:], 7)
    testing.expect_value(t, found_proc, true)
    proc_line, _, _, _ := kvist.source_position(source, proc_entry.source_span.start)
    testing.expect_value(t, proc_line, 5)

    binding_entry, found_binding := kvist.source_map_entry_for_generated_line(result.source_map[:], 8)
    testing.expect_value(t, found_binding, true)
    binding_line, binding_column, _, _ := kvist.source_position(source, binding_entry.source_span.start)
    testing.expect_value(t, binding_line, 6)
    testing.expect_value(t, binding_column > 0, true)
}

@(test)
format_declaration_source_map :: proc(t: ^testing.T) {
    entries := [?]kvist.Source_Map_Entry{
        {
            generated_start_line = 1,
            generated_end_line = 3,
            source_span = kvist.Span{start = 10, end = 20},
        },
        {
            generated_start_line = 2,
            generated_end_line = 2,
            source_span = kvist.Span{start = 30, end = 35},
        },
        {
            generated_start_line = 2,
            generated_end_line = 2,
            generated_start_column = 8,
            generated_end_column = 12,
            source_span = kvist.Span{start = 40, end = 45},
        },
    }

    formatted := kvist.format_source_map(entries[:])
    defer delete(formatted)

    expected := `generated_start generated_end source_start source_end
1 3 10 20
2 2 30 35
2 2 40 45
`
    testing.expect_value(t, formatted, expected)

    entry, found := kvist.source_map_entry_for_generated_line(entries[:], 2)
    testing.expect_value(t, found, true)
    testing.expect_value(t, entry.source_span.start, 30)

    column_entry, column_found := kvist.source_map_entry_for_generated_location(entries[:], 2, 9)
    testing.expect_value(t, column_found, true)
    testing.expect_value(t, column_entry.source_span.start, 40)

    fallback_entry, fallback_found := kvist.source_map_entry_for_generated_location(entries[:], 2, 2)
    testing.expect_value(t, fallback_found, true)
    testing.expect_value(t, fallback_entry.source_span.start, 30)

    _, missing := kvist.source_map_entry_for_generated_line(entries[:], 4)
    testing.expect_value(t, missing, false)
}

@(test)
cli_test_command_runs_filtered_kvist_tests :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-test-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    generated, generated_err := os.join_path({dir, "generated.odin"}, context.allocator)
    testing.expect_value(t, generated_err == nil, true)
    if generated_err != nil {
        return
    }
    defer delete(generated)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    source := `(package tests)

(import t "kvist:test")

(t.deftest passing
  (t.is true))

(t.deftest failing
  (t.is false))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path, "--generated", generated, "--names", "passing"},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    testing.expect_value(t, os.exists(generated), true)
}

@(test)
cli_test_command_reports_testing_context :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-test-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package tests)

(import t "kvist:test")

(t.deftest failing
  (t.testing "numbers"
    (t.testing "parity"
      (t.is false "not ok"))))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path, "--names", "failing"},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 1)
    testing.expect_value(t, strings.contains(string(stdout), "numbers > parity: not ok") || strings.contains(string(stderr), "numbers > parity: not ok"), true)
}

@(test)
cli_reload_command_discovers_sibling_reload_adapter :: proc(t: ^testing.T) {
    repo_root := compiler_test_repo_root()
    dir, dir_err := os.make_directory_temp(repo_root, "kvist-reload-discovery-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package demo_app)

(defstruct App_State
  {ticks: int})

(defn init [state: ^App_State]
  (set! state^.ticks 0))

(defn tick [state: ^App_State]
  (mut! state^.ticks += 1))

(defn main []
  (let [state (App_State {})]
    (init &state)
    (tick &state)))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    reload_path, reload_join_err := os.join_path({dir, "reload.kvist"}, context.allocator)
    testing.expect_value(t, reload_join_err == nil, true)
    if reload_join_err != nil {
        return
    }
    defer delete(reload_path)
    reload_source := `(package demo_reload)
(import app "main")
(import r "kvist:reload")

(def Reload_State app.App_State)

(defn init [state: ^Reload_State]
  (app.init state))

(defn run [state: ^Reload_State host: ^r.Run_Host]
  (app.tick state)
  (when (r.checkpoint! host)
    (return)))`
    reload_write_err := os.write_entire_file_from_string(reload_path, reload_source)
    testing.expect_value(t, reload_write_err == nil, true)
    if reload_write_err != nil {
        return
    }

    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "dev", "--reload", main_path, "--print-paths", "--json"},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    testing.expect_value(t, json_field_contains_path(string(stdout), "input", reload_path), true)
    testing.expect_value(t, strings.contains(string(stdout), "reload.kvist"), true)

    check_state, check_stdout, check_stderr, check_exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "check", reload_path},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(check_stdout)
    defer delete(check_stderr)

    testing.expect_value(t, check_exec_err == nil, true)
    if check_exec_err != nil {
        return
    }
    testing.expect_value(t, check_state.exited, true)
    testing.expect_value(t, check_state.exit_code, 0)
}

@(test)
cli_reload_command_resolves_runtime_from_configured_root :: proc(t: ^testing.T) {
    sync.lock(&test_env_mutex)
    defer sync.unlock(&test_env_mutex)

    dir, dir_err := os.make_directory_temp("", "kvist-reload-home-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    core_dir, core_dir_err := os.join_path({dir, "core"}, context.allocator)
    testing.expect_value(t, core_dir_err == nil, true)
    if core_dir_err != nil {
        return
    }
    defer delete(core_dir)
    mk_core_err := os.make_directory_all(core_dir)
    testing.expect_value(t, mk_core_err == nil, true)
    if mk_core_err != nil {
        return
    }
    core_path, core_path_err := os.join_path({core_dir, "core.kvist"}, context.allocator)
    testing.expect_value(t, core_path_err == nil, true)
    if core_path_err != nil {
        return
    }
    defer delete(core_path)
    core_write_err := os.write_entire_file_from_string(core_path, `(package core)`)
    testing.expect_value(t, core_write_err == nil, true)
    if core_write_err != nil {
        return
    }

    reload_dir, reload_dir_err := os.join_path({dir, "reload"}, context.allocator)
    testing.expect_value(t, reload_dir_err == nil, true)
    if reload_dir_err != nil {
        return
    }
    defer delete(reload_dir)
    mk_reload_err := os.make_directory_all(reload_dir)
    testing.expect_value(t, mk_reload_err == nil, true)
    if mk_reload_err != nil {
        return
    }
    reload_pkg_path, reload_pkg_path_err := os.join_path({reload_dir, "reload.kvist"}, context.allocator)
    testing.expect_value(t, reload_pkg_path_err == nil, true)
    if reload_pkg_path_err != nil {
        return
    }
    defer delete(reload_pkg_path)
    reload_pkg_source := `(package reload)

(defstruct Run_Host {})

(defn checkpoint! [host: ^Run_Host] -> bool
  false)`
    reload_pkg_write_err := os.write_entire_file_from_string(reload_pkg_path, reload_pkg_source)
    testing.expect_value(t, reload_pkg_write_err == nil, true)
    if reload_pkg_write_err != nil {
        return
    }

    runtime_dir, runtime_dir_err := os.join_path({dir, "odin", "olive_reload"}, context.allocator)
    testing.expect_value(t, runtime_dir_err == nil, true)
    if runtime_dir_err != nil {
        return
    }
    defer delete(runtime_dir)
    mk_runtime_err := os.make_directory_all(runtime_dir)
    testing.expect_value(t, mk_runtime_err == nil, true)
    if mk_runtime_err != nil {
        return
    }

    app_path, app_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, app_path_err == nil, true)
    if app_path_err != nil {
        return
    }
    defer delete(app_path)
    app_source := `(package demo_app)

(defstruct App_State
  {ticks: int})

(defn tick [state: ^App_State]
  (mut! state^.ticks += 1))`
    app_write_err := os.write_entire_file_from_string(app_path, app_source)
    testing.expect_value(t, app_write_err == nil, true)
    if app_write_err != nil {
        return
    }

    adapter_path, adapter_path_err := os.join_path({dir, "reload.kvist"}, context.allocator)
    testing.expect_value(t, adapter_path_err == nil, true)
    if adapter_path_err != nil {
        return
    }
    defer delete(adapter_path)
    adapter_source := `(package demo_reload)
(import app "main")
(import reload "kvist:reload")

(def Reload_State app.App_State)

(defn run [state: ^Reload_State host: ^reload.Run_Host]
  (app.tick state))`
    adapter_write_err := os.write_entire_file_from_string(adapter_path, adapter_source)
    testing.expect_value(t, adapter_write_err == nil, true)
    if adapter_write_err != nil {
        return
    }

    generated_dir, generated_dir_err := os.join_path({dir, "generated"}, context.allocator)
    testing.expect_value(t, generated_dir_err == nil, true)
    if generated_dir_err != nil {
        return
    }
    defer delete(generated_dir)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    root_env := fmt.tprintf("KVIST_ROOT=%s", dir)
    child_env, child_env_ok := test_child_env_without_kvist_vars({root_env})
    testing.expect_value(t, child_env_ok, true)
    if !child_env_ok {
        return
    }
    defer test_env_slice_delete(&child_env)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "dev", "--reload", app_path, "--generated-dir", generated_dir, "--print-paths", "--json"},
            working_dir = dir,
            env = child_env[:],
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    if !state.exited || state.exit_code != 0 {
        testing.expect_value(t, string(stderr), "")
        return
    }

    module_path, module_path_err := os.join_path({generated_dir, "module", "main.odin"}, context.allocator)
    testing.expect_value(t, module_path_err == nil, true)
    if module_path_err != nil {
        return
    }
    defer delete(module_path)
    module_source, module_read_err := os.read_entire_file_from_path(module_path, context.allocator)
    testing.expect_value(t, module_read_err == nil, true)
    if module_read_err != nil {
        return
    }
    defer delete(module_source)

    module_forward, _ := strings.replace_all(string(module_source), "\\", "/", context.temp_allocator)
    testing.expect_value(t, strings.contains(module_forward, "import olive_reload "), true)
    testing.expect_value(t, strings.contains(module_forward, "odin/olive_reload"), true)
    testing.expect_value(t, strings.contains(module_forward, "runtime/dev"), false)
    testing.expect_value(t, strings.contains(module_forward, "src/odin/olive_reload"), false)
}

@(test)
cli_check_accepts_bare_package_file_in_working_directory :: proc(t: ^testing.T) {
    repo_root := compiler_test_repo_root()
    dir, dir_err := os.make_directory_temp(repo_root, "kvist-bare-package-file-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package demo)

(defn main []
  (helper-value))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    helper_path, helper_join_err := os.join_path({dir, "helper.kvist"}, context.allocator)
    testing.expect_value(t, helper_join_err == nil, true)
    if helper_join_err != nil {
        return
    }
    defer delete(helper_path)
    helper_source := `(package demo)

(defn helper-value [] -> int
  42)`
    helper_write_err := os.write_entire_file_from_string(helper_path, helper_source)
    testing.expect_value(t, helper_write_err == nil, true)
    if helper_write_err != nil {
        return
    }

    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "check", "main.kvist"},
            working_dir = dir,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
}

@(test)
cli_test_command_runs_builtin_package_suite :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-builtin-package-suite-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    path, join_err := os.join_path({repo_root, "examples", "coverage", "packages", "builtin-package-tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
}

@(test)
cli_test_command_runs_test_package_suite :: proc(t: ^testing.T) {
    when ODIN_OS == .Windows {
        // ponytail: Windows runner stack-overflows compiling this large generated suite; keep Mac/Linux execution.
        return
    }

    dir, dir_err := os.make_directory_temp("", "kvist-test-package-suite-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    path, join_err := os.join_path({repo_root, "examples", "coverage", "packages", "test-package-tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
}

@(test)
cli_test_command_runs_arr_package_suite :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-arr-package-suite-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    path, join_err := os.join_path({repo_root, "examples", "coverage", "packages", "arr-package-tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
}

@(test)
cli_test_command_runs_package_edge_suite :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-package-edge-suite-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    path, join_err := os.join_path({repo_root, "examples", "coverage", "packages", "package-edge-tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
}

@(test)
cli_test_command_runs_package_file_order_suite :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-package-file-order-suite-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    path, join_err := os.join_path({repo_root, "examples", "coverage", "packages", "package-file-order-tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
}

@(test)
compile_typed_block_expression_preserves_defer_and_source_map :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn total [] -> int
  (let [answer: int (do
                      (let [xs ([dynamic]int [1 2 3]) :defer]
                        (count xs)))]
    answer))`

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
    testing.expect_value(t, len(result.source_map) > 0, true)
    testing.expect_value(t, strings.contains(result.output, "answer: int = (proc() -> int {"), true)
    testing.expect_value(t, strings.contains(result.output, "defer delete(xs)"), true)
    testing.expect_value(t, strings.contains(result.output, "return len(xs)"), true)
}

@(test)
macroexpand_source_map_marks_generated_lines :: proc(t: ^testing.T) {
    source := `(with-temp-allocator [allocator]
  (let [xs (arr.map inc users)]
    (count xs)))`
    result, err, ok := kvist.macroexpand_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.source_map), 9)

    body_start := strings.index(source, "(let [xs (arr.map inc users)]")

    body_entry, body_found := kvist.source_map_entry_for_generated_line(result.source_map[:], 9)
    testing.expect_value(t, body_found, true)
    testing.expect_value(t, body_entry.source_span.start, body_start)
}

@(test)
compile_keyword_and_data_map_invocation_lower_to_borrowed_lookup :: proc(t: ^testing.T) {
    source := `(package main)
(import data "kvist:data")

(defn keyword-lookup [message: Data] -> Data
  (:owner message))

(defn keyword-default [message: Data] -> Data
  (:owner message :nobody))

(defn map-lookup [message: Data] -> Data
  (message :owner))

(defn owned-default [message: Data] -> Data
  (:owner message (data.from-string "nobody")))

(defn nested-name [message: Data] -> Data
  (let [owner (:owner message)]
    (:name owner)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_data_map_call(message, Data{kind = .Keyword"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_map_call_or(message, Data{kind = .Keyword"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_retain(kvist_data_map_call(message"), true)
    testing.expect_value(t, strings.contains(output, "\"nobody\""), true)
    testing.expect_value(t, strings.contains(output, "defer kvist_data_release(kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "message(keyword("), false)
    testing.expect_value(t, strings.contains(output, "kvist_data_map_call :: proc"), true)
    testing.expect_value(t, strings.contains(output, "Data invocation expects a map or nil"), true)
}

@(test)
format_compile_errors_with_line_column_and_context :: proc(t: ^testing.T) {
    source := `(package main)
(unknown thing)`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    formatted := kvist.format_compile_error("bad.kvist", source, err)
    defer delete(formatted)

    expected := `bad.kvist:2:2: unsupported top-level form: unknown
  (unknown thing)
   ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
compile_and_symbols_resolve_kvist_imports_from_configured_root :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-home-flat-root-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    core_dir, core_dir_err := os.join_path({dir, "core"}, context.allocator)
    testing.expect_value(t, core_dir_err == nil, true)
    if core_dir_err != nil {
        return
    }
    defer delete(core_dir)
    mk_core_err := os.make_directory_all(core_dir)
    testing.expect_value(t, mk_core_err == nil, true)
    if mk_core_err != nil {
        return
    }
    core_path, core_path_err := os.join_path({core_dir, "core.kvist"}, context.allocator)
    testing.expect_value(t, core_path_err == nil, true)
    if core_path_err != nil {
        return
    }
    defer delete(core_path)
    core_write_err := os.write_entire_file_from_string(core_path, `(package core)`)
    testing.expect_value(t, core_write_err == nil, true)
    if core_write_err != nil {
        return
    }

    toy_dir, toy_dir_err := os.join_path({dir, "toy"}, context.allocator)
    testing.expect_value(t, toy_dir_err == nil, true)
    if toy_dir_err != nil {
        return
    }
    defer delete(toy_dir)
    mk_toy_err := os.make_directory_all(toy_dir)
    testing.expect_value(t, mk_toy_err == nil, true)
    if mk_toy_err != nil {
        return
    }
    toy_path, toy_path_err := os.join_path({toy_dir, "toy.kvist"}, context.allocator)
    testing.expect_value(t, toy_path_err == nil, true)
    if toy_path_err != nil {
        return
    }
    defer delete(toy_path)
    toy_write_err := os.write_entire_file_from_string(toy_path, `(package toy)

(defn id [x: int] -> int
  x)`)
    testing.expect_value(t, toy_write_err == nil, true)
    if toy_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    main_write_err := os.write_entire_file_from_string(main_path, `(package main)
(import toy "kvist:toy")

(defn main [] -> int
  (toy.id 42))`)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    output_path, output_path_err := os.join_path({dir, "main.odin"}, context.allocator)
    testing.expect_value(t, output_path_err == nil, true)
    if output_path_err != nil {
        return
    }
    defer delete(output_path)

    root_env := fmt.tprintf("KVIST_ROOT=%s", dir)
    child_env, child_env_ok := test_child_env_without_kvist_vars({root_env})
    testing.expect_value(t, child_env_ok, true)
    if !child_env_ok {
        return
    }
    defer test_env_slice_delete(&child_env)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "compile", main_path, "-o", output_path},
            working_dir = dir,
            env = child_env[:],
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    if !state.exited || state.exit_code != 0 {
        testing.expect_value(t, string(stderr), "")
        return
    }

    output, read_err := os.read_entire_file_from_path(output_path, context.allocator)
    testing.expect_value(t, read_err == nil, true)
    if read_err != nil {
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(string(output), "toy__id :: proc(x: int) -> int"), true)
    testing.expect_value(t, strings.contains(string(output), "return toy__id(42)"), true)

    symbols_state, symbols_stdout, symbols_stderr, symbols_exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "package-symbols", "kvist:toy", "toy"},
            working_dir = dir,
            env = child_env[:],
        },
        context.allocator,
    )
    defer delete(symbols_stdout)
    defer delete(symbols_stderr)

    testing.expect_value(t, symbols_exec_err == nil, true)
    if symbols_exec_err != nil {
        return
    }
    testing.expect_value(t, symbols_state.exited, true)
    testing.expect_value(t, symbols_state.exit_code, 0)
    if !symbols_state.exited || symbols_state.exit_code != 0 {
        testing.expect_value(t, string(symbols_stderr), "")
        return
    }
    testing.expect_value(t, strings.contains(string(symbols_stdout), "toy.id"), true)
}

@(test)
compile_and_symbols_resolve_relative_source_package_imports :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-relative-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    toy_dir, toy_join_err := os.join_path({dir, "packages", "toy"}, context.allocator)
    testing.expect_value(t, toy_join_err == nil, true)
    if toy_join_err != nil {
        return
    }
    defer delete(toy_dir)

    mk_toy_err := os.make_directory_all(toy_dir)
    testing.expect_value(t, mk_toy_err == nil, true)
    if mk_toy_err != nil {
        return
    }

    toy_path, toy_path_err := os.join_path({toy_dir, "toy.kvist"}, context.allocator)
    testing.expect_value(t, toy_path_err == nil, true)
    if toy_path_err != nil {
        return
    }
    defer delete(toy_path)
    toy_write_err := os.write_entire_file_from_string(toy_path, `(package toy)

(defn id [x: int] -> int
  x)`)
    testing.expect_value(t, toy_write_err == nil, true)
    if toy_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)
(import toy "packages/toy")

(defn main [] -> int
  (toy.id 42))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "toy__id :: proc(x: int) -> int"), true)
    testing.expect_value(t, strings.contains(output, "return toy__id(42)"), true)

    symbols, symbols_err, symbols_ok := kvist.editor_symbols_source(main_path, main_source)
    testing.expect_value(t, symbols_ok, true)
    if !symbols_ok {
        testing.expect_value(t, symbols_err.message, "")
        return
    }
    defer delete(symbols)
    testing.expect_value(t, strings.contains(symbols, "source import\ttoy\t1\t1\tpackages/toy"), true)
    testing.expect_value(t, strings.contains(symbols, "proc\ttoy.id\t"), true)
    testing.expect_value(t, strings.contains(symbols, toy_path), true)
}

@(test)
cli_check_loads_core_macros_outside_repo_with_root :: proc(t: ^testing.T) {
    sync.lock(&test_env_mutex)
    defer sync.unlock(&test_env_mutex)

    repo_root := compiler_test_repo_root()

    dir, dir_err := os.make_directory_temp("", "kvist-core-macros-env-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_write_err := os.write_entire_file_from_string(main_path, `(package main)

(defn main []
  (when true
    (println "hello from kvist")))`)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    source_root, source_root_err := os.join_path({repo_root, "src", "kvist"}, context.allocator)
    testing.expect_value(t, source_root_err == nil, true)
    if source_root_err != nil {
        return
    }
    defer delete(source_root)

    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    root_env := fmt.tprintf("KVIST_ROOT=%s", source_root)
    child_env, child_env_ok := test_child_env_without_kvist_vars({root_env})
    testing.expect_value(t, child_env_ok, true)
    if !child_env_ok {
        return
    }
    defer test_env_slice_delete(&child_env)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "check", "main.kvist"},
            working_dir = dir,
            env = child_env[:],
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    testing.expect_value(t, strings.contains(string(stderr), "core macro loading"), false)
}

@(test)
cli_root_rejects_invalid_configured_root_without_fallback :: proc(t: ^testing.T) {
    sync.lock(&test_env_mutex)
    defer sync.unlock(&test_env_mutex)

    dir, dir_err := os.make_directory_temp("", "kvist-invalid-root-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    invalid_root, invalid_root_err := os.join_path({dir, "missing-root"}, context.allocator)
    testing.expect_value(t, invalid_root_err == nil, true)
    if invalid_root_err != nil {
        return
    }
    defer delete(invalid_root)
    root_env := fmt.tprintf("KVIST_ROOT=%s", invalid_root)
    child_env, child_env_ok := test_child_env_without_kvist_vars({root_env})
    testing.expect_value(t, child_env_ok, true)
    if !child_env_ok {
        return
    }
    defer test_env_slice_delete(&child_env)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "root"},
            working_dir = dir,
            env = child_env[:],
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 1)
    testing.expect_value(t, strings.contains(string(stderr), "could not resolve Kvist package root"), true)
}

@(test)
cli_resolves_packages_from_symlink_install_layout :: proc(t: ^testing.T) {
    sync.lock(&test_env_mutex)
    defer sync.unlock(&test_env_mutex)

    when ODIN_OS == .Windows {
        return
    }

	repo_root := compiler_test_repo_root()

    dir, dir_err := os.make_directory_temp("", "kvist-path-symlink-install-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    install_bin, install_bin_err := os.join_path({dir, "install", "bin"}, context.allocator)
    testing.expect_value(t, install_bin_err == nil, true)
    if install_bin_err != nil {
        return
    }
    defer delete(install_bin)
    path_bin, path_bin_err := os.join_path({dir, "path-bin"}, context.allocator)
    testing.expect_value(t, path_bin_err == nil, true)
    if path_bin_err != nil {
        return
    }
    defer delete(path_bin)
    source_parent, source_parent_err := os.join_path({dir, "install"}, context.allocator)
    testing.expect_value(t, source_parent_err == nil, true)
    if source_parent_err != nil {
        return
    }
    defer delete(source_parent)

    mk_install_err := os.make_directory_all(install_bin)
    mk_path_err := os.make_directory_all(path_bin)
    testing.expect_value(t, mk_install_err == nil, true)
    testing.expect_value(t, mk_path_err == nil, true)
    if mk_install_err != nil || mk_path_err != nil {
        return
    }

    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, install_bin)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    helper_source, helper_source_err := os.join_path({install_bin, "src"}, context.allocator)
    testing.expect_value(t, helper_source_err == nil, true)
    if helper_source_err != nil {
        return
    }
    defer delete(helper_source)
    _ = os.remove_all(helper_source)

    repo_source, repo_source_err := os.join_path({repo_root, "src", "kvist"}, context.allocator)
    testing.expect_value(t, repo_source_err == nil, true)
    if repo_source_err != nil {
        return
    }
    defer delete(repo_source)
    repo_core, repo_core_err := os.join_path({repo_source, "core"}, context.allocator)
    testing.expect_value(t, repo_core_err == nil, true)
    if repo_core_err != nil {
        return
    }
    defer delete(repo_core)
    installed_source, installed_source_err := os.join_path({source_parent, "core"}, context.allocator)
    testing.expect_value(t, installed_source_err == nil, true)
    if installed_source_err != nil {
        return
    }
    defer delete(installed_source)
    source_link_err := os.symlink(repo_core, installed_source)
    testing.expect_value(t, source_link_err == nil, true)
    if source_link_err != nil {
        return
    }

    path_kvist, path_kvist_err := os.join_path({path_bin, "kvist"}, context.allocator)
    testing.expect_value(t, path_kvist_err == nil, true)
    if path_kvist_err != nil {
        return
    }
    defer delete(path_kvist)
    link_err := os.symlink(kvist_bin, path_kvist)
    testing.expect_value(t, link_err == nil, true)
    if link_err != nil {
        return
    }

    child_env, child_env_ok := test_child_env_without_kvist_vars(nil)
    testing.expect_value(t, child_env_ok, true)
    if !child_env_ok {
        return
    }
    defer test_env_slice_delete(&child_env)

    main_path, main_join_err := os.join_path({dir, "hello.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_write_err := os.write_entire_file_from_string(main_path, `(package main)

(defn main []
  (println "hello from kvist"))`)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    root_state, root_stdout, root_stderr, root_exec_err := os.process_exec(
		os.Process_Desc{
			command = {path_kvist, "root"},
			working_dir = dir,
			env = child_env[:],
		},
		context.allocator,
	)
    defer delete(root_stdout)
    defer delete(root_stderr)
    testing.expect_value(t, root_exec_err == nil, true)
    if root_exec_err != nil {
        return
    }
    testing.expect_value(t, root_state.exited, true)
    testing.expect_value(t, root_state.exit_code, 0)
    expected_root, expected_root_err := os.get_absolute_path(source_parent, context.allocator)
    testing.expect_value(t, expected_root_err == nil, true)
    if expected_root_err != nil {
        return
    }
    defer delete(expected_root)
    testing.expect_value(t, strings.trim_space(string(root_stdout)), expected_root)

	state, stdout, stderr, exec_err := os.process_exec(
		os.Process_Desc{
			command = {path_kvist, "check", main_path},
			working_dir = dir,
			env = child_env[:],
		},
		context.allocator,
	)
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    testing.expect_value(t, strings.contains(string(stderr), "core macro loading"), false)
}

@(test)
package_artifacts_do_not_rewrite_dependency_locals_as_root_symbols :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-package-local-shadow-*", context.allocator)
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
(import data "kvist:data")
(import support "support")
(defn map-value [] -> int 42)
(defn main [] -> bool
  (and (data.nil? nil) (= (support.identity 7) 7)))`) == nil, true)
    testing.expect_value(t, os.write_entire_file_from_string(support_path, `(package support)
(defn identity [map-value: int] -> int map-value)`) == nil, true)

    result, err, ok := kvist.compile_path_with_package_artifacts(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer kvist.package_emit_result_delete(&result)

    found_support := false
    found_shared_runtime := false
    for artifact in result.artifacts {
        testing.expect_value(t, strings.contains(artifact.output, "root.map_value"), false)
        if strings.contains(artifact.output, "support__identity") {
            found_support = true
            testing.expect_value(t, strings.contains(artifact.output, "map_value: int"), true)
        }
        if artifact.id == "kvp_shared" {
            found_shared_runtime = true
        }
    }
    testing.expect_value(t, found_support, true)
    testing.expect_value(t, found_shared_runtime, true)
}

@(test)
lifetimes_source_explains_inferred_boundaries_without_annotations :: proc(t: ^testing.T) {
    source := `(package main)

(defn allocate [] -> [dynamic]int
  (make [dynamic]int))

(defn consume [values: [dynamic]int]
  (delete values))

(defn view [value: Data] -> Data
  value)`

    output, err, ok := kvist.lifetimes_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "Inferred lifetime boundaries (no source annotations)"), true)
    testing.expect_value(t, strings.contains(output, "result: owned; every inferred return path produces a new value"), true)
    testing.expect_value(t, strings.contains(output, "values: consumed; the body explicitly deletes it"), true)
    testing.expect_value(t, strings.contains(output, "result: caller-owned Data reference; the compiler retains the borrowed source"), true)
}
