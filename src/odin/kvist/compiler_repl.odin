package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "core:time"
import "base:runtime"

repl_odin_sidecar_dir :: proc(path: string) -> string {
    if os.exists(path) && os.is_dir(path) {
        return strings.clone(path)
    }
    dir, _ := os.split_path(path)
    if dir == "" {
        return strings.clone(".")
    }
    return strings.clone(dir)
}

source_import_option_index :: proc(
    form: CST_Form,
    option: string,
    value_kind: CST_Form_Kind,
) -> (int, bool) {
    if form.kind != .List ||
       len(form.items) < 4 ||
       len(form.items)%2 != 0 ||
       !is_symbol(form.items[0], "import") ||
       form.items[1].kind != .String {
        return -1, false
    }
    for i := 2; i+1 < len(form.items); i += 2 {
        if form.items[i].kind == .Keyword &&
           form.items[i].text == option &&
           form.items[i+1].kind == value_kind {
            return i+1, true
        }
    }
    return -1, false
}

source_import_refer_index :: proc(form: CST_Form) -> (int, bool) {
    return source_import_option_index(form, ":refer", .Vector)
}

source_import_as_index :: proc(form: CST_Form) -> (int, bool) {
    return source_import_option_index(form, ":as", .Symbol)
}

Repl_Package_Scope :: struct {
    prefix:         string,
    locals:         [dynamic]string,
    private_macros: [dynamic]string,
    aliases:        [dynamic]Alias_Prefix,
}

paths_refer_to_same_file :: proc(left, right: string) -> bool {
    left_absolute, left_err := os.get_absolute_path(left, context.allocator)
    if left_err != nil {
        return false
    }
    defer delete(left_absolute)
    right_absolute, right_err := os.get_absolute_path(right, context.allocator)
    if right_err != nil {
        return false
    }
    defer delete(right_absolute)
    return left_absolute == right_absolute
}

repl_scope_from_package_files :: proc(
    files: []Package_File,
    prefix,
    target_path: string,
) -> (scope: Repl_Package_Scope, matched: bool, err: Compile_Error, ok: bool) {
    target_in_package := false
    for file in files {
        if paths_refer_to_same_file(file.path, target_path) {
            target_in_package = true
            break
        }
    }
    if !target_in_package {
        return scope, false, Compile_Error{}, true
    }

    all_forms := flatten_package_forms(files)
    defer delete(all_forms)
    scope.prefix = strings.clone(prefix)
    collected_locals := collect_local_decl_names(all_forms[:])
    scope.locals = clone_string_slice(collected_locals[:])
    delete(collected_locals)
    collected_private_macros := collect_private_macro_decl_names(all_forms[:])
    scope.private_macros = clone_string_slice(collected_private_macros[:])
    delete(collected_private_macros)

    err_core, ok_core := append_core_bare_symbol_alias(&scope.aliases, target_path)
    if !ok_core {
        return scope, true, err_core, false
    }
    package_name := files[0].package_name
    if prefix != "" && package_name != "" {
        exported := collect_public_decl_names(all_forms[:])
        raw_dir := repl_odin_sidecar_dir(target_path)
        raw_exported := collect_raw_odin_decl_names_from_dir(raw_dir)
        delete(raw_dir)
        append(&scope.aliases, Alias_Prefix{
            alias = strings.clone(package_name),
            prefix = strings.clone(prefix),
            raw_prefix = odin_package_import_alias(prefix),
            exports = clone_string_slice(exported[:]),
            raw_exports = clone_string_slice(raw_exported[:]),
        })
        delete(exported)
        delete_string_slice(&raw_exported)
    }
    for file in files {
        for top in file.forms {
            alias, import_path, is_import :=
                source_import_alias_and_path(top.form, file.path)
            if !is_import {
                continue
            }
            resolved, err_resolve, ok_resolve :=
                resolve_source_import_path(file.path, import_path)
            delete(import_path)
            if !ok_resolve {
                delete(alias)
                return scope, true, err_resolve, false
            }
            import_files, err_files, ok_files := read_package_files(resolved)
            if !ok_files {
                delete(alias)
                delete(resolved)
                return scope, true, err_files, false
            }
            import_forms := flatten_package_forms(import_files[:])
            exports := collect_public_decl_names(import_forms[:])
            raw_dir := repl_odin_sidecar_dir(resolved)
            raw_exports := collect_raw_odin_decl_names_from_dir(raw_dir)
            delete(raw_dir)
            nested_prefix := alias
            if prefix != "" {
                nested_prefix = fmt.aprintf("%s__%s", prefix, alias)
            }
            append(&scope.aliases, Alias_Prefix{
                alias = alias,
                prefix = strings.clone(nested_prefix),
                raw_prefix = odin_package_import_alias(nested_prefix),
                exports = clone_string_slice(exports[:]),
                raw_exports = clone_string_slice(raw_exports[:]),
                refer_names = source_import_refer_names(top.form),
                allow_unqualified_exports = source_import_form_has_refer(top.form),
            })
            if prefix != "" {
                delete(nested_prefix)
            }
            delete(exports)
            delete_string_slice(&raw_exports)
            delete(import_forms)
            package_file_slice_delete(import_files)
            delete(resolved)
        }
    }
    return scope, true, Compile_Error{}, true
}

find_repl_package_scope_imported :: proc(
    dir,
    prefix,
    target_path: string,
    visiting: ^[dynamic]string,
) -> (scope: Repl_Package_Scope, matched: bool, err: Compile_Error, ok: bool) {
    key := fmt.aprintf("%s|%s", dir, prefix)
    defer delete(key)
    if contains_text(visiting[:], key) {
        return scope, false, Compile_Error{}, true
    }
    append(visiting, strings.clone(key))
    files, err_files, ok_files := read_package_files(dir)
    if !ok_files {
        return scope, false, err_files, false
    }
    defer package_file_slice_delete(files)
    scope, matched, err, ok =
        repl_scope_from_package_files(files, prefix, target_path)
    if matched || !ok {
        return
    }
    for file in files {
        for top in file.forms {
            alias, import_path, is_import :=
                source_import_alias_and_path(top.form, file.path)
            if !is_import {
                continue
            }
            resolved, err_resolve, ok_resolve :=
                resolve_source_import_path(file.path, import_path)
            delete(import_path)
            if !ok_resolve {
                delete(alias)
                return scope, false, err_resolve, false
            }
            nested_prefix := alias
            if prefix != "" {
                nested_prefix = fmt.aprintf("%s__%s", prefix, alias)
            }
            nested_scope, nested_matched, nested_err, nested_ok :=
                find_repl_package_scope_imported(
                    resolved,
                    nested_prefix,
                    target_path,
                    visiting,
                )
            if prefix != "" {
                delete(nested_prefix)
            }
            delete(alias)
            delete(resolved)
            if nested_matched || !nested_ok {
                return nested_scope, nested_matched, nested_err, nested_ok
            }
        }
    }
    return scope, false, Compile_Error{}, true
}

find_repl_package_scope :: proc(
    root_path,
    target_path: string,
) -> (scope: Repl_Package_Scope, err: Compile_Error, ok: bool) {
    root_files, err_files, ok_files := read_root_package_files(root_path)
    if !ok_files {
        return scope, err_files, false
    }
    defer package_file_slice_delete(root_files)
    root_scope, matched, err_root, ok_root :=
        repl_scope_from_package_files(root_files, "", target_path)
    if matched || !ok_root {
        return root_scope, err_root, ok_root
    }
    visiting: [dynamic]string
    defer delete_string_slice(&visiting)
    for file in root_files {
        for top in file.forms {
            alias, import_path, is_import :=
                source_import_alias_and_path(top.form, file.path)
            if !is_import {
                continue
            }
            resolved, err_resolve, ok_resolve :=
                resolve_source_import_path(file.path, import_path)
            delete(import_path)
            if !ok_resolve {
                delete(alias)
                return scope, err_resolve, false
            }
            imported_scope, imported_matched, imported_err, imported_ok :=
                find_repl_package_scope_imported(
                    resolved,
                    alias,
                    target_path,
                    &visiting,
                )
            delete(alias)
            delete(resolved)
            if imported_matched || !imported_ok {
                return imported_scope, imported_err, imported_ok
            }
        }
    }
    return scope, Compile_Error{
        message = fmt.tprintf(
            "source file is not part of the active REPL package graph: %s",
            target_path,
        ),
    }, false
}

repl_filter_concrete_proc_names :: proc(
    names: ^[dynamic]string,
    program: AST_Program,
) {
    for i := len(names^)-1; i >= 0; i -= 1 {
        concrete := false
        for &decl in program.decls {
            if decl.kind == .Proc &&
               decl.proc_decl.name == names^[i] {
                concrete = repl_proc_is_concrete(&decl.proc_decl)
                break
            }
        }
        if !concrete {
            unordered_remove(names, i)
        }
    }
}

repl_filter_runtime_value_names :: proc(
    names: ^[dynamic]string,
    program: AST_Program,
) {
    for i := len(names^)-1; i >= 0; i -= 1 {
        for &decl in program.decls {
            if decl.kind != .Const ||
               decl.const_decl.name != names^[i] {
                continue
            }
            if decl.const_decl.is_type_alias ||
               decl.const_decl.is_overload {
                unordered_remove(names, i)
            }
            break
        }
    }
}

Repl_Batch :: struct {
    eval_form:   CST_Form,
    definitions: [dynamic]CST_Form,
    has_runtime: bool,
}

REPL_IGNORE_RESULT_HEAD :: "kvist-prim-ignore-repl-result"

repl_ignore_result_form :: proc(form: CST_Form) -> CST_Form {
    return make_list_form(
        {
            make_symbol_form(REPL_IGNORE_RESULT_HEAD, form.span),
            form,
        },
        form.span,
    )
}

repl_ignore_result_inner :: proc(form: CST_Form) -> (CST_Form, bool) {
    if form.kind != .List || len(form.items) != 2 ||
       !is_symbol(form.items[0], REPL_IGNORE_RESULT_HEAD) {
        return CST_Form{}, false
    }
    return form.items[1], true
}

repl_synthetic_batch_do :: proc(form: CST_Form) -> bool {
    if form.kind != .List || len(form.items) < 3 ||
       !is_symbol(form.items[0], "do") {
        return false
    }
    for item in form.items[1:len(form.items)-1] {
        if _, ok := repl_ignore_result_inner(item); !ok {
            return false
        }
    }
    return true
}

read_repl_batch :: proc(source: string) -> (batch: Repl_Batch, err: Compile_Error, ok: bool) {
    forms, err_forms, ok_forms := read_top_forms_with_origin(source, .Eval)
    if !ok_forms {
        return batch, err_forms, false
    }
    if len(forms) == 0 {
        return batch, Compile_Error{
            message = "REPL evaluation expects at least one form",
            span = Span{source = .Eval},
        }, false
    }
    err_surface, ok_surface := validate_surface_internal_call_names(forms[:])
    if !ok_surface {
        return batch, err_surface, false
    }
    err_slash, ok_slash := validate_surface_package_slash_access(forms[:])
    if !ok_slash {
        return batch, err_slash, false
    }

    runtime_forms: [dynamic]CST_Form
    batch_span := Span{
        start = forms[0].form.span.start,
        end = forms[len(forms)-1].form.span.end,
        source = .Eval,
    }
    for top_form in forms {
        head := eval_form_head(top_form.form)
        if head == "package" {
            // The controller already owns the package context. Accepting its
            // declaration makes top-level and whole-buffer editor evaluation
            // behave like ordinary source evaluation without emitting a
            // second native package declaration into the generation.
            _, err_package, ok_package :=
                parse_decl(CST_Top_Form{form = top_form.form})
            if !ok_package {
                return batch, err_package, false
            }
            continue
        }
        if head == "import" {
            // Imports are carried separately into the generation package and
            // are otherwise skipped by declaration emission. Validate the
            // complete surface here so an unsupported option combination
            // cannot appear to commit successfully while contributing no
            // alias or referred names.
            _, err_import, ok_import :=
                parse_decl(CST_Top_Form{form = top_form.form})
            if !ok_import {
                return batch, err_import, false
            }
        }
        // At package scope `(odin "...")` contributes a raw Odin declaration.
        // A submitted REPL form, however, occupies an expression/statement
        // position and should retain the ordinary Kvist escape semantics.
        // Keeping this decision at the REPL boundary lets clients submit the
        // explicit escape without accepting bare Odin source at the prompt.
        if eval_head_is_decl(head) && head != "odin" {
            if head != "defn" && head != "def" && head != "defvar" &&
               head != "defstruct" && head != "defenum" && head != "defunion" &&
               head != "deftransform" && head != "defiter" &&
               head != "defmacro" && head != "import" {
                return batch, Compile_Error{
                    message = "this REPL milestone supports explicit-alias imports, concrete defn, retainable typed def/defvar, nominal type declarations, deftransform, defiter, and defmacro",
                    span = top_form.form.span,
                }, false
            }
            append(&batch.definitions, top_form.form)
        } else {
            append(&runtime_forms, top_form.form)
        }
    }
    if len(runtime_forms) == 0 {
        batch.eval_form = CST_Form{
            kind = .Nil,
            text = "nil",
            span = batch_span,
        }
        return batch, {}, true
    }
    batch.has_runtime = true
    if len(runtime_forms) == 1 {
        batch.eval_form = runtime_forms[0]
        return batch, {}, true
    }
    items := make([dynamic]CST_Form, 0, len(runtime_forms)+1)
    append(&items, CST_Form{
        kind = .Symbol,
        text = "do",
        span = batch_span,
    })
    for form, idx in runtime_forms {
        if idx < len(runtime_forms)-1 {
            append(&items, repl_ignore_result_form(form))
        } else {
            append(&items, form)
        }
    }
    batch.eval_form = CST_Form{
        kind = .List,
        items = items,
        span = batch_span,
    }
    return batch, {}, true
}

// Rewrite a submitted imported-package batch into the root compilation's
// stable internal symbol space. Root-package submissions remain byte-for-byte
// unchanged so their diagnostic offsets and dynamically submitted imports keep
// the existing behavior.
repl_normalize_source_path :: proc(
    root_path,
    source,
    source_path: string,
) -> (normalized: string, err: Compile_Error, ok: bool) {
    if source_path == "" || !os.exists(source_path) ||
       paths_refer_to_same_file(root_path, source_path) {
        return strings.clone(source), Compile_Error{}, true
    }
    result_allocator := context.allocator
    old_allocator := result_allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    scope, err_scope, ok_scope :=
        find_repl_package_scope(root_path, source_path)
    if !ok_scope {
        context.allocator = old_allocator
        return "", clone_compile_error(err_scope, result_allocator), false
    }
    if scope.prefix == "" {
        normalized = strings.clone(source, result_allocator)
        context.allocator = old_allocator
        return normalized, Compile_Error{}, true
    }
    batch, err_batch, ok_batch := read_repl_batch(source)
    if !ok_batch {
        context.allocator = old_allocator
        return "", clone_compile_error(err_batch, result_allocator), false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for definition in batch.definitions {
        if eval_form_head(definition) == "import" {
            // The package graph has already loaded imports from this source
            // package. Their aliases are represented by scope.aliases below.
            continue
        }
        rewritten, err_rewrite, ok_rewrite := rewrite_top_form(
            CST_Top_Form{form = definition},
            scope.locals[:],
            scope.private_macros[:],
            scope.aliases[:],
            scope.prefix,
        )
        if !ok_rewrite {
            context.allocator = old_allocator
            return "", clone_compile_error(err_rewrite, result_allocator), false
        }
        text := macro_form_text(rewritten.form)
        strings.write_string(&builder, text)
        strings.write_byte(&builder, '\n')
        delete(text)
    }
    rewritten_eval, err_eval, ok_eval := rewrite_form_symbols(
        batch.eval_form,
        scope.locals[:],
        scope.aliases[:],
        scope.prefix,
    )
    if !ok_eval {
        context.allocator = old_allocator
        return "", clone_compile_error(err_eval, result_allocator), false
    }
    if repl_synthetic_batch_do(rewritten_eval) {
        for item, idx in rewritten_eval.items[1:] {
            normalized_item := item
            if inner, ignored := repl_ignore_result_inner(item); ignored {
                normalized_item = inner
            }
            eval_text := macro_form_text(normalized_item)
            strings.write_string(&builder, eval_text)
            delete(eval_text)
            if idx < len(rewritten_eval.items)-2 {
                strings.write_byte(&builder, '\n')
            }
        }
    } else {
        eval_text := macro_form_text(rewritten_eval)
        strings.write_string(&builder, eval_text)
        delete(eval_text)
    }
    normalized = strings.clone(strings.to_string(builder), result_allocator)
    context.allocator = old_allocator
    return normalized, Compile_Error{}, true
}

repl_persistent_definitions_source :: proc(source: string) -> string {
    forms, _, ok := read_top_forms_with_origin(source, .Eval)
    defer delete_borrowed_cst_top_form_slice(&forms)
    if !ok {
        return strings.clone("")
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for top in forms {
        name, is_defn := repl_form_decl_name(top.form)
        delete(name)
        if is_defn {
            if top.form.span.start < 0 ||
               top.form.span.end > len(source) ||
               top.form.span.start >= top.form.span.end {
                continue
            }
            strings.write_string(&builder, source[top.form.span.start:top.form.span.end])
            strings.write_byte(&builder, '\n')
        } else if eval_head_is_decl(eval_form_head(top.form)) {
            return strings.clone("")
        }
    }
    return strings.clone(strings.to_string(builder))
}

repl_persistent_imports_source :: proc(source: string) -> string {
    forms, _, ok := read_top_forms_with_origin(source, .Eval)
    defer delete_borrowed_cst_top_form_slice(&forms)
    if !ok {
        return strings.clone("")
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for top in forms {
        if eval_form_head(top.form) != "import" {
            continue
        }
        if top.form.span.start < 0 ||
           top.form.span.end > len(source) ||
           top.form.span.start >= top.form.span.end {
            continue
        }
        strings.write_string(
            &builder,
            source[top.form.span.start:top.form.span.end],
        )
        strings.write_byte(&builder, '\n')
    }
    return strings.clone(strings.to_string(builder))
}

repl_without_definition_source :: proc(source, logical_name: string) -> string {
    forms, _, ok := read_top_forms_with_origin(source, .Eval)
    defer delete_borrowed_cst_top_form_slice(&forms)
    if !ok {
        return strings.clone(source)
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for top in forms {
        form := top.form
        name := ""
        if form.kind == .List &&
           len(form.items) >= 2 &&
           form.items[1].kind == .Symbol {
            name = form.items[1].text
            if len(name) > 0 && name[len(name)-1] == ':' {
                name = name[:len(name)-1]
            }
        }
        if name == logical_name {
            continue
        }
        if form.span.start < 0 ||
           form.span.end > len(source) ||
           form.span.start >= form.span.end {
            continue
        }
        strings.write_string(&builder, source[form.span.start:form.span.end])
        strings.write_byte(&builder, '\n')
    }
    return strings.clone(strings.to_string(builder))
}

Repl_Definition_Info :: struct {
    name: string,
    kind: string,
    source: string,
    start: int,
    end: int,
}

repl_definition_info_slice_delete :: proc(infos: []Repl_Definition_Info) {
    for info in infos {
        delete(info.name)
        delete(info.kind)
        delete(info.source)
    }
    delete(infos)
}

repl_definition_infos :: proc(source: string) -> [dynamic]Repl_Definition_Info {
    infos: [dynamic]Repl_Definition_Info
    forms, _, ok := read_top_forms_with_origin(source, .Eval)
    defer delete_borrowed_cst_top_form_slice(&forms)
    if !ok {
        return infos
    }
    for top in forms {
        form := top.form
        mapped_name, supported := repl_form_decl_name(form)
        delete(mapped_name)
        if !supported {
            continue
        }
        if eval_form_head(form) == "import" {
            continue
        }
        name := form.items[1].text
        if len(name) > 0 && name[len(name)-1] == ':' {
            name = name[:len(name)-1]
        }
        append(&infos, Repl_Definition_Info{
            name = strings.clone(name),
            kind = strings.clone(form.items[0].text),
            source = strings.clone(source[form.span.start:form.span.end]),
            start = form.span.start,
            end = form.span.end,
        })
    }
    return infos
}

repl_collect_definition_dependencies :: proc(
    form: CST_Form,
    candidates: []string,
    dependencies: ^[dynamic]string,
) {
    if form.kind == .Symbol {
        for candidate in candidates {
            if form.text != candidate {
                continue
            }
            already_added := false
            for dependency in dependencies {
                if dependency == candidate {
                    already_added = true
                    break
                }
            }
            if !already_added {
                append(dependencies, strings.clone(candidate))
            }
            return
        }
    }
    for item in form.items {
        repl_collect_definition_dependencies(item, candidates, dependencies)
    }
}

repl_definition_dependencies :: proc(source: string, candidates: []string) -> [dynamic]string {
    dependencies: [dynamic]string
    forms, _, ok := read_top_forms_with_origin(source, .Eval)
    defer delete_borrowed_cst_top_form_slice(&forms)
    if !ok {
        return dependencies
    }
    for top in forms {
        form := top.form
        if form.kind != .List || len(form.items) < 2 {
            continue
        }
        for item in form.items[2:] {
            repl_collect_definition_dependencies(item, candidates, &dependencies)
        }
    }
    return dependencies
}

repl_string_slice_delete :: proc(values: []string) {
    for value in values {
        delete(value)
    }
    delete(values)
}

repl_registered_abi :: proc(emitted_source, logical_name: string) -> string {
    mapped_name := map_name(logical_name)
    defer delete(mapped_name)
    needle := fmt.tprintf("host.register_proc(host.ctx, %q, ", mapped_name)
    offset := strings.index(emitted_source, needle)
    if offset < 0 {
        needle =
            fmt.tprintf(
                "kvist_repl_definition_abi_%s :: ",
                mapped_name,
            )
        offset = strings.index(emitted_source, needle)
        if offset < 0 {
            return strings.clone("")
        }
    }
    rest := emitted_source[offset+len(needle):]
    if len(rest) == 0 || rest[0] != '"' {
        return strings.clone("")
    }
    escaped := false
    for i := 1; i < len(rest); i += 1 {
        if escaped {
            escaped = false
            continue
        }
        if rest[i] == '\\' {
            escaped = true
            continue
        }
        if rest[i] == '"' {
            return strings.clone(rest[1:i])
        }
    }
    return strings.clone("")
}

repl_registered_result_abi :: proc(emitted_source: string) -> string {
    needle := `host.register_result(host.ctx, "`
    offset := strings.index(emitted_source, needle)
    if offset < 0 {
        return strings.clone("")
    }
    rest := emitted_source[offset+len(needle):]
    escaped := false
    for i := 0; i < len(rest); i += 1 {
        if escaped {
            escaped = false
            continue
        }
        if rest[i] == '\\' {
            escaped = true
            continue
        }
        if rest[i] == '"' {
            return strings.clone(rest[:i])
        }
    }
    return strings.clone("")
}

repl_inspection_result_abi :: proc(emitted_source: string) -> string {
    needle := `kvist_repl_inspection_abi :: "`
    offset := strings.index(emitted_source, needle)
    if offset < 0 {
        return strings.clone("")
    }
    rest := emitted_source[offset+len(needle):]
    escaped := false
    for i := 0; i < len(rest); i += 1 {
        if escaped {
            escaped = false
            continue
        }
        if rest[i] == '\\' {
            escaped = true
            continue
        }
        if rest[i] == '"' {
            return strings.clone(rest[:i])
        }
    }
    return strings.clone("")
}

repl_result_type_from_abi :: proc(abi: string) -> string {
    prefix := "value:"
    if !strings.has_prefix(abi, prefix) {
        return strings.clone("")
    }
    result_ty := abi[len(prefix):]
    if layout := strings.index(result_ty, "|"); layout >= 0 {
        result_ty = result_ty[:layout]
    }
    if suffix := ":owned"; strings.has_suffix(result_ty, suffix) {
        result_ty = result_ty[:len(result_ty)-len(suffix)]
    } else if suffix := ":borrowed"; strings.has_suffix(result_ty, suffix) {
        result_ty = result_ty[:len(result_ty)-len(suffix)]
    }
    return strings.clone(result_ty)
}

// The returned name is owned by context.allocator. Compilation normally calls
// this inside its temporary arena; standalone REPL source helpers delete it.
repl_form_decl_name :: proc(form: CST_Form) -> (name: string, ok: bool) {
    if form.kind != .List ||
       len(form.items) < 2 ||
       form.items[0].kind != .Symbol {
        return "", false
    }
    if form.items[0].text == "import" {
        if len(form.items) == 3 &&
           form.items[1].kind == .Symbol &&
           form.items[2].kind == .String {
            return strings.clone(form.items[1].text), true
        }
        if as_index, has_as := source_import_as_index(form); has_as {
            return strings.clone(form.items[as_index].text), true
        }
        if source_import_form_has_refer(form) {
            // The path is the replacement key for later :refer selections
            // from the same package.
            return strings.clone(form.items[1].text), true
        }
        return "", false
    }
    if (form.items[0].text != "defn" &&
        form.items[0].text != "def" &&
        form.items[0].text != "defvar" &&
        form.items[0].text != "defstruct" &&
        form.items[0].text != "defenum" &&
        form.items[0].text != "defunion" &&
        form.items[0].text != "deftransform" &&
        form.items[0].text != "defiter" &&
        form.items[0].text != "defmacro") ||
       form.items[1].kind != .Symbol {
        return "", false
    }
    text := form.items[1].text
    if len(text) > 0 && text[len(text)-1] == ':' {
        text = text[:len(text)-1]
    }
    return map_name(text), true
}

repl_session_forms :: proc(source: string) -> (forms: [dynamic]CST_Top_Form, err: Compile_Error, ok: bool) {
    if strings.trim_space(source) == "" {
        return forms, {}, true
    }
    parsed, err_parsed, ok_parsed := read_top_forms_with_origin(source, .Eval)
    if !ok_parsed {
        return forms, err_parsed, false
    }
    for top in parsed {
        name, is_defn := repl_form_decl_name(top.form)
        delete(name)
        if !is_defn {
            return forms, Compile_Error{
                message = "REPL session history contains an unsupported declaration",
                span = top.form.span,
            }, false
        }
        append(&forms, top)
    }
    return forms, {}, true
}

repl_dedupe_session_decls :: proc(program: AST_Program) -> AST_Program {
    retained_reversed: [dynamic]AST_Decl
    seen := make(map[string]bool)
    for i := len(program.decls)-1; i >= 0; i -= 1 {
        decl := program.decls[i]
        if decl.kind == .Proc || decl.kind == .Const || decl.kind == .Var ||
           decl.kind == .Struct || decl.kind == .Enum || decl.kind == .Union ||
           decl.kind == .Transform || decl.kind == .Source {
            name := decl.proc_decl.name if decl.kind == .Proc else
                    (decl.const_decl.name if decl.kind == .Const else
                     (decl.var_decl.name if decl.kind == .Var else
                      (decl.struct_decl.name if decl.kind == .Struct else
                       (decl.enum_decl.name if decl.kind == .Enum else
                        (decl.union_decl.name if decl.kind == .Union else
                         (decl.transform_decl.name if decl.kind == .Transform else decl.source_decl.name))))))
            if seen[name] {
                continue
            }
            seen[name] = true
        }
        append(&retained_reversed, decl)
    }
    deduped := AST_Program{}
    for i := len(retained_reversed)-1; i >= 0; i -= 1 {
        append(&deduped.decls, retained_reversed[i])
    }
    return deduped
}

repl_type_is_fixed_array :: proc(ty: string) -> (elem: string, ok: bool) {
    if len(ty) < 4 || ty[0] != '[' || ty[1] == ']' {
        return "", false
    }
    close := strings.index(ty, "]")
    if close <= 1 || close+1 >= len(ty) {
        return "", false
    }
    for ch in ty[1:close] {
        if ch < '0' || ch > '9' {
            return "", false
        }
    }
    return ty[close+1:], true
}

repl_storage_type_supported :: proc(
    program: IR_Program,
    ty: string,
    depth := 0,
    allow_dynamic_array := false,
    allow_slice := false,
) -> bool {
    if depth > 16 || ty == "" {
        return false
    }
    if ty == "Data" {
        for decl in program.decls {
            if decl.kind == .Struct && decl.struct_decl.name == "Data" {
                return false
            }
        }
        return true
    }
    if repl_value_type_supported(ty) {
        return true
    }
    if allow_slice &&
       strings.has_prefix(ty, "[]") &&
       len(ty) > 2 {
        return allow_dynamic_array &&
               repl_storage_type_supported(
                   program,
                   ty[2:],
                   depth+1,
                   allow_dynamic_array,
                   allow_slice,
               )
    }
    if elem, is_dynamic := dynamic_array_element_type(ty); is_dynamic {
        return allow_dynamic_array &&
               repl_storage_type_supported(
                   program,
                   elem,
                   depth+1,
                   allow_dynamic_array,
                   allow_slice,
               )
    }
    if key_ty, value_ty, is_map := map_type_parts(ty); is_map {
        return allow_dynamic_array &&
               repl_storage_type_supported(
                   program,
                   key_ty,
                   depth+1,
                   allow_dynamic_array,
                   allow_slice,
               ) &&
               repl_storage_type_supported(
                   program,
                   value_ty,
                   depth+1,
                   allow_dynamic_array,
                   allow_slice,
               )
    }
    if elem, fixed := repl_type_is_fixed_array(ty); fixed {
        if elem == "Data" {
            return false
        }
        return repl_storage_type_supported(
            program,
            elem,
            depth+1,
            allow_dynamic_array,
            allow_slice,
        )
    }
    for decl in program.decls {
        if decl.kind == .Enum && decl.enum_decl.name == ty {
            return true
        }
        if decl.kind == .Struct && decl.struct_decl.name == ty {
            for field in decl.struct_decl.fields {
                if !repl_storage_type_supported(
                    program,
                    field.ty,
                    depth+1,
                    allow_dynamic_array,
                    allow_slice,
                ) {
                    return false
                }
            }
            return true
        }
        if decl.kind == .Union && decl.union_decl.name == ty {
            for variant in decl.union_decl.variants {
                if !repl_storage_type_supported(
                    program,
                    variant.ty,
                    depth+1,
                    allow_dynamic_array,
                    false,
                ) {
                    return false
                }
            }
            return true
        }
        if decl.kind == .Const &&
           decl.const_decl.is_type_alias &&
           decl.const_decl.name == ty {
            return repl_storage_type_supported(
                program,
                decl.const_decl.type_alias,
                depth+1,
                allow_dynamic_array,
                false,
            )
        }
    }
    return false
}

repl_storage_type_requires_lifecycle :: proc(
    program: IR_Program,
    ty: string,
    depth := 0,
) -> bool {
    if depth > 16 || ty == "" {
        return false
    }
    trimmed := strings.trim_space(ty)
    if strings.has_prefix(trimmed, "^") ||
       trimmed == "rawptr" ||
       trimmed == "cstring" {
        return true
    }
    distinct_prefix := "distinct "
    if strings.has_prefix(trimmed, distinct_prefix) {
        return repl_storage_type_requires_lifecycle(
            program,
            strings.trim_space(trimmed[len(distinct_prefix):]),
            depth+1,
        )
    }
    if strings.has_prefix(trimmed, "[]") && len(trimmed) > 2 {
        return repl_storage_type_requires_lifecycle(
            program,
            trimmed[2:],
            depth+1,
        )
    }
    if elem, is_dynamic := dynamic_array_element_type(trimmed); is_dynamic {
        return repl_storage_type_requires_lifecycle(
            program,
            elem,
            depth+1,
        )
    }
    if key_ty, value_ty, map_type := map_type_parts(trimmed); map_type {
        return repl_storage_type_requires_lifecycle(
                   program,
                   key_ty,
                   depth+1,
               ) ||
               repl_storage_type_requires_lifecycle(
                   program,
                   value_ty,
                   depth+1,
               )
    }
    if elem, fixed := repl_type_is_fixed_array(trimmed); fixed {
        return repl_storage_type_requires_lifecycle(
            program,
            elem,
            depth+1,
        )
    }
    for decl in program.decls {
        if decl.kind == .Struct && decl.struct_decl.name == trimmed {
            for field in decl.struct_decl.fields {
                if repl_storage_type_requires_lifecycle(
                    program,
                    field.ty,
                    depth+1,
                ) {
                    return true
                }
            }
            return false
        }
        if decl.kind == .Union && decl.union_decl.name == trimmed {
            for variant in decl.union_decl.variants {
                if repl_storage_type_requires_lifecycle(
                    program,
                    variant.ty,
                    depth+1,
                ) {
                    return true
                }
            }
            return false
        }
        if decl.kind == .Const &&
           decl.const_decl.is_type_alias &&
           decl.const_decl.name == trimmed {
            return repl_storage_type_requires_lifecycle(
                program,
                decl.const_decl.type_alias,
                depth+1,
            )
        }
    }
    return false
}

rewrite_repl_stream_output_form :: proc(form: ^CST_Form) {
    if form == nil {
        return
    }
    if form.kind == .List &&
       len(form.items) > 0 &&
       form.items[0].kind == .Symbol {
        if form.items[0].text == "quote" {
            return
        }
        if form.items[0].text == "fmt.println" {
            form.items[0].text =
                strings.clone("kvist_repl_println")
        }
    }
    if form.kind == .Symbol {
        return
    }
    for &item in form.items {
        rewrite_repl_stream_output_form(&item)
    }
}
