// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
compile_path_emits_imported_package_artifacts :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-package-artifacts-*", context.allocator)
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
(defn main [] (println support.answer))`) == nil, true)
    testing.expect_value(t, os.write_entire_file_from_string(support_path, `(package support)
(def answer 42)`) == nil, true)

    result, err, ok := kvist.compile_path_with_package_artifacts(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer kvist.package_emit_result_delete(&result)
    testing.expect_value(t, len(result.artifacts) > 0, true)
    testing.expect_value(t, strings.contains(result.root.output, "__KVIST_PACKAGE_"), true)
    testing.expect_value(t, strings.contains(result.root.output, ".support__answer"), true)
}

@(test)
package_artifacts_keep_parallel_helpers_with_their_calling_package :: proc(t: ^testing.T) {
    repo_root := compiler_test_repo_root()
    example_path, path_err := os.join_path(
        {repo_root, "examples", "packages", "parallel.kvist"},
        context.allocator,
    )
    testing.expect_value(t, path_err == nil, true)
    if path_err != nil {
        return
    }
    defer delete(example_path)

    result, err, ok := kvist.compile_path_with_package_artifacts(example_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer kvist.package_emit_result_delete(&result)

    testing.expect_value(
        t,
        strings.contains(result.root.output, "thread_start_square_int_int :: proc"),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(result.root.output, ".parallel_Task(int)"),
        true,
    )

    found_parallel_package := false
    for artifact in result.artifacts {
        if artifact.id == "kvp_shared" {
            testing.expect_value(t, strings.contains(artifact.output, "thread_start_"), false)
            testing.expect_value(t, strings.contains(artifact.output, "thread_detach_"), false)
            continue
        }
        if strings.contains(artifact.output, "parallel_Task :: struct") {
            found_parallel_package = true
            testing.expect_value(
                t,
                strings.contains(artifact.output, "thread_start_p__map_worker"),
                true,
            )
            testing.expect_value(
                t,
                strings.contains(artifact.output, "thread_start_p__for_worker"),
                true,
            )
        }
    }
    testing.expect_value(t, found_parallel_package, true)
}

@(test)
package_artifacts_preserve_explicitly_qualified_foreign_types :: proc(
	t: ^testing.T,
) {
	origins := make(map[string]kvist.Package_Symbol_Origin)
	defer delete(origins)
	origins["Data"] = {
		package_id = "kvp_shared",
		symbol = "Data",
	}
	qualified, dependencies := kvist.qualify_generated_package_output(
		"wrapped: native.Data\nplain: Data\n",
		origins,
	)
	defer delete(qualified)
	defer kvist.delete_string_slice(&dependencies)
	testing.expect_value(
		t,
		strings.contains(qualified, "wrapped: native.Data"),
		true,
	)
	testing.expect_value(
		t,
		strings.contains(qualified, "native.kvp_shared.Data"),
		false,
	)
	testing.expect_value(
		t,
		strings.contains(qualified, "plain: kvp_shared.Data"),
		true,
	)
	testing.expect_value(t, len(dependencies), 1)
	testing.expect_value(t, dependencies[0], "kvp_shared")
}

@(test)
package_artifact_source_hash_includes_resolved_declaration_identity :: proc(t: ^testing.T) {
    path, ok_path := repo_temp_test_path(".tmp-package-artifact-hash.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path do return
    defer {
        _ = os.remove(path)
        delete(path)
    }
    testing.expect_value(
        t,
        os.write_entire_file_from_string(path, "(package helper)\n(defn value [] -> int 1)\n") == nil,
        true,
    )
    first := kvist.IR_Package_Group{decls = make([dynamic]kvist.IR_Decl)}
    second := kvist.IR_Package_Group{decls = make([dynamic]kvist.IR_Decl)}
    a_decl := kvist.IR_Decl{
        kind = .Proc,
        source_path = path,
        proc_decl = kvist.Proc_Decl{name = "a__helper__value"},
    }
    append(&first.decls, a_decl)
    append(&second.decls, a_decl)
    append(&second.decls, kvist.IR_Decl{
        kind = .Proc,
        source_path = path,
        proc_decl = kvist.Proc_Decl{name = "b__helper__value"},
    })
    defer {
        delete(first.decls)
        delete(second.decls)
    }
    first_hash, first_ok := kvist.package_group_source_hash(first)
    second_hash, second_ok := kvist.package_group_source_hash(second)
    testing.expect_value(t, first_ok, true)
    testing.expect_value(t, second_ok, true)
    testing.expect_value(t, first_hash != second_hash, true)
}
