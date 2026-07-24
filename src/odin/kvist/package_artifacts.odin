// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

IR_Package_Group :: struct {
    id:          string,
    source_root: string,
    is_root:     bool,
    decls:       [dynamic]IR_Decl,
    emitted:     Emit_Result,
    symbols:     [dynamic]string,
    source_hash: u64,
    features:    Emitter_Features,
    cache_hit:   bool,
}

PACKAGE_ARTIFACT_CACHE_VERSION :: 2

Cached_IR_Package_Group :: struct {
    version: int,
    emitted: Emit_Result,
    features: Emitter_Features,
}

Package_Dependency_Record :: struct {
    id:           string,
    dependencies: [dynamic]string,
}

Package_Dependency_Manifest :: struct {
    version: int,
    root:    string,
    packages: [dynamic]Package_Dependency_Record,
}

package_artifact_hash_update :: proc(hash: u64, bytes: []byte) -> u64 {
    out := hash
    for value in bytes {
        out = (out ~ u64(value)) * 1099511628211
    }
    return out
}

package_artifact_hash_text :: proc(hash: u64, text: string) -> u64 {
    next := package_artifact_hash_update(hash, transmute([]byte)text)
    return package_artifact_hash_update(next, []byte{0})
}

package_artifact_hash_cst :: proc(hash: u64, form: CST_Form) -> u64 {
    next := package_artifact_hash_text(hash, fmt.tprintf("%d", form.kind))
    next = package_artifact_hash_text(next, form.text)
    next = package_artifact_hash_text(next, form.source_text)
    for item in form.items {
        next = package_artifact_hash_cst(next, item)
    }
    return next
}

package_artifact_hash_param :: proc(hash: u64, param: Param) -> u64 {
    next := package_artifact_hash_text(hash, param.name)
    next = package_artifact_hash_text(next, param.ty)
    next = package_artifact_hash_text(next, fmt.tprintf("%d", param.ownership))
    next = package_artifact_hash_text(next, param.owner_flag)
    next = package_artifact_hash_text(next, fmt.tprintf("%t", param.has_default))
    if param.has_default {
        next = package_artifact_hash_cst(next, param.default_value)
    }
    return next
}

package_decls_interface_hash :: proc(decls: []IR_Decl) -> u64 {
    hash: u64 = 14695981039346656037
    for decl in decls {
        hash = package_artifact_hash_text(hash, fmt.tprintf("%d", decl.kind))
        #partial switch decl.kind {
        case .Const:
            hash = package_artifact_hash_text(hash, decl.const_decl.name)
            hash = package_artifact_hash_text(hash, decl.const_decl.ty)
            hash = package_artifact_hash_text(hash, decl.const_decl.type_alias)
            hash = package_artifact_hash_text(hash, fmt.tprintf("%d", decl.const_decl.init_kind))
            hash = package_artifact_hash_cst(hash, decl.const_decl.value)
        case .Var:
            hash = package_artifact_hash_text(hash, decl.var_decl.name)
            hash = package_artifact_hash_text(hash, decl.var_decl.ty)
        case .Struct:
            hash = package_artifact_hash_text(hash, decl.struct_decl.name)
            for field in decl.struct_decl.fields {
                hash = package_artifact_hash_text(hash, field.name)
                hash = package_artifact_hash_text(hash, field.ty)
                hash = package_artifact_hash_text(
                    hash,
                    fmt.tprintf(
                        "%t:%t:%t",
                        field.is_using,
                        field.owns_string,
                        field.owns_dynamic_array,
                    ),
                )
            }
        case .Enum:
            hash = package_artifact_hash_text(hash, decl.enum_decl.name)
            for variant in decl.enum_decl.variants {
                hash = package_artifact_hash_text(hash, variant.name)
                if variant.has_value {
                    hash = package_artifact_hash_cst(hash, variant.value)
                }
            }
        case .Union:
            hash = package_artifact_hash_text(hash, decl.union_decl.name)
            for variant in decl.union_decl.variants {
                hash = package_artifact_hash_text(hash, variant.name)
                hash = package_artifact_hash_text(hash, variant.ty)
            }
        case .Proc:
            proc_decl := decl.proc_decl
            hash = package_artifact_hash_text(hash, proc_decl.name)
            hash = package_artifact_hash_text(hash, proc_decl.calling_convention)
            hash = package_artifact_hash_text(
                hash,
                fmt.tprintf("%t:%t", proc_decl.owns_result, proc_decl.borrows_result),
            )
            for param in proc_decl.params {
                hash = package_artifact_hash_param(hash, param)
            }
            hash = package_artifact_hash_text(hash, fmt.tprintf("%d", proc_decl.returns.kind))
            hash = package_artifact_hash_text(hash, proc_decl.returns.single_ty)
            hash = package_artifact_hash_text(
                hash,
                fmt.tprintf("%d", proc_decl.returns.single_ownership),
            )
            for named in proc_decl.returns.named {
                hash = package_artifact_hash_text(hash, named.name)
                hash = package_artifact_hash_text(hash, named.ty)
                hash = package_artifact_hash_text(hash, fmt.tprintf("%d", named.ownership))
            }
            for constraint in proc_decl.where_constraints {
                hash = package_artifact_hash_cst(hash, constraint)
            }
        case .Source:
            hash = package_artifact_hash_text(hash, decl.source_decl.name)
            hash = package_artifact_hash_text(hash, decl.source_decl.state_ty)
            hash = package_artifact_hash_text(hash, decl.source_decl.item_ty)
            for param in decl.source_decl.params {
                hash = package_artifact_hash_param(hash, param)
            }
        case .Transform:
            hash = package_artifact_hash_text(hash, decl.transform_decl.name)
            hash = package_artifact_hash_cst(hash, decl.transform_decl.spec)
        case .Raw:
            hash = package_artifact_hash_text(hash, decl.raw_text)
        case:
        }
    }
    return hash
}

package_group_source_hash :: proc(group: IR_Package_Group) -> (hash: u64, ok: bool) {
    hash = 14695981039346656037
    paths: [dynamic]string
    defer delete(paths)
    for decl in group.decls {
        if decl.source_path == "" || contains_text(paths[:], decl.source_path) {
            continue
        }
        append(&paths, decl.source_path)
        bytes, read_err := os.read_entire_file_from_path(decl.source_path, context.allocator)
        if read_err != nil {
            return 0, false
        }
        hash = package_artifact_hash_text(hash, decl.source_path)
        hash = package_artifact_hash_update(hash, bytes)
        delete(bytes)
    }
    return hash, true
}

package_group_cache_path :: proc(
    cache_dir, group_id: string,
    source_hash, interface_hash: u64,
) -> (string, bool) {
    if cache_dir == "" {
        return "", false
    }
    name := fmt.tprintf(
        "%s-%016x-%016x.json",
        group_id,
        source_hash,
        interface_hash,
    )
    path, path_err := os.join_path({cache_dir, name}, context.allocator)
    return path, path_err == nil
}

delete_cached_emitter_features :: proc(features: ^Emitter_Features) {
    delete(features.thread_starts)
    delete(features.thread_detaches)
    delete(features.data_literals)
    features^ = {}
}

load_cached_package_group :: proc(path: string) -> (Emit_Result, Emitter_Features, bool) {
    bytes, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return {}, {}, false
    }
    defer delete(bytes)
    cached := Cached_IR_Package_Group{}
    if json.unmarshal(bytes, &cached) != nil ||
       cached.version != PACKAGE_ARTIFACT_CACHE_VERSION {
        delete(cached.emitted.output)
        source_map_slice_delete(cached.emitted.source_map)
        compile_warning_slice_delete(cached.emitted.warnings)
        delete_cached_emitter_features(&cached.features)
        return {}, {}, false
    }
    now := time.now()
    _ = os.change_times(path, now, now)
    return cached.emitted, cached.features, true
}

publish_package_cache_bytes :: proc(path: string, bytes: []byte) {
    parent, _ := os.split_path(path)
    if parent == "" {
        return
    }
    temp_dir, temp_err := os.make_directory_temp(
        parent,
        ".kvist-package-*",
        context.allocator,
    )
    if temp_err != nil {
        return
    }
    defer {
        _ = os.remove_all(temp_dir)
        delete(temp_dir)
    }
    temp_path, join_err := os.join_path(
        {temp_dir, "artifact.json"},
        context.allocator,
    )
    if join_err != nil {
        return
    }
    defer delete(temp_path)
    if os.write_entire_file(temp_path, bytes) == nil {
        _ = os.rename(temp_path, path)
    }
}

publish_cached_package_group :: proc(
    path: string,
    emitted: Emit_Result,
    features: Emitter_Features,
) {
    bytes, marshal_err := json.marshal(Cached_IR_Package_Group{
        version = PACKAGE_ARTIFACT_CACHE_VERSION,
        emitted = emitted,
        features = features,
    })
    if marshal_err != nil {
        return
    }
    defer delete(bytes)
    publish_package_cache_bytes(path, bytes)
}

delete_package_dependency_manifest :: proc(manifest: ^Package_Dependency_Manifest) {
    delete(manifest.root)
    for &record in manifest.packages {
        delete(record.id)
        delete_string_slice(&record.dependencies)
    }
    delete(manifest.packages)
    manifest^ = {}
}

package_dependency_manifest_path :: proc(
    cache_dir, root_path: string,
) -> (string, bool) {
    if cache_dir == "" {
        return "", false
    }
    absolute, absolute_err := os.get_absolute_path(root_path, context.allocator)
    if absolute_err != nil {
        return "", false
    }
    defer delete(absolute)
    root_hash := package_artifact_hash_update(
        14695981039346656037,
        transmute([]byte)absolute,
    )
    name := fmt.tprintf("graph-%016x.json", root_hash)
    path, path_err := os.join_path({cache_dir, name}, context.allocator)
    return path, path_err == nil
}

load_package_dependency_manifest :: proc(
    path, root_path: string,
) -> (manifest: Package_Dependency_Manifest, ok: bool) {
    bytes, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return manifest, false
    }
    defer delete(bytes)
    if json.unmarshal(bytes, &manifest) != nil ||
       manifest.version != PACKAGE_ARTIFACT_CACHE_VERSION {
        delete_package_dependency_manifest(&manifest)
        return manifest, false
    }
    now := time.now()
    _ = os.change_times(path, now, now)
    return manifest, true
}

package_manifest_dependencies :: proc(
    manifest: Package_Dependency_Manifest,
    group_id: string,
) -> []string {
    for record in manifest.packages {
        if record.id == group_id {
            return record.dependencies[:]
        }
    }
    return nil
}

package_dependency_interface_hash :: proc(
    dependencies: []string,
    interfaces: map[string]u64,
) -> u64 {
    hash: u64 = 14695981039346656037
    sorted: [dynamic]string
    defer delete(sorted)
    append(&sorted, ..dependencies)
    slice.sort_by(sorted[:], proc(a, b: string) -> bool {
        return a < b
    })
    for dependency in sorted {
        hash = package_artifact_hash_text(hash, dependency)
        if dependency_hash, found := interfaces[dependency]; found {
            text := fmt.tprintf("%016x", dependency_hash)
            hash = package_artifact_hash_text(hash, text)
        }
    }
    return hash
}

publish_package_dependency_manifest :: proc(
    path, root_path: string,
    records: []Package_Dependency_Record,
) {
    manifest := Package_Dependency_Manifest{
        version = PACKAGE_ARTIFACT_CACHE_VERSION,
        root = root_path,
    }
    for record in records {
        cloned := Package_Dependency_Record{id = strings.clone(record.id)}
        for dependency in record.dependencies {
            append(&cloned.dependencies, strings.clone(dependency))
        }
        append(&manifest.packages, cloned)
    }
    defer delete_package_dependency_manifest(&manifest)
    bytes, marshal_err := json.marshal(manifest)
    if marshal_err == nil {
        defer delete(bytes)
        publish_package_cache_bytes(path, bytes)
    }
}

package_artifact_id :: proc(path: string) -> string {
    hash := package_artifact_hash_update(14695981039346656037, transmute([]byte)path)
    return strings.clone(fmt.tprintf("kvp_%016x", hash))
}

canonical_decl_source_root :: proc(decl: IR_Decl, root_dir: string) -> string {
    if decl.source_path == "" {
        return strings.clone(root_dir)
    }
    dir, _ := os.split_path(decl.source_path)
    if dir == "" {
        dir = "."
    }
    absolute, absolute_err := os.get_absolute_path(dir, context.allocator)
    if absolute_err != nil {
        return strings.clone(dir)
    }
    return absolute
}

delete_ir_package_groups :: proc(groups: ^[dynamic]IR_Package_Group) {
    for &group in groups^ {
        delete(group.id)
        delete(group.source_root)
        delete(group.decls)
        delete(group.emitted.output)
        source_map_slice_delete(group.emitted.source_map)
        compile_warning_slice_delete(group.emitted.warnings)
        delete_string_slice(&group.symbols)
        delete_cached_emitter_features(&group.features)
    }
    delete(groups^)
    groups^ = nil
}

find_or_add_package_group :: proc(
    groups: ^[dynamic]IR_Package_Group,
    source_root, root_dir: string,
) -> ^IR_Package_Group {
    for &group in groups^ {
        if group.source_root == source_root {
            return &group
        }
    }
    is_root := source_root == root_dir
    id := strings.clone("root")
    if !is_root {
        delete(id)
        id = package_artifact_id(source_root)
    }
    append(groups, IR_Package_Group{
        id = id,
        source_root = strings.clone(source_root),
        is_root = is_root,
    })
    return &groups^[len(groups^)-1]
}

group_ir_decls_by_package :: proc(program: IR_Program, root_path: string) -> ([dynamic]IR_Package_Group, bool) {
    root_absolute, root_err := os.get_absolute_path(root_path, context.allocator)
    if root_err != nil {
        return nil, false
    }
    defer delete(root_absolute)
    root_dir, _ := os.split_path(root_absolute)
    if root_dir == "" {
        root_dir = "."
    }

    groups: [dynamic]IR_Package_Group
    for decl in program.decls {
        source_root := canonical_decl_source_root(decl, root_dir)
        group := find_or_add_package_group(&groups, source_root, root_dir)
        append(&group.decls, decl)
        delete(source_root)
    }
    slice.sort_by(groups[:], proc(a, b: IR_Package_Group) -> bool {
        if a.is_root != b.is_root {
            return a.is_root
        }
        return a.id < b.id
    })
    return groups, true
}

odin_identifier_start :: proc(ch: u8) -> bool {
    return ch == '_' ||
           (ch >= 'a' && ch <= 'z') ||
           (ch >= 'A' && ch <= 'Z')
}

odin_identifier_continue :: proc(ch: u8) -> bool {
    return odin_identifier_start(ch) || (ch >= '0' && ch <= '9')
}

collect_top_level_odin_symbols :: proc(output: string) -> [dynamic]string {
    symbols: [dynamic]string
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || !odin_identifier_start(line[0]) {
            continue
        }
        end := 1
        for end < len(line) && odin_identifier_continue(line[end]) {
            end += 1
        }
        rest := strings.trim_space(line[end:])
        if strings.has_prefix(rest, "::") || strings.has_prefix(rest, ":") {
            name := line[:end]
            if name != "package" && name != "import" && !contains_text(symbols[:], name) {
                append(&symbols, strings.clone(name))
            }
        }
    }
    return symbols
}

Package_Symbol_Origin :: struct {
    package_id: string,
    symbol:     string,
}

Generated_Import :: struct {
    alias: string,
    line:  string,
}

delete_generated_imports :: proc(imports: ^[dynamic]Generated_Import) {
    for item in imports^ {
        delete(item.alias)
        delete(item.line)
    }
    delete(imports^)
    imports^ = nil
}

generated_import_alias :: proc(line: string) -> (string, bool) {
    trimmed := strings.trim_space(line)
    if !strings.has_prefix(trimmed, "import ") {
        return "", false
    }
    rest := strings.trim_space(trimmed[len("import "):])
    if rest == "" {
        return "", false
    }
    if rest[0] == '"' {
        path := unquote_string(rest)
        return import_default_alias(path), true
    }
    end := 0
    for end < len(rest) &&
        rest[end] != ' ' &&
        rest[end] != '\t' &&
        rest[end] != '\r' &&
        rest[end] != '\n' {
        end += 1
    }
    if end == 0 {
        return "", false
    }
    return rest[:end], true
}

collect_generated_imports :: proc(groups: []IR_Package_Group) -> [dynamic]Generated_Import {
    imports: [dynamic]Generated_Import
    for group in groups {
        lines := strings.split_lines(group.emitted.output, context.allocator)
        for line in lines {
            alias, ok := generated_import_alias(line)
            if !ok || alias == "" {
                continue
            }
            found := false
            for item in imports {
                if item.alias == alias {
                    found = true
                    break
                }
            }
            if !found {
                append(&imports, Generated_Import{
                    alias = strings.clone(alias),
                    line = strings.clone(strings.trim_space(line)),
                })
            }
        }
        delete(lines)
    }
    return imports
}

output_uses_import_alias :: proc(output, alias: string) -> bool {
    if alias == "" {
        return false
    }
    needle := strings.clone(fmt.tprintf("%s.", alias))
    defer delete(needle)
    return strings.contains(output, needle)
}

output_has_generated_import_alias :: proc(output, alias: string) -> bool {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        existing, ok := generated_import_alias(line)
        if ok && existing == alias {
            return true
        }
    }
    return false
}

propagate_used_generated_imports :: proc(groups: ^[dynamic]IR_Package_Group) {
    imports := collect_generated_imports(groups^[:])
    defer delete_generated_imports(&imports)
    for &group in groups^ {
        additions: [dynamic]string
        for item in imports {
            if output_uses_import_alias(group.emitted.output, item.alias) &&
               !output_has_generated_import_alias(group.emitted.output, item.alias) {
                append(&additions, item.line)
            }
        }
        if len(additions) > 0 {
            adjusted, added_lines := inject_imports_into_output_header(
                group.emitted.output,
                additions[:],
            )
            delete(group.emitted.output)
            group.emitted.output = adjusted
            shift_source_map_lines(&group.emitted.source_map, added_lines)
        }
        delete(additions)
    }
}

foreign_package_symbol_map :: proc(
    groups: []IR_Package_Group,
    current: int,
) -> map[string]Package_Symbol_Origin {
    origins := make(map[string]Package_Symbol_Origin)
    local := make(map[string]bool)
    defer delete(local)
    for symbol in groups[current].symbols {
        local[symbol] = true
    }
    for group, idx in groups {
        if idx == current {
            continue
        }
        for symbol in group.symbols {
            if !local[symbol] {
                origins[symbol] = Package_Symbol_Origin{
                    package_id = group.id,
                    symbol = symbol,
                }
            }
        }
    }
    return origins
}

qualify_generated_package_output :: proc(
    output: string,
    origins: map[string]Package_Symbol_Origin,
) -> (qualified: string, dependencies: [dynamic]string) {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    in_string := false
    in_rune := false
    escaped := false
    in_line_comment := false
    in_block_comment := false
    i := 0
    for i < len(output) {
        ch := output[i]
        next := u8(0)
        if i+1 < len(output) {
            next = output[i+1]
        }
        if in_line_comment {
            strings.write_byte(&builder, ch)
            i += 1
            if ch == '\n' {
                in_line_comment = false
            }
            continue
        }
        if in_block_comment {
            strings.write_byte(&builder, ch)
            i += 1
            if ch == '*' && next == '/' {
                strings.write_byte(&builder, next)
                i += 1
                in_block_comment = false
            }
            continue
        }
        if in_string || in_rune {
            strings.write_byte(&builder, ch)
            i += 1
            if escaped {
                escaped = false
            } else if ch == '\\' {
                escaped = true
            } else if (in_string && ch == '"') || (in_rune && ch == '\'') {
                in_string = false
                in_rune = false
            }
            continue
        }
        if ch == '/' && next == '/' {
            strings.write_byte(&builder, ch)
            strings.write_byte(&builder, next)
            i += 2
            in_line_comment = true
            continue
        }
        if ch == '/' && next == '*' {
            strings.write_byte(&builder, ch)
            strings.write_byte(&builder, next)
            i += 2
            in_block_comment = true
            continue
        }
        if ch == '"' {
            in_string = true
            strings.write_byte(&builder, ch)
            i += 1
            continue
        }
        if ch == '\'' {
            in_rune = true
            strings.write_byte(&builder, ch)
            i += 1
            continue
        }
        if odin_identifier_start(ch) {
            end := i+1
            for end < len(output) && odin_identifier_continue(output[end]) {
                end += 1
            }
            token := output[i:end]
            if origin, found := origins[token]; found {
                strings.write_string(&builder, origin.package_id)
                strings.write_byte(&builder, '.')
                strings.write_string(&builder, token)
                if !contains_text(dependencies[:], origin.package_id) {
                    append(&dependencies, strings.clone(origin.package_id))
                }
            } else {
                strings.write_string(&builder, token)
            }
            i = end
            continue
        }
        strings.write_byte(&builder, ch)
        i += 1
    }
    return strings.clone(strings.to_string(builder)), dependencies
}

generated_package_import_lines :: proc(dependencies: []string) -> [dynamic]string {
    imports: [dynamic]string
    for dependency in dependencies {
        append(
            &imports,
            strings.clone(fmt.tprintf(
                "import %s \"__KVIST_PACKAGE_%s__\"",
                dependency,
                dependency,
            )),
        )
    }
    return imports
}

emit_ir_program_with_package_artifacts :: proc(
    program: IR_Program,
    root_path: string,
    profile: ^Compile_Profile = nil,
    cache_dir := "",
) -> (result: Package_Emit_Result, err: Compile_Error, ok: bool) {
    groups, grouped := group_ir_decls_by_package(program, root_path)
    if !grouped {
        return result, Compile_Error{message = "could not group generated packages"}, false
    }
    defer delete_ir_package_groups(&groups)

    err_prepare, ok_prepare := prepare_ir_decls_for_emission(program.decls[:], profile)
    if !ok_prepare {
        return result, err_prepare, false
    }
    interfaces := make(map[string]u64)
    defer delete(interfaces)
    for group in groups {
        interfaces[group.id] = package_decls_interface_hash(group.decls[:])
    }
    manifest_path, manifest_path_ok := package_dependency_manifest_path(
        cache_dir,
        root_path,
    )
    defer if manifest_path != "" {
        delete(manifest_path)
    }
    previous_manifest := Package_Dependency_Manifest{}
    previous_manifest_ok := false
    if manifest_path_ok && os.exists(manifest_path) {
        previous_manifest, previous_manifest_ok = load_package_dependency_manifest(
            manifest_path,
            root_path,
        )
    }
    defer if previous_manifest_ok {
        delete_package_dependency_manifest(&previous_manifest)
    }
    root_index := -1
    import_cache := Emitter_Import_Cache{}
    emitter_import_cache_init(&import_cache)
    defer emitter_import_cache_delete(&import_cache)
    shared_features := Emitter_Features{}
    defer {
        delete(shared_features.thread_starts)
        delete(shared_features.thread_detaches)
        delete(shared_features.data_literals)
    }
    for &group, idx in groups {
        source_hash, hash_ok := package_group_source_hash(group)
        group.source_hash = source_hash
        previous_dependencies: []string
        if previous_manifest_ok {
            previous_dependencies = package_manifest_dependencies(
                previous_manifest,
                group.id,
            )
        }
        dependency_hash := package_dependency_interface_hash(
            previous_dependencies,
            interfaces,
        )
        cache_path := ""
        cache_path_ok := false
        if hash_ok {
            cache_path, cache_path_ok = package_group_cache_path(
                cache_dir,
                group.id,
                source_hash,
                dependency_hash,
            )
        }
        if cache_path_ok && os.exists(cache_path) {
            cached, cached_features, cached_ok := load_cached_package_group(cache_path)
            if cached_ok {
                group.emitted = cached
                merge_emitter_features(&shared_features, cached_features)
                group.features = cached_features
                group.cache_hit = true
                result.packages_reused += 1
                delete(cache_path)
                if group.is_root {
                    root_index = idx
                }
                continue
            }
        }
        emitted_decls: [dynamic]IR_Decl
        if group.is_root {
            root_index = idx
            append(&emitted_decls, ..group.decls[:])
        } else {
            append(&emitted_decls, IR_Decl{
                kind = .Package,
                package_name = group.id,
            })
            append(&emitted_decls, ..group.decls[:])
        }
        group_features := Emitter_Features{}
        emitted, emit_err, emit_ok := emit_selected_decls_with_source_map(
            program.decls[:],
            emitted_decls[:],
            suppress_shared_helpers = true,
            aggregate_features = &group_features,
            analysis_prepared = true,
            profile = profile,
            shared_import_cache = &import_cache,
        )
        delete(emitted_decls)
        if !emit_ok {
            if cache_path != "" {
                delete(cache_path)
            }
            delete_cached_emitter_features(&group_features)
            return result, emit_err, false
        }
        group.emitted = emitted
        merge_emitter_features(&shared_features, group_features)
        group.features = group_features
        if cache_path != "" {
            delete(cache_path)
        }
        result.packages_emitted += 1
    }
    propagate_used_generated_imports(&groups)
    for &group in groups {
        group.symbols = collect_top_level_odin_symbols(group.emitted.output)
    }
    shared_package := IR_Decl{
        kind = .Package,
        package_name = "kvp_shared",
    }
    shared_emitted, shared_err, shared_ok := emit_selected_decls_with_source_map(
        program.decls[:],
        []IR_Decl{shared_package},
        initial_features = &shared_features,
        analysis_prepared = true,
        profile = profile,
        shared_import_cache = &import_cache,
    )
    if !shared_ok {
        return result, shared_err, false
    }
    result.packages_emitted += 1
    append(&groups, IR_Package_Group{
        id = strings.clone("kvp_shared"),
        source_root = strings.clone(""),
        emitted = shared_emitted,
        symbols = collect_top_level_odin_symbols(shared_emitted.output),
    })
    if root_index < 0 {
        return result, Compile_Error{message = "generated package graph has no root package"}, false
    }

    dependency_records: [dynamic]Package_Dependency_Record
    defer {
        for &record in dependency_records {
            delete(record.id)
            delete_string_slice(&record.dependencies)
        }
        delete(dependency_records)
    }
    for &group, idx in groups {
        origins := foreign_package_symbol_map(groups[:], idx)
        qualified, dependencies := qualify_generated_package_output(group.emitted.output, origins)
        delete(origins)
        if group.id != "kvp_shared" {
            record := Package_Dependency_Record{id = strings.clone(group.id)}
            for dependency in dependencies {
                append(&record.dependencies, strings.clone(dependency))
            }
            append(&dependency_records, record)
            if !group.cache_hit {
                dependency_hash := package_dependency_interface_hash(
                    dependencies[:],
                    interfaces,
                )
                cache_path, cache_path_ok := package_group_cache_path(
                    cache_dir,
                    group.id,
                    group.source_hash,
                    dependency_hash,
                )
                if cache_path_ok {
                    publish_cached_package_group(
                        cache_path,
                        group.emitted,
                        group.features,
                    )
                }
                if cache_path != "" {
                    delete(cache_path)
                }
            }
        }
        imports := generated_package_import_lines(dependencies[:])
        final_output := qualified
        if len(imports) > 0 {
            adjusted, added_lines := inject_imports_into_output_header(qualified, imports[:])
            delete(qualified)
            final_output = adjusted
            shift_source_map_lines(&group.emitted.source_map, added_lines)
        }
        delete_string_slice(&imports)
        delete(group.emitted.output)
        group.emitted.output = final_output

        if group.is_root {
            result.root = group.emitted
            group.emitted = {}
            delete_string_slice(&dependencies)
            continue
        }
        artifact := Generated_Package_Artifact{
            id = strings.clone(group.id),
            source_root = strings.clone(group.source_root),
            output = group.emitted.output,
            source_map = group.emitted.source_map,
            warnings = group.emitted.warnings,
            dependencies = dependencies,
        }
        group.emitted = {}
        append(&result.artifacts, artifact)
    }
    if manifest_path_ok {
        publish_package_dependency_manifest(
            manifest_path,
            root_path,
            dependency_records[:],
        )
    }
    return result, {}, true
}

generated_package_artifact_delete :: proc(artifact: ^Generated_Package_Artifact) {
    delete(artifact.id)
    delete(artifact.source_root)
    delete(artifact.output)
    source_map_slice_delete(artifact.source_map)
    compile_warning_slice_delete(artifact.warnings)
    delete_string_slice(&artifact.dependencies)
    artifact^ = {}
}

package_emit_result_delete :: proc(result: ^Package_Emit_Result) {
    delete(result.root.output)
    source_map_slice_delete(result.root.source_map)
    compile_warning_slice_delete(result.root.warnings)
    for &artifact in result.artifacts {
        generated_package_artifact_delete(&artifact)
    }
    delete(result.artifacts)
    result^ = {}
}
