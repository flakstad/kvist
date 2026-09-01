package kvist_repl

import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import repl_program "../kvist_repl_program"

WORKER_INCREMENTAL_PROGRAM_PREFIX :: "__kvist_program__\t"

LLVM_Create_LLJIT :: proc "c" (^rawptr, rawptr) -> rawptr
LLVM_Dispose_LLJIT :: proc "c" (rawptr) -> rawptr
LLVM_Get_LLJIT_String :: proc "c" (rawptr) -> cstring
LLVM_Get_LLJIT_Dylib :: proc "c" (rawptr) -> rawptr
LLVM_LLJIT_Add_Module :: proc "c" (rawptr, rawptr, rawptr) -> rawptr
LLVM_LLJIT_Lookup :: proc "c" (rawptr, ^u64, cstring) -> rawptr
LLVM_Context_Create :: proc "c" () -> rawptr
LLVM_Context_Dispose :: proc "c" (rawptr)
LLVM_Memory_Buffer_Create :: proc "c" (cstring, uintptr, cstring) -> rawptr
LLVM_Memory_Buffer_Dispose :: proc "c" (rawptr)
LLVM_Parse_IR :: proc "c" (rawptr, rawptr, ^rawptr, ^cstring) -> i32
LLVM_Message_Dispose :: proc "c" (cstring)
LLVM_Thread_Context_Create :: proc "c" (rawptr) -> rawptr
LLVM_Thread_Context_Dispose :: proc "c" (rawptr)
LLVM_Thread_Module_Create :: proc "c" (rawptr, rawptr) -> rawptr
LLVM_Thread_Module_Dispose :: proc "c" (rawptr)
LLVM_Error_Message :: proc "c" (rawptr) -> cstring
LLVM_Error_Message_Dispose :: proc "c" (cstring)

Incremental_LLVM_API :: struct {
    create_jit: LLVM_Create_LLJIT `dynlib:"LLVMOrcCreateLLJIT"`,
    dispose_jit: LLVM_Dispose_LLJIT `dynlib:"LLVMOrcDisposeLLJIT"`,
    get_triple: LLVM_Get_LLJIT_String `dynlib:"LLVMOrcLLJITGetTripleString"`,
    get_data_layout: LLVM_Get_LLJIT_String `dynlib:"LLVMOrcLLJITGetDataLayoutStr"`,
    get_main_dylib: LLVM_Get_LLJIT_Dylib `dynlib:"LLVMOrcLLJITGetMainJITDylib"`,
    add_module: LLVM_LLJIT_Add_Module `dynlib:"LLVMOrcLLJITAddLLVMIRModule"`,
    lookup: LLVM_LLJIT_Lookup `dynlib:"LLVMOrcLLJITLookup"`,
    context_create: LLVM_Context_Create `dynlib:"LLVMContextCreate"`,
    context_dispose: LLVM_Context_Dispose `dynlib:"LLVMContextDispose"`,
    memory_buffer_create: LLVM_Memory_Buffer_Create `dynlib:"LLVMCreateMemoryBufferWithMemoryRangeCopy"`,
    memory_buffer_dispose: LLVM_Memory_Buffer_Dispose `dynlib:"LLVMDisposeMemoryBuffer"`,
    parse_ir: LLVM_Parse_IR `dynlib:"LLVMParseIRInContext2"`,
    message_dispose: LLVM_Message_Dispose `dynlib:"LLVMDisposeMessage"`,
    thread_context_create: LLVM_Thread_Context_Create `dynlib:"LLVMOrcCreateNewThreadSafeContextFromLLVMContext"`,
    thread_context_dispose: LLVM_Thread_Context_Dispose `dynlib:"LLVMOrcDisposeThreadSafeContext"`,
    thread_module_create: LLVM_Thread_Module_Create `dynlib:"LLVMOrcCreateNewThreadSafeModule"`,
    thread_module_dispose: LLVM_Thread_Module_Dispose `dynlib:"LLVMOrcDisposeThreadSafeModule"`,
    error_message: LLVM_Error_Message `dynlib:"LLVMGetErrorMessage"`,
    error_message_dispose: LLVM_Error_Message_Dispose `dynlib:"LLVMDisposeErrorMessage"`,
    __handle: dynlib.Library,
}

Incremental_LLVM_Backend :: struct {
    initialized: bool,
    available:   bool,
    api:         Incremental_LLVM_API,
    engines:     [dynamic]rawptr,
    generation:  int,
    reason:      string,
}

Incremental_LLVM_Native_Targets :: struct {
    // One scalar-adapter slot per expression. -1 is not a native call.
    slots: [dynamic]int,
}

Incremental_Call_Status :: enum u8 {
    Failed,
    Success,
    Aborted,
}

Incremental_Managed_Frame :: struct {
    worker:       ^Worker,
    allocator:    runtime.Allocator,
    values:       [dynamic]Worker_Plan_Value,
    initialized:  [dynamic]bool,
    owned_values: Worker_Plan_Owned_Values,
}

Incremental_LLVM_Managed_Cleanup :: struct {
    slot_index:  int,
    force_owner: bool,
}

incremental_llvm_probe_mutex: sync.Mutex
incremental_llvm_probe_complete: bool
incremental_llvm_probe_path: string

incremental_llvm_api_complete :: proc(api: ^Incremental_LLVM_API) -> bool {
    return api != nil && api.__handle != nil && api.create_jit != nil &&
           api.dispose_jit != nil && api.get_triple != nil &&
           api.get_data_layout != nil && api.get_main_dylib != nil &&
           api.add_module != nil && api.lookup != nil &&
           api.context_create != nil && api.context_dispose != nil &&
           api.memory_buffer_create != nil &&
           api.memory_buffer_dispose != nil && api.parse_ir != nil &&
           api.message_dispose != nil && api.thread_context_create != nil &&
           api.thread_context_dispose != nil &&
           api.thread_module_create != nil &&
           api.thread_module_dispose != nil && api.error_message != nil &&
           api.error_message_dispose != nil
}

incremental_llvm_api_unload :: proc(api: ^Incremental_LLVM_API) {
    if api == nil {
        return
    }
    if api.__handle != nil {
        _ = dynlib.unload_library(api.__handle)
    }
    api^ = {}
}

incremental_llvm_api_load :: proc(
    path: string,
) -> (Incremental_LLVM_API, bool) {
    api := Incremental_LLVM_API{}
    _, loaded := dynlib.initialize_symbols(&api, path)
    if !loaded || !incremental_llvm_api_complete(&api) {
        incremental_llvm_api_unload(&api)
        return {}, false
    }
    return api, true
}

incremental_llvm_api_can_create_jit :: proc(
    api: ^Incremental_LLVM_API,
) -> bool {
    if !incremental_llvm_api_complete(api) ||
       incremental_llvm_initialize_targets(api.__handle) == 0 {
        return false
    }
    engine: rawptr
    create_error := api.create_jit(&engine, nil)
    if create_error != nil {
        message := api.error_message(create_error)
        if message != nil {
            api.error_message_dispose(message)
        }
        return false
    }
    if engine == nil {
        return false
    }
    dispose_error := api.dispose_jit(engine)
    if dispose_error != nil {
        message := api.error_message(dispose_error)
        if message != nil {
            api.error_message_dispose(message)
        }
        return false
    }
    return true
}

incremental_llvm_candidate_names :: proc() -> [dynamic]string {
    result: [dynamic]string
    extension := dynlib.LIBRARY_FILE_EXTENSION
    if extension == "dll" {
        append(&result, strings.clone("LLVM-C.dll"))
        append(&result, strings.clone("LLVM.dll"))
        for version := 22; version >= 17; version -= 1 {
            append(&result, fmt.aprintf("LLVM-C-%d.dll", version))
            append(&result, fmt.aprintf("LLVM-%d.dll", version))
        }
        return result
    }
    append(&result, fmt.aprintf("libLLVM-C.%s", extension))
    append(&result, fmt.aprintf("libLLVM.%s", extension))
    for version := 22; version >= 17; version -= 1 {
        append(&result, fmt.aprintf("libLLVM-C-%d.%s", version, extension))
        append(&result, fmt.aprintf("libLLVM-%d.%s", version, extension))
        if extension == "so" {
            append(&result, fmt.aprintf("libLLVM.so.%d", version))
        }
    }
    return result
}

incremental_llvm_candidate_names_delete :: proc(names: ^[dynamic]string) {
    if names == nil {
        return
    }
    for name in names^ {
        delete(name)
    }
    delete(names^)
    names^ = nil
}

INCREMENTAL_LLVM_ODIN_BINARY_SCAN_LIMIT :: 16 * 1024 * 1024

// Odin distributions expose LLVM in a few different, but discoverable, ways:
// beside the compiler, under its reported root, or as a dynamic dependency of
// the compiler executable. Inspect those toolchain-owned locations and always
// validate the C API before using a candidate. This avoids package-manager and
// platform-specific paths while keeping LLVM optional for ordinary Kvist use.

incremental_llvm_append_unique_text :: proc(
    values: ^[dynamic]string,
    value: string,
) {
    if values == nil || value == "" {
        return
    }
    for existing in values^ {
        if existing == value {
            return
        }
    }
    append(values, strings.clone(value))
}

incremental_llvm_text_slice_delete :: proc(values: ^[dynamic]string) {
    if values == nil {
        return
    }
    for value in values^ {
        delete(value)
    }
    delete(values^)
    values^ = nil
}

incremental_llvm_library_name_end :: proc(
    value: string,
    marker: int,
) -> (int, bool) {
    if marker < 0 || marker >= len(value) {
        return 0, false
    }
    rest := value[marker:]
    extension_offset := -1
    extension_length := 0
    extensions := [?]string{".dylib", ".so", ".dll"}
    for extension in extensions {
        offset := strings.index(rest, extension)
        if offset >= 0 &&
           (extension_offset < 0 || offset < extension_offset) {
            extension_offset = offset
            extension_length = len(extension)
        }
    }
    if extension_offset < 0 {
        return 0, false
    }
    end := marker+extension_offset+extension_length
    if strings.has_prefix(value[marker+extension_offset:], ".so") {
        for end < len(value) &&
            ((value[end] >= '0' && value[end] <= '9') ||
             value[end] == '.') {
            end += 1
        }
    }
    return end, true
}

incremental_llvm_append_embedded_library_run :: proc(
    candidates: ^[dynamic]string,
    value: string,
) {
    if candidates == nil || value == "" {
        return
    }
    marker := strings.index(value, "libLLVM")
    if marker < 0 {
        marker = strings.index(value, "LLVM-C")
    }
    if marker < 0 {
        marker = strings.index(value, "LLVM.dll")
    }
    end, found := incremental_llvm_library_name_end(value, marker)
    if !found {
        return
    }
    incremental_llvm_append_unique_text(candidates, value[marker:end])
    absolute_path := value[0] == '/' || value[0] == '\\' ||
        (len(value) >= 3 &&
         ((value[0] >= 'A' && value[0] <= 'Z') ||
          (value[0] >= 'a' && value[0] <= 'z')) &&
         value[1] == ':' &&
         (value[2] == '/' || value[2] == '\\'))
    if absolute_path {
        incremental_llvm_append_unique_text(candidates, value[:end])
    }
}

incremental_llvm_embedded_library_candidates :: proc(
    data: []byte,
) -> [dynamic]string {
    candidates: [dynamic]string
    run_start := 0
    in_run := false
    for byte, index in data {
        printable := byte >= 0x20 && byte <= 0x7e
        if printable && !in_run {
            run_start = index
            in_run = true
        }
        if printable {
            continue
        }
        if in_run {
            incremental_llvm_append_embedded_library_run(
                &candidates,
                string(data[run_start:index]),
            )
            in_run = false
        }
    }
    if in_run {
        incremental_llvm_append_embedded_library_run(
            &candidates,
            string(data[run_start:]),
        )
    }
    return candidates
}

incremental_llvm_binary_library_candidates :: proc(
    path: string,
) -> [dynamic]string {
    candidates: [dynamic]string
    if path == "" || !os.is_file(path) {
        return candidates
    }
    file, open_err := os.open(path)
    if open_err != nil {
        return candidates
    }
    defer os.close(file)
    size, size_err := os.file_size(file)
    if size_err != nil || size <= 0 {
        return candidates
    }
    read_size := min(size, i64(INCREMENTAL_LLVM_ODIN_BINARY_SCAN_LIMIT))
    data := make([]byte, int(read_size))
    defer delete(data)
    count, _ := os.read_at(file, data, 0)
    if count <= 0 {
        return candidates
    }
    return incremental_llvm_embedded_library_candidates(data[:count])
}

incremental_llvm_odin_root :: proc() -> string {
    configured := os.get_env("ODIN_ROOT", context.allocator)
    if configured != "" && os.is_dir(configured) {
        cleaned, clean_err := os.clean_path(configured, context.allocator)
        if clean_err == nil {
            delete(configured)
            return cleaned
        }
    }
    delete(configured)
    state, stdout, stderr, process_err := os.process_exec(
        os.Process_Desc{command = {"odin", "root"}},
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    if process_err != nil || !state.exited || state.exit_code != 0 {
        return ""
    }
    root := strings.trim_space(string(stdout))
    if root == "" || !os.is_dir(root) {
        return ""
    }
    cleaned, clean_err := os.clean_path(root, context.allocator)
    if clean_err != nil {
        return strings.clone(root)
    }
    return cleaned
}

incremental_llvm_append_joined_path :: proc(
    paths: ^[dynamic]string,
    directory,
    leaf: string,
) {
    if paths == nil || directory == "" || leaf == "" {
        return
    }
    joined, join_err := os.join_path({directory, leaf}, context.allocator)
    if join_err != nil {
        return
    }
    defer delete(joined)
    incremental_llvm_append_unique_text(paths, joined)
}

incremental_llvm_odin_toolchain_paths :: proc(
) -> (directories, executables: [dynamic]string) {
    root := incremental_llvm_odin_root()
    defer delete(root)
    if root != "" {
        incremental_llvm_append_unique_text(&directories, root)
        incremental_llvm_append_joined_path(&directories, root, "bin")
        incremental_llvm_append_joined_path(&directories, root, "lib")
        parent, _ := os.split_path(root)
        if parent != "" && parent != root {
            incremental_llvm_append_unique_text(&directories, parent)
            incremental_llvm_append_joined_path(&directories, parent, "bin")
            incremental_llvm_append_joined_path(&directories, parent, "lib")
        }
        incremental_llvm_append_joined_path(&executables, root, "odin")
        incremental_llvm_append_joined_path(&executables, root, "odin.exe")
        incremental_llvm_append_joined_path(&executables, root, "bin/odin")
        incremental_llvm_append_joined_path(&executables, root, "bin/odin.exe")
    }
    path_value := os.get_env("PATH", context.allocator)
    defer delete(path_value)
    path_directories, path_err := os.split_path_list(
        path_value,
        context.allocator,
    )
    if path_err == nil {
        defer {
            for directory in path_directories {
                delete(directory)
            }
            delete(path_directories)
        }
        for directory in path_directories {
            incremental_llvm_append_joined_path(
                &executables,
                directory,
                "odin",
            )
            incremental_llvm_append_joined_path(
                &executables,
                directory,
                "odin.exe",
            )
        }
    }
    return
}

incremental_llvm_library_usable :: proc(path: string) -> bool {
    if path == "" {
        return false
    }
    api, loaded := incremental_llvm_api_load(path)
    if !loaded {
        return false
    }
    defer incremental_llvm_api_unload(&api)
    return incremental_llvm_api_can_create_jit(&api)
}

incremental_llvm_library_in_directory :: proc(
    directory: string,
    names: []string,
) -> string {
    if directory == "" {
        return ""
    }
    for name in names {
        path, path_err := os.join_path(
            {directory, name},
            context.allocator,
        )
        if path_err != nil {
            continue
        }
        if incremental_llvm_library_usable(path) {
            return path
        }
        delete(path)
    }
    return ""
}

incremental_llvm_odin_toolchain_library :: proc(
    names: []string,
) -> string {
    directories, executables := incremental_llvm_odin_toolchain_paths()
    defer incremental_llvm_text_slice_delete(&directories)
    defer incremental_llvm_text_slice_delete(&executables)
    for directory in directories {
        library := incremental_llvm_library_in_directory(directory, names)
        if library != "" {
            return library
        }
    }
    embedded: [dynamic]string
    defer incremental_llvm_text_slice_delete(&embedded)
    for executable in executables {
        if !os.is_file(executable) {
            continue
        }
        executable_dir, _ := os.split_path(executable)
        incremental_llvm_append_unique_text(&directories, executable_dir)
        candidates := incremental_llvm_binary_library_candidates(executable)
        for candidate in candidates {
            incremental_llvm_append_unique_text(&embedded, candidate)
        }
        incremental_llvm_text_slice_delete(&candidates)
    }
    for candidate in embedded {
        if incremental_llvm_library_usable(candidate) {
            return strings.clone(candidate)
        }
        _, leaf := os.split_path(candidate)
        if leaf == "" {
            leaf = candidate
        }
        for directory in directories {
            path, path_err := os.join_path(
                {directory, leaf},
                context.allocator,
            )
            if path_err != nil {
                continue
            }
            if incremental_llvm_library_usable(path) {
                return path
            }
            delete(path)
        }
    }
    return ""
}

incremental_llvm_config_libdir :: proc() -> string {
    configured := os.get_env("LLVM_CONFIG", context.allocator)
    defer delete(configured)
    executables: [dynamic]string
    defer {
        for executable in executables {
            delete(executable)
        }
        delete(executables)
    }
    if configured != "" {
        append(&executables, strings.clone(configured))
    } else {
        append(&executables, strings.clone("llvm-config"))
        for version := 22; version >= 17; version -= 1 {
            append(&executables, fmt.aprintf("llvm-config-%d", version))
        }
    }
    for executable in executables {
        command := []string{executable, "--libdir"}
        state, stdout, stderr, process_err := os.process_exec(
            os.Process_Desc{command = command},
            context.allocator,
        )
        if process_err == nil && state.exited && state.exit_code == 0 {
            result := strings.clone(strings.trim_space(string(stdout)))
            delete(stdout)
            delete(stderr)
            if result != "" {
                return result
            }
            delete(result)
        } else {
            delete(stdout)
            delete(stderr)
        }
    }
    return ""
}

incremental_llvm_find_library :: proc() -> string {
    explicit := os.get_env("KVIST_LLVM_LIBRARY", context.allocator)
    if explicit != "" {
        if incremental_llvm_library_usable(explicit) {
            return explicit
        }
    }
    delete(explicit)
    names := incremental_llvm_candidate_names()
    defer incremental_llvm_candidate_names_delete(&names)
    configured := os.get_env("LLVM_CONFIG", context.allocator)
    defer delete(configured)
    if configured != "" {
        libdir := incremental_llvm_config_libdir()
        defer delete(libdir)
        library := incremental_llvm_library_in_directory(libdir, names[:])
        if library != "" {
            return library
        }
    }
    toolchain_library := incremental_llvm_odin_toolchain_library(names[:])
    if toolchain_library != "" {
        return toolchain_library
    }
    if configured == "" {
        libdir := incremental_llvm_config_libdir()
        defer delete(libdir)
        library := incremental_llvm_library_in_directory(libdir, names[:])
        if library != "" {
            return library
        }
    }
    for name in names {
        if incremental_llvm_library_usable(name) {
            return strings.clone(name)
        }
    }
    return ""
}

incremental_native_backend_supported :: proc() -> bool {
    sync.mutex_lock(&incremental_llvm_probe_mutex)
    defer sync.mutex_unlock(&incremental_llvm_probe_mutex)
    if !incremental_llvm_probe_complete {
        found := incremental_llvm_find_library()
        incremental_llvm_probe_path = strings.clone(
            found,
            runtime.heap_allocator(),
        )
        delete(found)
        incremental_llvm_probe_complete = true
    }
    return incremental_llvm_probe_path != ""
}

incremental_llvm_library_path :: proc() -> string {
    if !incremental_native_backend_supported() {
        return ""
    }
    sync.mutex_lock(&incremental_llvm_probe_mutex)
    defer sync.mutex_unlock(&incremental_llvm_probe_mutex)
    return strings.clone(incremental_llvm_probe_path)
}

incremental_llvm_initialize_targets :: proc(library: dynlib.Library) -> int {
    // LLVM's C native-target helpers are header-only. Resolve every target
    // family exported by the installed LLVM instead of introducing OS or host
    // architecture branches here; the JIT then selects its detected host.
    families := [?]string{
        "AArch64", "AMDGPU", "ARM", "AVR", "BPF", "Hexagon", "Lanai",
        "LoongArch", "Mips", "MSP430", "NVPTX", "PowerPC", "RISCV",
        "Sparc", "SystemZ", "VE", "WebAssembly", "X86", "XCore",
    }
    suffixes := [?]string{"TargetInfo", "Target", "TargetMC", "AsmPrinter"}
    initialized := 0
    for family in families {
        complete := true
        addresses: [len(suffixes)]rawptr
        for suffix, index in suffixes {
            symbol := fmt.tprintf("LLVMInitialize%s%s", family, suffix)
            address, found := dynlib.symbol_address(library, symbol)
            if !found {
                complete = false
                break
            }
            addresses[index] = address
        }
        if !complete {
            continue
        }
        for address in addresses {
            initialize := transmute(proc "c" ())address
            initialize()
        }
        initialized += 1
    }
    return initialized
}

incremental_llvm_error :: proc(
    api: ^Incremental_LLVM_API,
    llvm_error: rawptr,
    fallback: string,
) -> string {
    if llvm_error == nil || api == nil || api.error_message == nil {
        return strings.clone(fallback)
    }
    message := api.error_message(llvm_error)
    if message == nil {
        return strings.clone(fallback)
    }
    result := strings.clone(string(message))
    api.error_message_dispose(message)
    return result
}

incremental_llvm_backend_initialize :: proc(
    backend: ^Incremental_LLVM_Backend,
) -> bool {
    if backend == nil {
        return false
    }
    if backend.initialized {
        return backend.available
    }
    backend.initialized = true
    path := incremental_llvm_library_path()
    defer delete(path)
    if path == "" {
        backend.reason = strings.clone(
            "incremental native execution needs an Odin toolchain with reusable LLVM, or KVIST_LLVM_LIBRARY/LLVM_CONFIG",
        )
        return false
    }
    api, loaded := incremental_llvm_api_load(path)
    if !loaded {
        backend.reason = strings.clone("failed to load the discovered LLVM native backend")
        return false
    }
    if incremental_llvm_initialize_targets(api.__handle) == 0 {
        incremental_llvm_api_unload(&api)
        backend.reason = strings.clone("LLVM contains no complete native target backend")
        return false
    }
    backend.api = api
    backend.available = true
    return true
}

incremental_llvm_backend_delete :: proc(
    backend: ^Incremental_LLVM_Backend,
) {
    if backend == nil {
        return
    }
    if backend.api.dispose_jit != nil {
        for engine in backend.engines {
            llvm_error := backend.api.dispose_jit(engine)
            if llvm_error != nil {
                message := backend.api.error_message(llvm_error)
                if message != nil {
                    backend.api.error_message_dispose(message)
                }
            }
        }
    }
    delete(backend.engines)
    incremental_llvm_api_unload(&backend.api)
    delete(backend.reason)
    backend^ = {}
}

Incremental_LLVM_Value :: struct {
    text: string,
    kind: repl_program.Value_Kind,
}

Incremental_LLVM_Local :: struct {
    pointer: string,
    kind:    repl_program.Value_Kind,
}

Incremental_LLVM_Emitter :: struct {
    output:         ^strings.Builder,
    program:        ^repl_program.Program,
    procedure:      ^repl_program.Procedure,
    procedure_index: int,
    function_names: []string,
    native_slots:   []int,
    worker_address: uintptr,
    invoke_address: uintptr,
    status_address: uintptr,
    managed_begin_address: uintptr,
    managed_end_address:   uintptr,
    managed_store_address: uintptr,
    managed_release_address: uintptr,
    guard_call_status: bool,
    locals:         [dynamic]Incremental_LLVM_Local,
    native_args_pointer:   string,
    native_result_pointer: string,
    managed_frame_pointer: string,
    managed_pointers:      [dynamic]string,
    active_managed_cleanups: [dynamic]Incremental_LLVM_Managed_Cleanup,
    loop_cleanup_depths:     [dynamic]int,
    next_value:     int,
    next_block:     int,
    current_block:  string,
    loop_condition_blocks: [dynamic]string,
    loop_exit_blocks:      [dynamic]string,
    terminated:     bool,
    failed:         bool,
}

incremental_llvm_value_delete :: proc(value: ^Incremental_LLVM_Value) {
    if value == nil {
        return
    }
    delete(value.text)
    value^ = {}
}

incremental_llvm_emitter_delete :: proc(emitter: ^Incremental_LLVM_Emitter) {
    if emitter == nil {
        return
    }
    for &local in emitter.locals {
        delete(local.pointer)
    }
    for &pointer in emitter.managed_pointers {
        delete(pointer)
    }
    delete(emitter.locals)
    delete(emitter.managed_pointers)
    delete(emitter.active_managed_cleanups)
    delete(emitter.loop_cleanup_depths)
    delete(emitter.loop_condition_blocks)
    delete(emitter.loop_exit_blocks)
    delete(emitter.native_args_pointer)
    delete(emitter.native_result_pointer)
    delete(emitter.managed_frame_pointer)
    delete(emitter.current_block)
    emitter^ = {}
}

incremental_llvm_type :: proc(kind: repl_program.Value_Kind) -> string {
    switch kind {
    case .Bool: return "i1"
    case .Int:  return "i64" if size_of(int) == 8 else "i32"
    case .F64:  return "double"
    case .String, .Data: return "ptr"
    case .Invalid, .Void:
    }
    return ""
}

incremental_llvm_internal_return_type :: proc(
    kind: repl_program.Value_Kind,
) -> string {
    if kind == .Bool {
        return "i8"
    }
    return incremental_llvm_type(kind)
}

incremental_llvm_pointer_int_type :: proc() -> string {
    return "i64" if size_of(uintptr) == 8 else "i32"
}

incremental_llvm_fresh_value :: proc(
    emitter: ^Incremental_LLVM_Emitter,
) -> string {
    result := fmt.aprintf("%%v%d", emitter.next_value)
    emitter.next_value += 1
    return result
}

incremental_llvm_fresh_block :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    prefix: string,
) -> string {
    result := fmt.aprintf("%s.%d", prefix, emitter.next_block)
    emitter.next_block += 1
    return result
}

incremental_llvm_start_block :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    block: string,
) {
    fmt.sbprintf(emitter.output, "%s:\n", block)
    delete(emitter.current_block)
    emitter.current_block = strings.clone(block)
    emitter.terminated = false
}

incremental_llvm_children :: proc(
    procedure: ^repl_program.Procedure,
    expression: repl_program.Expression,
) -> ([]int, bool) {
    end := expression.children_start+expression.children_count
    if procedure == nil || expression.children_start < 0 ||
       expression.children_count < 0 || end > len(procedure.child_indices) {
        return nil, false
    }
    return procedure.child_indices[expression.children_start:end], true
}

incremental_llvm_program_proc_index :: proc(
    program: ^repl_program.Program,
    name,
    signature: string,
) -> (int, bool) {
    if program == nil {
        return 0, false
    }
    for procedure, index in program.procedures {
        if procedure.name == name && procedure.signature == signature {
            return index, true
        }
    }
    return 0, false
}

incremental_llvm_scalar_result_abi :: proc(
    kind: repl_program.Value_Kind,
) -> string {
    switch kind {
    case .Bool: return "value:bool"
    case .Int:  return "value:int"
    case .F64:  return "value:f64"
    case .String: return "value:string"
    case .Data:   return "value:Data"
    case .Invalid, .Void:
    }
    return ""
}

incremental_llvm_native_targets_delete :: proc(
    targets: ^[dynamic]Incremental_LLVM_Native_Targets,
) {
    if targets == nil {
        return
    }
    for &target in targets^ {
        delete(target.slots)
    }
    delete(targets^)
    targets^ = nil
}

incremental_llvm_find_scalar_slot_index :: proc(
    worker: ^Worker,
    name,
    signature: string,
) -> (int, bool) {
    if worker == nil {
        return 0, false
    }
    for &slot, index in worker.scalar_invoke_slots {
        if slot.name == name && slot.signature == signature {
            return index, true
        }
    }
    return 0, false
}

incremental_llvm_resolve_native_targets :: proc(
    worker: ^Worker,
    program: ^repl_program.Program,
) -> (
    targets: [dynamic]Incremental_LLVM_Native_Targets,
    message: string,
    ok: bool,
) {
    if worker == nil || program == nil {
        return nil, strings.clone("incremental native context is unavailable"), false
    }
    for &procedure in program.procedures {
        target := Incremental_LLVM_Native_Targets{}
        resize(&target.slots, len(procedure.expressions))
        for &slot in target.slots {
            slot = -1
        }
        for expression, expression_index in procedure.expressions {
            if expression.kind != .Native_Call {
                continue
            }
            children, children_ok := incremental_llvm_children(
                &procedure,
                expression,
            )
            slot_index, slot_ok := incremental_llvm_find_scalar_slot_index(
                worker,
                expression.resolved_name,
                expression.scalar_signature,
            )
            if !children_ok || len(children) > 4 || !slot_ok {
                delete(target.slots)
                incremental_llvm_native_targets_delete(&targets)
                return nil,
                       strings.clone("incremental native scalar dependency is unavailable"),
                       false
            }
            invoke_slot := &worker.scalar_invoke_slots[slot_index]
            if invoke_slot.address == nil ||
               invoke_slot.result_abi != incremental_llvm_scalar_result_abi(
                   expression.value_kind,
               ) {
                delete(target.slots)
                incremental_llvm_native_targets_delete(&targets)
                return nil,
                       strings.clone("incremental native scalar dependency ABI changed"),
                       false
            }
            target.slots[expression_index] = slot_index
        }
        append(&targets, target)
    }
    return targets, "", true
}

worker_incremental_execution_status :: proc "c" (
    context_ptr: rawptr,
) -> Incremental_Call_Status {
    if context_ptr == nil {
        return .Failed
    }
    worker := transmute(^Worker)context_ptr
    if worker.incremental_call_failed {
        return .Failed
    }
    if worker.abort_requested {
        return .Aborted
    }
    return .Success
}

worker_incremental_managed_fail :: proc(worker: ^Worker) {
    if worker == nil {
        return
    }
    worker.incremental_call_failed = true
    worker.abort_requested = true
}

worker_incremental_managed_begin :: proc "c" (
    context_ptr: rawptr,
    slot_count: i64,
) -> rawptr {
    if context_ptr == nil {
        return nil
    }
    worker := transmute(^Worker)context_ptr
    context = runtime.default_context()
    context.allocator = worker.allocator
    if slot_count <= 0 || slot_count > repl_program.MAX_EXPRESSIONS {
        worker_incremental_managed_fail(worker)
        return nil
    }
    frame := new(Incremental_Managed_Frame)
    frame.worker = worker
    frame.allocator = worker.allocator
    resize(&frame.values, int(slot_count))
    resize(&frame.initialized, int(slot_count))
    return rawptr(frame)
}

worker_incremental_managed_end :: proc "c" (frame_ptr: rawptr) {
    if frame_ptr == nil {
        return
    }
    frame := transmute(^Incremental_Managed_Frame)frame_ptr
    context = runtime.default_context()
    context.allocator = frame.allocator
    worker := frame.worker
    if worker != nil {
        for value, index in frame.values {
            if index < len(frame.initialized) && frame.initialized[index] {
                worker_plan_value_release(
                    worker,
                    &frame.owned_values,
                    value,
                )
            }
        }
        worker_plan_owned_values_delete(worker, &frame.owned_values)
    }
    delete(frame.values)
    delete(frame.initialized)
    free(frame)
}

worker_incremental_managed_store :: proc "c" (
    context_ptr,
    frame_ptr: rawptr,
    slot_index: i64,
    result,
    destination: ^Scalar_Value,
) -> Incremental_Call_Status {
    if context_ptr == nil {
        return .Failed
    }
    worker := transmute(^Worker)context_ptr
    context = runtime.default_context()
    context.allocator = worker.allocator
    if frame_ptr == nil || result == nil || destination == nil {
        if result != nil {
            worker_release_owned_scalar_value(worker, result^)
            result^ = {}
        }
        worker_incremental_managed_fail(worker)
        return .Failed
    }
    frame := transmute(^Incremental_Managed_Frame)frame_ptr
    if frame.worker != worker || slot_index < 0 ||
       slot_index >= i64(len(frame.values)) ||
       result.kind != .String && result.kind != .Data {
        worker_release_owned_scalar_value(worker, result^)
        result^ = {}
        worker_incremental_managed_fail(worker)
        return .Failed
    }
    slot := int(slot_index)
    if frame.initialized[slot] {
        worker_plan_value_release(
            worker,
            &frame.owned_values,
            frame.values[slot],
        )
        frame.values[slot] = {}
        frame.initialized[slot] = false
    }
    value := Worker_Plan_Value{scalar = result^}
    if result.owned {
        adopted := false
        value, adopted = worker_plan_owned_value_adopt(
            worker,
            &frame.owned_values,
            result^,
        )
        if !adopted {
            worker_release_owned_scalar_value(worker, result^)
            result^ = {}
            worker_incremental_managed_fail(worker)
            return .Failed
        }
    } else if result.kind == .String {
        value.owner = worker_plan_owned_value_retain_string_alias(
            &frame.owned_values,
            result^,
        )
    } else {
        worker_incremental_managed_fail(worker)
        return .Failed
    }
    result^ = {}
    destination^ = value.scalar
    frame.values[slot] = value
    frame.initialized[slot] = true
    return .Success
}

worker_incremental_managed_release :: proc "c" (
    context_ptr,
    frame_ptr: rawptr,
    slot_index: i64,
    force_owner: u8,
) -> Incremental_Call_Status {
    if context_ptr == nil || frame_ptr == nil {
        return .Failed
    }
    worker := transmute(^Worker)context_ptr
    frame := transmute(^Incremental_Managed_Frame)frame_ptr
    context = runtime.default_context()
    context.allocator = frame.allocator
    if frame.worker != worker || slot_index < 0 ||
       slot_index >= i64(len(frame.values)) {
        worker_incremental_managed_fail(worker)
        return .Failed
    }
    slot := int(slot_index)
    if !frame.initialized[slot] {
        return .Success
    }
    value := frame.values[slot]
    if force_owner != 0 && value.owner > 0 {
        owner_index := value.owner-1
        if owner_index < 0 ||
           owner_index >= len(frame.owned_values.values) ||
           !frame.owned_values.values[owner_index].active {
            worker_incremental_managed_fail(worker)
            return .Failed
        }
        for &candidate, candidate_index in frame.values {
            if frame.initialized[candidate_index] &&
               candidate.owner == value.owner {
                candidate = {}
                frame.initialized[candidate_index] = false
            }
        }
        owned := &frame.owned_values.values[owner_index]
        worker_release_owned_scalar_value(worker, owned.scalar)
        if owned.scalar.kind == .String {
            frame.owned_values.live_string_bytes -=
                owned.scalar.string_length
        }
        frame.owned_values.live_values -= 1
        owned^ = {}
        return .Success
    }
    worker_plan_value_release(
        worker,
        &frame.owned_values,
        value,
    )
    frame.values[slot] = {}
    frame.initialized[slot] = false
    return .Success
}

worker_incremental_invoke_scalar :: proc "c" (
    context_ptr: rawptr,
    slot_index: i64,
    args: [^]Scalar_Value,
    arg_count: i64,
    result: ^Scalar_Value,
) -> Incremental_Call_Status {
    if context_ptr == nil {
        return .Failed
    }
    worker := transmute(^Worker)context_ptr
    context = runtime.default_context()
    context.allocator = worker.allocator
    if slot_index < 0 || slot_index >= i64(len(worker.scalar_invoke_slots)) ||
       arg_count < 0 || arg_count > 4 || result == nil {
        worker.incremental_call_failed = true
        worker.abort_requested = true
        return .Failed
    }
    invoke_slot := &worker.scalar_invoke_slots[int(slot_index)]
    if invoke_slot.address == nil {
        worker.incremental_call_failed = true
        worker.abort_requested = true
        return .Failed
    }
    result^ = {}
    invoked := invoke_slot.address(args, int(arg_count), result)
    if !invoked || !worker_plan_scalar_result_valid(result^, invoke_slot) {
        worker_release_owned_scalar_value(worker, result^)
        result^ = {}
        worker_incremental_managed_fail(worker)
        return .Failed
    }
    if worker.abort_requested {
        worker_release_owned_scalar_value(worker, result^)
        result^ = {}
        return .Aborted
    }
    return .Success
}

incremental_llvm_emit_if :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    expression: repl_program.Expression,
) -> Incremental_LLVM_Value {
    children, children_ok := incremental_llvm_children(
        emitter.procedure,
        expression,
    )
    if !children_ok || len(children) != 3 {
        emitter.failed = true
        return {}
    }
    condition := incremental_llvm_emit_expression(emitter, children[0])
    defer incremental_llvm_value_delete(&condition)
    if emitter.failed || condition.kind != .Bool {
        emitter.failed = true
        return {}
    }
    then_block := incremental_llvm_fresh_block(emitter, "if.then")
    else_block := incremental_llvm_fresh_block(emitter, "if.else")
    merge_block := incremental_llvm_fresh_block(emitter, "if.merge")
    defer delete(then_block)
    defer delete(else_block)
    defer delete(merge_block)
    fmt.sbprintf(
        emitter.output,
        "  br i1 %s, label %%%s, label %%%s\n",
        condition.text,
        then_block,
        else_block,
    )
    incremental_llvm_start_block(emitter, then_block)
    then_value := incremental_llvm_emit_expression(emitter, children[1])
    defer incremental_llvm_value_delete(&then_value)
    then_terminated := emitter.terminated
    then_predecessor := strings.clone(emitter.current_block)
    defer delete(then_predecessor)
    if !emitter.failed && !then_terminated {
        fmt.sbprintf(emitter.output, "  br label %%%s\n", merge_block)
    }
    incremental_llvm_start_block(emitter, else_block)
    else_value := incremental_llvm_emit_expression(emitter, children[2])
    defer incremental_llvm_value_delete(&else_value)
    else_terminated := emitter.terminated
    else_predecessor := strings.clone(emitter.current_block)
    defer delete(else_predecessor)
    if emitter.failed {
        emitter.failed = true
        return {}
    }
    if !else_terminated {
        fmt.sbprintf(emitter.output, "  br label %%%s\n", merge_block)
    }
    if then_terminated && else_terminated {
        emitter.terminated = true
        return {kind = .Void}
    }
    incremental_llvm_start_block(emitter, merge_block)
    if expression.value_kind == .Void {
        return {kind = .Void}
    }
    if (!then_terminated && then_value.kind != expression.value_kind) ||
       (!else_terminated && else_value.kind != expression.value_kind) {
        emitter.failed = true
        return {}
    }
    if then_terminated {
        return {
            text = strings.clone(else_value.text),
            kind = expression.value_kind,
        }
    }
    if else_terminated {
        return {
            text = strings.clone(then_value.text),
            kind = expression.value_kind,
        }
    }
    result := incremental_llvm_fresh_value(emitter)
    fmt.sbprintf(
        emitter.output,
        "  %s = phi %s [ %s, %%%s ], [ %s, %%%s ]\n",
        result,
        incremental_llvm_type(expression.value_kind),
        then_value.text,
        then_predecessor,
        else_value.text,
        else_predecessor,
    )
    return {text = result, kind = expression.value_kind}
}

incremental_llvm_emit_short_circuit :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    expression: repl_program.Expression,
) -> Incremental_LLVM_Value {
    children, children_ok := incremental_llvm_children(
        emitter.procedure,
        expression,
    )
    if !children_ok || len(children) < 2 ||
       (expression.kind != .And && expression.kind != .Or) {
        emitter.failed = true
        return {}
    }
    merge_block := incremental_llvm_fresh_block(emitter, "bool.merge")
    defer delete(merge_block)
    predecessors: [dynamic]string
    defer {
        for predecessor in predecessors {
            delete(predecessor)
        }
        delete(predecessors)
    }
    last_value := Incremental_LLVM_Value{}
    defer incremental_llvm_value_delete(&last_value)
    last_predecessor := ""
    defer delete(last_predecessor)
    for child, index in children {
        value := incremental_llvm_emit_expression(emitter, child)
        if emitter.failed || value.kind != .Bool {
            incremental_llvm_value_delete(&value)
            emitter.failed = true
            return {}
        }
        if index+1 == len(children) {
            last_value = value
            last_predecessor = strings.clone(emitter.current_block)
            fmt.sbprintf(emitter.output, "  br label %%%s\n", merge_block)
            break
        }
        predecessor := strings.clone(emitter.current_block)
        append(&predecessors, predecessor)
        next_block := incremental_llvm_fresh_block(emitter, "bool.next")
        if expression.kind == .And {
            fmt.sbprintf(
                emitter.output,
                "  br i1 %s, label %%%s, label %%%s\n",
                value.text,
                next_block,
                merge_block,
            )
        } else {
            fmt.sbprintf(
                emitter.output,
                "  br i1 %s, label %%%s, label %%%s\n",
                value.text,
                merge_block,
                next_block,
            )
        }
        incremental_llvm_value_delete(&value)
        incremental_llvm_start_block(emitter, next_block)
        delete(next_block)
    }
    incremental_llvm_start_block(emitter, merge_block)
    result := incremental_llvm_fresh_value(emitter)
    fmt.sbprintf(emitter.output, "  %s = phi i1 ", result)
    short_value := "false" if expression.kind == .And else "true"
    for predecessor, index in predecessors {
        if index > 0 {
            strings.write_string(emitter.output, ", ")
        }
        fmt.sbprintf(
            emitter.output,
            "[ %s, %%%s ]",
            short_value,
            predecessor,
        )
    }
    if len(predecessors) > 0 {
        strings.write_string(emitter.output, ", ")
    }
    fmt.sbprintf(
        emitter.output,
        "[ %s, %%%s ]\n",
        last_value.text,
        last_predecessor,
    )
    return {text = result, kind = .Bool}
}

incremental_llvm_emit_default_return :: proc(
    emitter: ^Incremental_LLVM_Emitter,
) -> bool {
    if emitter == nil || emitter.procedure == nil {
        return false
    }
    if !incremental_llvm_emit_managed_cleanup(emitter) {
        return false
    }
    switch emitter.procedure.result_kind {
    case .Bool:
        strings.write_string(emitter.output, "  ret i8 0\n")
    case .Int:
        fmt.sbprintf(
            emitter.output,
            "  ret %s 0\n",
            incremental_llvm_type(.Int),
        )
    case .F64:
        strings.write_string(emitter.output, "  ret double 0.0\n")
    case .Invalid, .Void, .String, .Data:
        return false
    }
    return true
}

incremental_llvm_emit_managed_cleanup :: proc(
    emitter: ^Incremental_LLVM_Emitter,
) -> bool {
    if emitter == nil {
        return false
    }
    if emitter.managed_frame_pointer == "" {
        return true
    }
    if emitter.managed_end_address == 0 {
        return false
    }
    fmt.sbprintf(
        emitter.output,
        "  call void inttoptr (%s %d to ptr)(ptr %s)\n",
        incremental_llvm_pointer_int_type(),
        emitter.managed_end_address,
        emitter.managed_frame_pointer,
    )
    return true
}

incremental_llvm_emit_managed_slot_release :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    cleanup: Incremental_LLVM_Managed_Cleanup,
) -> bool {
    if emitter == nil || cleanup.slot_index < 0 ||
       cleanup.slot_index >= len(emitter.managed_pointers) {
        return false
    }
    if emitter.managed_frame_pointer == "" {
        return true
    }
    if emitter.managed_release_address == 0 ||
       emitter.managed_pointers[cleanup.slot_index] == "" {
        return false
    }
    release_status := incremental_llvm_fresh_value(emitter)
    fmt.sbprintf(
        emitter.output,
        "  %s = call i8 inttoptr (%s %d to ptr)(" +
        "ptr inttoptr (%s %d to ptr), ptr %s, i64 %d, i8 %d)\n",
        release_status,
        incremental_llvm_pointer_int_type(),
        emitter.managed_release_address,
        incremental_llvm_pointer_int_type(),
        emitter.worker_address,
        emitter.managed_frame_pointer,
        cleanup.slot_index,
        1 if cleanup.force_owner else 0,
    )
    released := incremental_llvm_emit_status_guard(
        emitter,
        release_status,
    )
    delete(release_status)
    return released
}

incremental_llvm_emit_active_managed_cleanups :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    depth: int,
) -> bool {
    if emitter == nil || depth < 0 ||
       depth > len(emitter.active_managed_cleanups) {
        return false
    }
    index := len(emitter.active_managed_cleanups)-1
    for index >= depth {
        if !incremental_llvm_emit_managed_slot_release(
            emitter,
            emitter.active_managed_cleanups[index],
        ) {
            return false
        }
        index -= 1
    }
    return true
}

incremental_llvm_emit_status_guard :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    status: string,
) -> bool {
    if emitter == nil || status == "" {
        return false
    }
    status_ok := incremental_llvm_fresh_value(emitter)
    defer delete(status_ok)
    continue_block := incremental_llvm_fresh_block(emitter, "call.continue")
    failure_block := incremental_llvm_fresh_block(emitter, "call.exit")
    defer delete(continue_block)
    defer delete(failure_block)
    fmt.sbprintf(
        emitter.output,
        "  %s = icmp eq i8 %s, %d\n" +
        "  br i1 %s, label %%%s, label %%%s\n",
        status_ok,
        status,
        int(Incremental_Call_Status.Success),
        status_ok,
        continue_block,
        failure_block,
    )
    incremental_llvm_start_block(emitter, failure_block)
    if !incremental_llvm_emit_default_return(emitter) {
        return false
    }
    incremental_llvm_start_block(emitter, continue_block)
    return true
}

incremental_llvm_emit_current_status :: proc(
    emitter: ^Incremental_LLVM_Emitter,
) -> bool {
    if emitter == nil || emitter.worker_address == 0 ||
       emitter.status_address == 0 {
        return false
    }
    status := incremental_llvm_fresh_value(emitter)
    defer delete(status)
    fmt.sbprintf(
        emitter.output,
        "  %s = call i8 inttoptr (%s %d to ptr)(" +
        "ptr inttoptr (%s %d to ptr))\n",
        status,
        incremental_llvm_pointer_int_type(),
        emitter.status_address,
        incremental_llvm_pointer_int_type(),
        emitter.worker_address,
    )
    return incremental_llvm_emit_status_guard(emitter, status)
}

incremental_llvm_emit_call :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    expression: repl_program.Expression,
) -> Incremental_LLVM_Value {
    if expression.kind != .Program_Call {
        emitter.failed = true
        return {}
    }
    target_index, target_ok := incremental_llvm_program_proc_index(
        emitter.program,
        expression.resolved_name,
        expression.scalar_signature,
    )
    children, children_ok := incremental_llvm_children(
        emitter.procedure,
        expression,
    )
    if !target_ok || !children_ok ||
       target_index >= len(emitter.function_names) {
        emitter.failed = true
        return {}
    }
    target := &emitter.program.procedures[target_index]
    if len(children) != len(target.parameter_kinds) ||
       expression.value_kind != target.result_kind {
        emitter.failed = true
        return {}
    }
    arguments: [dynamic]Incremental_LLVM_Value
    defer {
        for &argument in arguments {
            incremental_llvm_value_delete(&argument)
        }
        delete(arguments)
    }
    for child, index in children {
        value := incremental_llvm_emit_expression(emitter, child)
        if emitter.failed || value.kind != target.parameter_kinds[index] {
            incremental_llvm_value_delete(&value)
            emitter.failed = true
            return {}
        }
        append(&arguments, value)
    }
    raw_result := incremental_llvm_fresh_value(emitter)
    fmt.sbprintf(
        emitter.output,
        "  %s = call %s @%s(",
        raw_result,
        incremental_llvm_internal_return_type(target.result_kind),
        emitter.function_names[target_index],
    )
    for argument, index in arguments {
        if index > 0 {
            strings.write_string(emitter.output, ", ")
        }
        fmt.sbprintf(
            emitter.output,
            "%s %s",
            incremental_llvm_type(argument.kind),
            argument.text,
        )
    }
    if len(arguments) > 0 {
        strings.write_string(emitter.output, ", ")
    }
    strings.write_string(emitter.output, "ptr %ctx)\n")
    if emitter.guard_call_status &&
       !incremental_llvm_emit_current_status(emitter) {
        emitter.failed = true
        delete(raw_result)
        return {}
    }
    if target.result_kind != .Bool {
        return {text = raw_result, kind = target.result_kind}
    }
    bool_result := incremental_llvm_fresh_value(emitter)
    fmt.sbprintf(
        emitter.output,
        "  %s = trunc i8 %s to i1\n",
        bool_result,
        raw_result,
    )
    delete(raw_result)
    return {text = bool_result, kind = .Bool}
}

incremental_llvm_emit_managed_argument :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    argument: Incremental_LLVM_Value,
    destination: string,
) -> bool {
    if emitter == nil || argument.text == "" || destination == "" ||
       (argument.kind != .String && argument.kind != .Data) {
        return false
    }
    probe := Scalar_Value{}
    if argument.kind == .String {
        data_offset := int(uintptr(&probe.string_data)-uintptr(&probe))
        length_offset := int(uintptr(&probe.string_length)-uintptr(&probe))
        source_data_pointer := incremental_llvm_fresh_value(emitter)
        data_value := incremental_llvm_fresh_value(emitter)
        destination_data_pointer := incremental_llvm_fresh_value(emitter)
        source_length_pointer := incremental_llvm_fresh_value(emitter)
        length_value := incremental_llvm_fresh_value(emitter)
        destination_length_pointer := incremental_llvm_fresh_value(emitter)
        defer {
            delete(source_data_pointer)
            delete(data_value)
            delete(destination_data_pointer)
            delete(source_length_pointer)
            delete(length_value)
            delete(destination_length_pointer)
        }
        fmt.sbprintf(
            emitter.output,
            "  %s = getelementptr i8, ptr %s, i64 %d\n" +
            "  %s = load ptr, ptr %s\n" +
            "  %s = getelementptr i8, ptr %s, i64 %d\n" +
            "  store ptr %s, ptr %s\n" +
            "  %s = getelementptr i8, ptr %s, i64 %d\n" +
            "  %s = load %s, ptr %s\n" +
            "  %s = getelementptr i8, ptr %s, i64 %d\n" +
            "  store %s %s, ptr %s\n",
            source_data_pointer,
            argument.text,
            data_offset,
            data_value,
            source_data_pointer,
            destination_data_pointer,
            destination,
            data_offset,
            data_value,
            destination_data_pointer,
            source_length_pointer,
            argument.text,
            length_offset,
            length_value,
            incremental_llvm_type(.Int),
            source_length_pointer,
            destination_length_pointer,
            destination,
            length_offset,
            incremental_llvm_type(.Int),
            length_value,
            destination_length_pointer,
        )
        return true
    }
    source_address_offset := int(
        uintptr(&probe.source_address)-uintptr(&probe),
    )
    source_value_offset := int(uintptr(&probe.source_value)-uintptr(&probe))
    offsets := [?]int{source_address_offset, source_value_offset}
    for offset in offsets {
        source_pointer := incremental_llvm_fresh_value(emitter)
        value := incremental_llvm_fresh_value(emitter)
        destination_pointer := incremental_llvm_fresh_value(emitter)
        fmt.sbprintf(
            emitter.output,
            "  %s = getelementptr i8, ptr %s, i64 %d\n" +
            "  %s = load ptr, ptr %s\n" +
            "  %s = getelementptr i8, ptr %s, i64 %d\n" +
            "  store ptr %s, ptr %s\n",
            source_pointer,
            argument.text,
            offset,
            value,
            source_pointer,
            destination_pointer,
            destination,
            offset,
            value,
            destination_pointer,
        )
        delete(source_pointer)
        delete(value)
        delete(destination_pointer)
    }
    return true
}

incremental_llvm_emit_native_call :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    expression: repl_program.Expression,
    expression_index: int,
) -> Incremental_LLVM_Value {
    children, children_ok := incremental_llvm_children(
        emitter.procedure,
        expression,
    )
    if !children_ok || len(children) > 4 || expression_index < 0 ||
       expression_index >= len(emitter.native_slots) ||
       emitter.native_slots[expression_index] < 0 ||
       emitter.native_args_pointer == "" ||
       emitter.native_result_pointer == "" ||
       emitter.worker_address == 0 || emitter.invoke_address == 0 {
        emitter.failed = true
        return {}
    }
    arguments: [dynamic]Incremental_LLVM_Value
    defer {
        for &argument in arguments {
            incremental_llvm_value_delete(&argument)
        }
        delete(arguments)
    }
    // Evaluate every argument before writing the shared scratch area. A
    // nested native call may use the same area in the current stack frame.
    for child in children {
        argument := incremental_llvm_emit_expression(emitter, child)
        if emitter.failed || argument.text == "" ||
           argument.kind == .Invalid || argument.kind == .Void {
            incremental_llvm_value_delete(&argument)
            emitter.failed = true
            return {}
        }
        append(&arguments, argument)
    }
    probe := Scalar_Value{}
    kind_offset := int(uintptr(&probe.kind)-uintptr(&probe))
    int_offset := int(uintptr(&probe.int_value)-uintptr(&probe))
    float_offset := int(uintptr(&probe.float_value)-uintptr(&probe))
    stride := size_of(Scalar_Value)
    for argument, index in arguments {
        kind_pointer := incremental_llvm_fresh_value(emitter)
        fmt.sbprintf(
            emitter.output,
            "  %s = getelementptr i8, ptr %s, i64 %d\n" +
            "  store i32 %d, ptr %s, align 4\n",
            kind_pointer,
            emitter.native_args_pointer,
            index*stride+kind_offset,
            incremental_llvm_scalar_kind(argument.kind),
            kind_pointer,
        )
        delete(kind_pointer)
        if argument.kind == .String || argument.kind == .Data {
            destination := incremental_llvm_fresh_value(emitter)
            fmt.sbprintf(
                emitter.output,
                "  %s = getelementptr i8, ptr %s, i64 %d\n",
                destination,
                emitter.native_args_pointer,
                index*stride,
            )
            if !incremental_llvm_emit_managed_argument(
                emitter,
                argument,
                destination,
            ) {
                delete(destination)
                emitter.failed = true
                return {}
            }
            delete(destination)
            continue
        }
        if argument.kind == .F64 {
            value_pointer := incremental_llvm_fresh_value(emitter)
            fmt.sbprintf(
                emitter.output,
                "  %s = getelementptr i8, ptr %s, i64 %d\n" +
                "  store double %s, ptr %s, align 8\n",
                value_pointer,
                emitter.native_args_pointer,
                index*stride+float_offset,
                argument.text,
                value_pointer,
            )
            delete(value_pointer)
            continue
        }
        stored_value := strings.clone(argument.text)
        if argument.kind == .Bool {
            delete(stored_value)
            stored_value = incremental_llvm_fresh_value(emitter)
            fmt.sbprintf(
                emitter.output,
                "  %s = zext i1 %s to i64\n",
                stored_value,
                argument.text,
            )
        } else if size_of(int) != 8 {
            delete(stored_value)
            stored_value = incremental_llvm_fresh_value(emitter)
            fmt.sbprintf(
                emitter.output,
                "  %s = sext i32 %s to i64\n",
                stored_value,
                argument.text,
            )
        }
        value_pointer := incremental_llvm_fresh_value(emitter)
        fmt.sbprintf(
            emitter.output,
            "  %s = getelementptr i8, ptr %s, i64 %d\n" +
            "  store i64 %s, ptr %s, align 8\n",
            value_pointer,
            emitter.native_args_pointer,
            index*stride+int_offset,
            stored_value,
            value_pointer,
        )
        delete(value_pointer)
        delete(stored_value)
    }
    status := incremental_llvm_fresh_value(emitter)
    fmt.sbprintf(
        emitter.output,
        "  %s = call i8 inttoptr (%s %d to ptr)(" +
        "ptr inttoptr (%s %d to ptr), i64 %d, ptr %s, i64 %d, ptr %s)\n",
        status,
        incremental_llvm_pointer_int_type(),
        emitter.invoke_address,
        incremental_llvm_pointer_int_type(),
        emitter.worker_address,
        emitter.native_slots[expression_index],
        emitter.native_args_pointer,
        len(arguments),
        emitter.native_result_pointer,
    )
    if !incremental_llvm_emit_status_guard(emitter, status) {
        delete(status)
        emitter.failed = true
        return {}
    }
    delete(status)
    if expression.value_kind == .String || expression.value_kind == .Data {
        if emitter.managed_frame_pointer == "" ||
           emitter.managed_store_address == 0 || expression_index < 0 ||
           expression_index >= len(emitter.managed_pointers) ||
           emitter.managed_pointers[expression_index] == "" {
            emitter.failed = true
            return {}
        }
        stored_status := incremental_llvm_fresh_value(emitter)
        fmt.sbprintf(
            emitter.output,
            "  %s = call i8 inttoptr (%s %d to ptr)(" +
            "ptr inttoptr (%s %d to ptr), ptr %s, i64 %d, ptr %s, ptr %s)\n",
            stored_status,
            incremental_llvm_pointer_int_type(),
            emitter.managed_store_address,
            incremental_llvm_pointer_int_type(),
            emitter.worker_address,
            emitter.managed_frame_pointer,
            expression_index,
            emitter.native_result_pointer,
            emitter.managed_pointers[expression_index],
        )
        if !incremental_llvm_emit_status_guard(emitter, stored_status) {
            delete(stored_status)
            emitter.failed = true
            return {}
        }
        delete(stored_status)
        return {
            text = strings.clone(emitter.managed_pointers[expression_index]),
            kind = expression.value_kind,
        }
    }
    if expression.value_kind == .F64 {
        value_pointer := incremental_llvm_fresh_value(emitter)
        result := incremental_llvm_fresh_value(emitter)
        fmt.sbprintf(
            emitter.output,
            "  %s = getelementptr i8, ptr %s, i64 %d\n" +
            "  %s = load double, ptr %s, align 8\n",
            value_pointer,
            emitter.native_result_pointer,
            float_offset,
            result,
            value_pointer,
        )
        delete(value_pointer)
        return {text = result, kind = .F64}
    }
    value_pointer := incremental_llvm_fresh_value(emitter)
    raw_result := incremental_llvm_fresh_value(emitter)
    fmt.sbprintf(
        emitter.output,
        "  %s = getelementptr i8, ptr %s, i64 %d\n" +
        "  %s = load i64, ptr %s, align 8\n",
        value_pointer,
        emitter.native_result_pointer,
        int_offset,
        raw_result,
        value_pointer,
    )
    delete(value_pointer)
    if expression.value_kind == .Int && size_of(int) == 8 {
        return {text = raw_result, kind = .Int}
    }
    result := incremental_llvm_fresh_value(emitter)
    if expression.value_kind == .Bool {
        fmt.sbprintf(
            emitter.output,
            "  %s = trunc i64 %s to i1\n",
            result,
            raw_result,
        )
    } else if expression.value_kind == .Int {
        fmt.sbprintf(
            emitter.output,
            "  %s = trunc i64 %s to i32\n",
            result,
            raw_result,
        )
    } else {
        delete(result)
        delete(raw_result)
        emitter.failed = true
        return {}
    }
    delete(raw_result)
    return {text = result, kind = expression.value_kind}
}

incremental_llvm_string_literal_name :: proc(
    function_name: string,
    expression_index: int,
) -> string {
    return fmt.aprintf("%s_string_%d", function_name, expression_index)
}

incremental_llvm_emit_string_literal :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    expression: repl_program.Expression,
    expression_index: int,
) -> Incremental_LLVM_Value {
    if emitter == nil || emitter.procedure_index < 0 ||
       emitter.procedure_index >= len(emitter.function_names) ||
       expression_index < 0 ||
       expression_index >= len(emitter.managed_pointers) ||
       emitter.managed_pointers[expression_index] == "" {
        if emitter != nil {
            emitter.failed = true
        }
        return {}
    }
    name := incremental_llvm_string_literal_name(
        emitter.function_names[emitter.procedure_index],
        expression_index,
    )
    defer delete(name)
    byte_count := len(expression.string_value)
    storage_count := byte_count if byte_count > 0 else 1
    data := incremental_llvm_fresh_value(emitter)
    defer delete(data)
    fmt.sbprintf(
        emitter.output,
        "  %s = getelementptr [%d x i8], ptr @%s, i64 0, i64 0\n",
        data,
        storage_count,
        name,
    )
    probe := Scalar_Value{}
    kind_offset := int(uintptr(&probe.kind)-uintptr(&probe))
    data_offset := int(uintptr(&probe.string_data)-uintptr(&probe))
    length_offset := int(uintptr(&probe.string_length)-uintptr(&probe))
    kind_pointer := incremental_llvm_fresh_value(emitter)
    data_pointer := incremental_llvm_fresh_value(emitter)
    length_pointer := incremental_llvm_fresh_value(emitter)
    defer {
        delete(kind_pointer)
        delete(data_pointer)
        delete(length_pointer)
    }
    destination := emitter.managed_pointers[expression_index]
    fmt.sbprintf(
        emitter.output,
        "  %s = getelementptr i8, ptr %s, i64 %d\n" +
        "  store i32 %d, ptr %s, align 4\n" +
        "  %s = getelementptr i8, ptr %s, i64 %d\n" +
        "  store ptr %s, ptr %s\n" +
        "  %s = getelementptr i8, ptr %s, i64 %d\n" +
        "  store %s %d, ptr %s\n",
        kind_pointer,
        destination,
        kind_offset,
        incremental_llvm_scalar_kind(.String),
        kind_pointer,
        data_pointer,
        destination,
        data_offset,
        data,
        data_pointer,
        length_pointer,
        destination,
        length_offset,
        incremental_llvm_type(.Int),
        byte_count,
        length_pointer,
    )
    return {
        text = strings.clone(destination),
        kind = .String,
    }
}

incremental_llvm_emit_numeric :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    expression: repl_program.Expression,
) -> Incremental_LLVM_Value {
    children, children_ok := incremental_llvm_children(
        emitter.procedure,
        expression,
    )
    if !children_ok || len(children) == 0 ||
       (expression.value_kind != .Int && expression.value_kind != .F64) {
        emitter.failed = true
        return {}
    }
    accumulator := incremental_llvm_emit_expression(emitter, children[0])
    if emitter.failed || accumulator.kind != expression.value_kind {
        incremental_llvm_value_delete(&accumulator)
        emitter.failed = true
        return {}
    }
    if expression.kind == .Subtract && len(children) == 1 {
        result := incremental_llvm_fresh_value(emitter)
        if expression.value_kind == .Int {
            fmt.sbprintf(
                emitter.output,
                "  %s = sub %s 0, %s\n",
                result,
                incremental_llvm_type(.Int),
                accumulator.text,
            )
        } else {
            fmt.sbprintf(
                emitter.output,
                "  %s = fneg double %s\n",
                result,
                accumulator.text,
            )
        }
        incremental_llvm_value_delete(&accumulator)
        return {text = result, kind = expression.value_kind}
    }
    for child in children[1:] {
        operand := incremental_llvm_emit_expression(emitter, child)
        if emitter.failed || operand.kind != expression.value_kind {
            incremental_llvm_value_delete(&operand)
            incremental_llvm_value_delete(&accumulator)
            emitter.failed = true
            return {}
        }
        opcode := ""
        if expression.value_kind == .Int {
            #partial switch expression.kind {
            case .Add:      opcode = "add"
            case .Subtract: opcode = "sub"
            case .Multiply: opcode = "mul"
            case .Divide:   opcode = "sdiv"
            case .Modulo:   opcode = "srem"
            case:           emitter.failed = true
            }
        } else {
            #partial switch expression.kind {
            case .Add:      opcode = "fadd"
            case .Subtract: opcode = "fsub"
            case .Multiply: opcode = "fmul"
            case .Divide:   opcode = "fdiv"
            case:           emitter.failed = true
            }
        }
        if emitter.failed {
            incremental_llvm_value_delete(&operand)
            incremental_llvm_value_delete(&accumulator)
            return {}
        }
        result := incremental_llvm_fresh_value(emitter)
        fmt.sbprintf(
            emitter.output,
            "  %s = %s %s %s, %s\n",
            result,
            opcode,
            incremental_llvm_type(expression.value_kind),
            accumulator.text,
            operand.text,
        )
        incremental_llvm_value_delete(&operand)
        incremental_llvm_value_delete(&accumulator)
        accumulator = {text = result, kind = expression.value_kind}
    }
    return accumulator
}

incremental_llvm_emit_compare :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    expression: repl_program.Expression,
) -> Incremental_LLVM_Value {
    children, children_ok := incremental_llvm_children(
        emitter.procedure,
        expression,
    )
    if !children_ok || len(children) != 2 {
        emitter.failed = true
        return {}
    }
    left := incremental_llvm_emit_expression(emitter, children[0])
    defer incremental_llvm_value_delete(&left)
    right := incremental_llvm_emit_expression(emitter, children[1])
    defer incremental_llvm_value_delete(&right)
    if emitter.failed || left.kind != right.kind ||
       (left.kind != .Bool && left.kind != .Int && left.kind != .F64) {
        emitter.failed = true
        return {}
    }
    predicate := ""
    prefix := "icmp"
    if left.kind == .F64 {
        prefix = "fcmp"
        #partial switch expression.kind {
        case .Equal:         predicate = "oeq"
        case .Not_Equal:     predicate = "une"
        case .Less:          predicate = "olt"
        case .Less_Equal:    predicate = "ole"
        case .Greater:       predicate = "ogt"
        case .Greater_Equal: predicate = "oge"
        case:                emitter.failed = true
        }
    } else {
        #partial switch expression.kind {
        case .Equal:         predicate = "eq"
        case .Not_Equal:     predicate = "ne"
        case .Less:          predicate = "slt"
        case .Less_Equal:    predicate = "sle"
        case .Greater:       predicate = "sgt"
        case .Greater_Equal: predicate = "sge"
        case:                emitter.failed = true
        }
        if left.kind == .Bool && expression.kind != .Equal &&
           expression.kind != .Not_Equal {
            emitter.failed = true
        }
    }
    if emitter.failed {
        return {}
    }
    result := incremental_llvm_fresh_value(emitter)
    fmt.sbprintf(
        emitter.output,
        "  %s = %s %s %s %s, %s\n",
        result,
        prefix,
        predicate,
        incremental_llvm_type(left.kind),
        left.text,
        right.text,
    )
    return {text = result, kind = .Bool}
}

incremental_llvm_store_local :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    slot: int,
    value: Incremental_LLVM_Value,
) -> bool {
    if emitter == nil || slot < 0 || slot >= len(emitter.locals) ||
       emitter.locals[slot].kind != value.kind ||
       emitter.locals[slot].pointer == "" || value.text == "" {
        return false
    }
    fmt.sbprintf(
        emitter.output,
        "  store %s %s, ptr %s\n",
        incremental_llvm_type(value.kind),
        value.text,
        emitter.locals[slot].pointer,
    )
    return true
}

incremental_llvm_emit_return_value :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    value: Incremental_LLVM_Value,
) -> bool {
    if emitter == nil || emitter.procedure == nil ||
       value.kind != emitter.procedure.result_kind || value.text == "" {
        return false
    }
    if !incremental_llvm_emit_managed_cleanup(emitter) {
        return false
    }
    if value.kind == .Bool {
        widened := incremental_llvm_fresh_value(emitter)
        defer delete(widened)
        fmt.sbprintf(
            emitter.output,
            "  %s = zext i1 %s to i8\n  ret i8 %s\n",
            widened,
            value.text,
            widened,
        )
    } else {
        fmt.sbprintf(
            emitter.output,
            "  ret %s %s\n",
            incremental_llvm_type(value.kind),
            value.text,
        )
    }
    emitter.terminated = true
    return true
}

incremental_llvm_emit_sequence :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    expression: repl_program.Expression,
) -> Incremental_LLVM_Value {
    children, children_ok := incremental_llvm_children(
        emitter.procedure,
        expression,
    )
    if !children_ok {
        emitter.failed = true
        return {}
    }
    result := Incremental_LLVM_Value{kind = .Void}
    for child in children {
        incremental_llvm_value_delete(&result)
        result = incremental_llvm_emit_expression(emitter, child)
        if emitter.failed || emitter.terminated {
            break
        }
    }
    if emitter.failed {
        incremental_llvm_value_delete(&result)
        return {}
    }
    if emitter.terminated {
        incremental_llvm_value_delete(&result)
        return {kind = .Void}
    }
    if expression.value_kind == .Void {
        incremental_llvm_value_delete(&result)
        return {kind = .Void}
    }
    if result.kind != expression.value_kind {
        incremental_llvm_value_delete(&result)
        emitter.failed = true
        return {}
    }
    return result
}

incremental_llvm_emit_while :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    expression: repl_program.Expression,
) -> Incremental_LLVM_Value {
    children, children_ok := incremental_llvm_children(
        emitter.procedure,
        expression,
    )
    if !children_ok || len(children) != 2 ||
       expression.value_kind != .Void {
        emitter.failed = true
        return {}
    }
    condition_block := incremental_llvm_fresh_block(emitter, "while.cond")
    body_block := incremental_llvm_fresh_block(emitter, "while.body")
    exit_block := incremental_llvm_fresh_block(emitter, "while.exit")
    defer delete(condition_block)
    defer delete(body_block)
    defer delete(exit_block)
    fmt.sbprintf(emitter.output, "  br label %%%s\n", condition_block)
    incremental_llvm_start_block(emitter, condition_block)
    condition := incremental_llvm_emit_expression(emitter, children[0])
    defer incremental_llvm_value_delete(&condition)
    if emitter.failed || emitter.terminated || condition.kind != .Bool {
        emitter.failed = true
        return {}
    }
    fmt.sbprintf(
        emitter.output,
        "  br i1 %s, label %%%s, label %%%s\n",
        condition.text,
        body_block,
        exit_block,
    )
    incremental_llvm_start_block(emitter, body_block)
    append(&emitter.loop_condition_blocks, condition_block)
    append(&emitter.loop_exit_blocks, exit_block)
    append(
        &emitter.loop_cleanup_depths,
        len(emitter.active_managed_cleanups),
    )
    body := incremental_llvm_emit_expression(emitter, children[1])
    incremental_llvm_value_delete(&body)
    resize(
        &emitter.loop_condition_blocks,
        len(emitter.loop_condition_blocks)-1,
    )
    resize(&emitter.loop_exit_blocks, len(emitter.loop_exit_blocks)-1)
    resize(&emitter.loop_cleanup_depths, len(emitter.loop_cleanup_depths)-1)
    if emitter.failed {
        return {}
    }
    if !emitter.terminated {
        fmt.sbprintf(emitter.output, "  br label %%%s\n", condition_block)
    }
    incremental_llvm_start_block(emitter, exit_block)
    return {kind = .Void}
}

incremental_llvm_emit_expression :: proc(
    emitter: ^Incremental_LLVM_Emitter,
    expression_index: int,
) -> Incremental_LLVM_Value {
    if emitter == nil || emitter.procedure == nil ||
       expression_index < 0 ||
       expression_index >= len(emitter.procedure.expressions) {
        if emitter != nil {
            emitter.failed = true
        }
        return {}
    }
    expression := emitter.procedure.expressions[expression_index]
    switch expression.kind {
    case .Sequence:
        return incremental_llvm_emit_sequence(emitter, expression)
    case .Discard:
        children, children_ok := incremental_llvm_children(
            emitter.procedure,
            expression,
        )
        if !children_ok || expression.value_kind != .Void {
            emitter.failed = true
            return {}
        }
        for child in children {
            value := incremental_llvm_emit_expression(emitter, child)
            incremental_llvm_value_delete(&value)
            if emitter.failed || emitter.terminated {
                break
            }
        }
        return {kind = .Void}
    case .Set_Local:
        children, children_ok := incremental_llvm_children(
            emitter.procedure,
            expression,
        )
        if !children_ok || len(children) != 1 ||
           expression.value_kind != .Void {
            emitter.failed = true
            return {}
        }
        value := incremental_llvm_emit_expression(emitter, children[0])
        defer incremental_llvm_value_delete(&value)
        if emitter.failed || emitter.terminated ||
           !incremental_llvm_store_local(emitter, expression.operand, value) {
            emitter.failed = true
            return {}
        }
        return {kind = .Void}
    case .While:
        return incremental_llvm_emit_while(emitter, expression)
    case .Return:
        children, children_ok := incremental_llvm_children(
            emitter.procedure,
            expression,
        )
        if !children_ok || len(children) != 1 ||
           expression.value_kind != .Void {
            emitter.failed = true
            return {}
        }
        value := incremental_llvm_emit_expression(emitter, children[0])
        defer incremental_llvm_value_delete(&value)
        if emitter.failed || emitter.terminated ||
           !incremental_llvm_emit_active_managed_cleanups(emitter, 0) ||
           !incremental_llvm_emit_return_value(emitter, value) {
            emitter.failed = true
            return {}
        }
        return {kind = .Void}
    case .Break, .Continue:
        if expression.value_kind != .Void ||
           len(emitter.loop_condition_blocks) == 0 ||
           len(emitter.loop_exit_blocks) == 0 ||
           len(emitter.loop_cleanup_depths) == 0 {
            emitter.failed = true
            return {}
        }
        cleanup_depth := emitter.loop_cleanup_depths[
            len(emitter.loop_cleanup_depths)-1
        ]
        if !incremental_llvm_emit_active_managed_cleanups(
            emitter,
            cleanup_depth,
        ) {
            emitter.failed = true
            return {}
        }
        target := emitter.loop_exit_blocks[
            len(emitter.loop_exit_blocks)-1
        ] if expression.kind == .Break else
            emitter.loop_condition_blocks[
                len(emitter.loop_condition_blocks)-1
            ]
        fmt.sbprintf(emitter.output, "  br label %%%s\n", target)
        emitter.terminated = true
        return {kind = .Void}
    case .Bool_Literal:
        return {
            text = strings.clone("true" if expression.bool_value else "false"),
            kind = .Bool,
        }
    case .Int_Literal:
        return {
            text = fmt.aprintf("%d", expression.int_value),
            kind = .Int,
        }
    case .F64_Literal:
        bits := transmute(u64)expression.float_value
        return {
            text = fmt.aprintf("0x%016X", bits),
            kind = .F64,
        }
    case .String_Literal:
        return incremental_llvm_emit_string_literal(
            emitter,
            expression,
            expression_index,
        )
    case .Local:
        if expression.operand < 0 ||
           expression.operand >= len(emitter.locals) ||
           emitter.locals[expression.operand].pointer == "" ||
           emitter.locals[expression.operand].kind !=
               expression.value_kind {
            emitter.failed = true
            return {}
        }
        result := incremental_llvm_fresh_value(emitter)
        fmt.sbprintf(
            emitter.output,
            "  %s = load %s, ptr %s\n",
            result,
            incremental_llvm_type(expression.value_kind),
            emitter.locals[expression.operand].pointer,
        )
        return {text = result, kind = expression.value_kind}
    case .Let:
        bindings_end := expression.bindings_start+expression.bindings_count
        if expression.bindings_start < 0 || expression.bindings_count < 0 ||
           bindings_end > len(emitter.procedure.bindings) {
            emitter.failed = true
            return {}
        }
        cleanup_depth := len(emitter.active_managed_cleanups)
        for binding in emitter.procedure.bindings[expression.bindings_start:bindings_end] {
            if binding.slot < 0 || binding.slot >= len(emitter.locals) {
                emitter.failed = true
                return {}
            }
            value := incremental_llvm_emit_expression(
                emitter,
                binding.value_expr,
            )
            if emitter.failed || value.kind != binding.value_kind {
                incremental_llvm_value_delete(&value)
                emitter.failed = true
                return {}
            }
            if !incremental_llvm_store_local(
                emitter,
                binding.slot,
                value,
            ) {
                incremental_llvm_value_delete(&value)
                emitter.failed = true
                return {}
            }
            incremental_llvm_value_delete(&value)
            if binding.managed_cleanup {
                value_expression := &emitter.procedure.expressions[
                    binding.value_expr
                ]
                if value_expression.kind == .Native_Call &&
                   (binding.value_kind == .String ||
                    binding.value_kind == .Data) {
                    append(
                        &emitter.active_managed_cleanups,
                        Incremental_LLVM_Managed_Cleanup{
                            slot_index = binding.value_expr,
                            force_owner = strings.has_suffix(
                                value_expression.scalar_signature,
                                ")->string:owned",
                            ) || strings.has_suffix(
                                value_expression.scalar_signature,
                                ")->Data:owned",
                            ),
                        },
                    )
                }
            }
        }
        result := incremental_llvm_emit_expression(emitter, expression.body)
        if !emitter.failed && !emitter.terminated &&
           !incremental_llvm_emit_active_managed_cleanups(
                emitter,
                cleanup_depth,
           ) {
            incremental_llvm_value_delete(&result)
            emitter.failed = true
            resize(&emitter.active_managed_cleanups, cleanup_depth)
            return {}
        }
        resize(&emitter.active_managed_cleanups, cleanup_depth)
        return result
    case .Program_Call:
        return incremental_llvm_emit_call(emitter, expression)
    case .Native_Call:
        return incremental_llvm_emit_native_call(
            emitter,
            expression,
            expression_index,
        )
    case .If:
        return incremental_llvm_emit_if(emitter, expression)
    case .And, .Or:
        return incremental_llvm_emit_short_circuit(emitter, expression)
    case .Not:
        children, children_ok := incremental_llvm_children(
            emitter.procedure,
            expression,
        )
        if !children_ok || len(children) != 1 {
            emitter.failed = true
            return {}
        }
        value := incremental_llvm_emit_expression(emitter, children[0])
        defer incremental_llvm_value_delete(&value)
        if emitter.failed || value.kind != .Bool {
            emitter.failed = true
            return {}
        }
        result := incremental_llvm_fresh_value(emitter)
        fmt.sbprintf(
            emitter.output,
            "  %s = xor i1 %s, true\n",
            result,
            value.text,
        )
        return {text = result, kind = .Bool}
    case .Add, .Subtract, .Multiply, .Divide, .Modulo:
        return incremental_llvm_emit_numeric(emitter, expression)
    case .Equal, .Not_Equal, .Less, .Less_Equal, .Greater, .Greater_Equal:
        return incremental_llvm_emit_compare(emitter, expression)
    case .Invalid, .Recent_Result:
        emitter.failed = true
        return {}
    }
    emitter.failed = true
    return {}
}

incremental_llvm_render_procedure :: proc(
    output: ^strings.Builder,
    program: ^repl_program.Program,
    procedure_index: int,
    function_names: []string,
    native_targets: ^Incremental_LLVM_Native_Targets,
    worker_address,
    invoke_address,
    status_address: uintptr,
    managed_begin_address,
    managed_end_address,
    managed_store_address,
    managed_release_address: uintptr,
    guard_call_status: bool,
) -> bool {
    if output == nil || program == nil || procedure_index < 0 ||
       procedure_index >= len(program.procedures) ||
       procedure_index >= len(function_names) || native_targets == nil ||
       len(native_targets.slots) !=
           len(program.procedures[procedure_index].expressions) {
        return false
    }
    procedure := &program.procedures[procedure_index]
    result_type := incremental_llvm_internal_return_type(
        procedure.result_kind,
    )
    if result_type == "" ||
       procedure.local_count < len(procedure.parameter_kinds) ||
       len(procedure.local_kinds) != procedure.local_count {
        return false
    }
    fmt.sbprintf(
        output,
        "define %s @%s(",
        result_type,
        function_names[procedure_index],
    )
    for kind, index in procedure.parameter_kinds {
        if index > 0 {
            strings.write_string(output, ", ")
        }
        ty := incremental_llvm_type(kind)
        if ty == "" {
            return false
        }
        if kind == .Bool {
            fmt.sbprintf(output, "i1 zeroext %%arg%d", index)
        } else {
            fmt.sbprintf(output, "%s %%arg%d", ty, index)
        }
    }
    if len(procedure.parameter_kinds) > 0 {
        strings.write_string(output, ", ")
    }
    strings.write_string(output, "ptr %ctx) {\nentry:\n")
    emitter := Incremental_LLVM_Emitter{
        output = output,
        program = program,
        procedure = procedure,
        procedure_index = procedure_index,
        function_names = function_names,
        native_slots = native_targets.slots[:],
        worker_address = worker_address,
        invoke_address = invoke_address,
        status_address = status_address,
        managed_begin_address = managed_begin_address,
        managed_end_address = managed_end_address,
        managed_store_address = managed_store_address,
        managed_release_address = managed_release_address,
        guard_call_status = guard_call_status,
        current_block = strings.clone("entry"),
    }
    defer incremental_llvm_emitter_delete(&emitter)
    resize(&emitter.locals, procedure.local_count)
    resize(&emitter.managed_pointers, len(procedure.expressions))
    for kind, index in procedure.local_kinds {
        pointer := fmt.aprintf("%%local.%d", index)
        emitter.locals[index] = {
            pointer = pointer,
            kind = kind,
        }
        fmt.sbprintf(
            output,
            "  %s = alloca %s\n",
            pointer,
            incremental_llvm_type(kind),
        )
    }
    has_native_call := false
    for slot in native_targets.slots {
        if slot >= 0 {
            has_native_call = true
            break
        }
    }
    if has_native_call {
        emitter.native_args_pointer = strings.clone("%native.args")
        emitter.native_result_pointer = strings.clone("%native.result")
        fmt.sbprintf(
            output,
            "  %s = alloca [%d x i8], align 8\n" +
            "  %s = alloca [%d x i8], align 8\n",
            emitter.native_args_pointer,
            4*size_of(Scalar_Value),
            emitter.native_result_pointer,
            size_of(Scalar_Value),
        )
    }
    has_managed_frame := false
    for expression, expression_index in procedure.expressions {
        if expression.value_kind != .String &&
           expression.value_kind != .Data {
            continue
        }
        if expression.kind == .String_Literal ||
           expression.kind == .Native_Call {
            pointer := fmt.aprintf("%%managed.%d", expression_index)
            emitter.managed_pointers[expression_index] = pointer
            fmt.sbprintf(
                output,
                "  %s = alloca [%d x i8], align 8\n",
                pointer,
                size_of(Scalar_Value),
            )
        }
        if expression.kind == .Native_Call {
            has_managed_frame = true
        }
    }
    if has_managed_frame {
        if managed_begin_address == 0 || managed_end_address == 0 ||
           managed_store_address == 0 || managed_release_address == 0 {
            return false
        }
        emitter.managed_frame_pointer = strings.clone("%managed.frame")
        frame_ok := incremental_llvm_fresh_value(&emitter)
        ready_block := incremental_llvm_fresh_block(&emitter, "managed.ready")
        failure_block := incremental_llvm_fresh_block(&emitter, "managed.exit")
        fmt.sbprintf(
            output,
            "  %s = call ptr inttoptr (%s %d to ptr)(" +
            "ptr inttoptr (%s %d to ptr), i64 %d)\n" +
            "  %s = icmp ne ptr %s, null\n" +
            "  br i1 %s, label %%%s, label %%%s\n",
            emitter.managed_frame_pointer,
            incremental_llvm_pointer_int_type(),
            managed_begin_address,
            incremental_llvm_pointer_int_type(),
            worker_address,
            len(procedure.expressions),
            frame_ok,
            emitter.managed_frame_pointer,
            frame_ok,
            ready_block,
            failure_block,
        )
        incremental_llvm_start_block(&emitter, failure_block)
        if !incremental_llvm_emit_default_return(&emitter) {
            delete(frame_ok)
            delete(ready_block)
            delete(failure_block)
            return false
        }
        incremental_llvm_start_block(&emitter, ready_block)
        delete(frame_ok)
        delete(ready_block)
        delete(failure_block)
    }
    for kind, index in procedure.parameter_kinds {
        argument := Incremental_LLVM_Value{
            text = fmt.aprintf("%%arg%d", index),
            kind = kind,
        }
        stored := incremental_llvm_store_local(&emitter, index, argument)
        incremental_llvm_value_delete(&argument)
        if !stored {
            return false
        }
    }
    result := incremental_llvm_emit_expression(
        &emitter,
        procedure.result_expr,
    )
    defer incremental_llvm_value_delete(&result)
    if emitter.failed {
        return false
    }
    if !emitter.terminated &&
       !incremental_llvm_emit_return_value(&emitter, result) {
        return false
    }
    strings.write_string(output, "}\n\n")
    return true
}

incremental_llvm_scalar_kind :: proc(kind: repl_program.Value_Kind) -> u32 {
    switch kind {
    case .Bool: return u32(Scalar_Value_Kind.Bool)
    case .Int:  return u32(Scalar_Value_Kind.Int)
    case .F64:  return u32(Scalar_Value_Kind.F64)
    case .String: return u32(Scalar_Value_Kind.String)
    case .Data:   return u32(Scalar_Value_Kind.Data)
    case .Invalid, .Void:
    }
    return 0
}

incremental_llvm_render_wrapper :: proc(
    output: ^strings.Builder,
    procedure: ^repl_program.Procedure,
    function_name,
    wrapper_name: string,
    worker_address,
    status_address: uintptr,
    guard_call_status: bool,
) -> bool {
    if output == nil || procedure == nil || function_name == "" ||
       wrapper_name == "" || worker_address == 0 || status_address == 0 {
        return false
    }
    probe := Scalar_Value{}
    kind_offset := int(uintptr(&probe.kind)-uintptr(&probe))
    int_offset := int(uintptr(&probe.int_value)-uintptr(&probe))
    float_offset := int(uintptr(&probe.float_value)-uintptr(&probe))
    stride := size_of(Scalar_Value)
    fmt.sbprintf(
        output,
        "define i8 @%s(ptr %%args, i64 %%arg_count, ptr %%result) {{\nentry:\n",
        wrapper_name,
    )
    count_ok := 0
    fmt.sbprintf(
        output,
        "  %%w%d = icmp eq i64 %%arg_count, %d\n",
        count_ok,
        len(procedure.parameter_kinds),
    )
    next_value := count_ok+1
    check_block := "wrapper.check.0"
    if len(procedure.parameter_kinds) == 0 {
        check_block = "wrapper.invoke"
    }
    fmt.sbprintf(
        output,
        "  br i1 %%w0, label %%%s, label %%wrapper.invalid\n",
        check_block,
    )
    loaded_values: [dynamic]string
    defer {
        for value in loaded_values {
            delete(value)
        }
        delete(loaded_values)
    }
    for kind, index in procedure.parameter_kinds {
        fmt.sbprintf(output, "wrapper.check.%d:\n", index)
        kind_pointer := fmt.aprintf("%%w%d", next_value)
        next_value += 1
        kind_value := fmt.aprintf("%%w%d", next_value)
        next_value += 1
        kind_ok := fmt.aprintf("%%w%d", next_value)
        next_value += 1
        fmt.sbprintf(
            output,
            "  %s = getelementptr i8, ptr %%args, i64 %d\n" +
            "  %s = load i32, ptr %s, align 4\n" +
            "  %s = icmp eq i32 %s, %d\n",
            kind_pointer,
            index*stride+kind_offset,
            kind_value,
            kind_pointer,
            kind_ok,
            kind_value,
            incremental_llvm_scalar_kind(kind),
        )
        next_block := "wrapper.invoke" if
            index+1 == len(procedure.parameter_kinds) else
            fmt.tprintf("wrapper.check.%d", index+1)
        fmt.sbprintf(
            output,
            "  br i1 %s, label %%%s, label %%wrapper.invalid\n",
            kind_ok,
            next_block,
        )
        delete(kind_pointer)
        delete(kind_value)
        delete(kind_ok)
    }
    strings.write_string(output, "wrapper.invalid:\n  ret i8 0\nwrapper.invoke:\n")
    for kind, index in procedure.parameter_kinds {
        offset := index*stride
        if kind == .Bool || kind == .Int {
            pointer := fmt.aprintf("%%w%d", next_value)
            next_value += 1
            raw_value := fmt.aprintf("%%w%d", next_value)
            next_value += 1
            fmt.sbprintf(
                output,
                "  %s = getelementptr i8, ptr %%args, i64 %d\n" +
                "  %s = load i64, ptr %s, align 8\n",
                pointer,
                offset+int_offset,
                raw_value,
                pointer,
            )
            delete(pointer)
            if kind == .Bool {
                value := fmt.aprintf("%%w%d", next_value)
                next_value += 1
                fmt.sbprintf(
                    output,
                    "  %s = trunc i64 %s to i1\n",
                    value,
                    raw_value,
                )
                delete(raw_value)
                append(&loaded_values, value)
            } else if size_of(int) == 8 {
                append(&loaded_values, raw_value)
            } else {
                value := fmt.aprintf("%%w%d", next_value)
                next_value += 1
                fmt.sbprintf(
                    output,
                    "  %s = trunc i64 %s to i32\n",
                    value,
                    raw_value,
                )
                delete(raw_value)
                append(&loaded_values, value)
            }
        } else if kind == .F64 {
            pointer := fmt.aprintf("%%w%d", next_value)
            next_value += 1
            value := fmt.aprintf("%%w%d", next_value)
            next_value += 1
            fmt.sbprintf(
                output,
                "  %s = getelementptr i8, ptr %%args, i64 %d\n" +
                "  %s = load double, ptr %s, align 8\n",
                pointer,
                offset+float_offset,
                value,
                pointer,
            )
            delete(pointer)
            append(&loaded_values, value)
        } else {
            return false
        }
    }
    call_result := fmt.aprintf("%%w%d", next_value)
    next_value += 1
    fmt.sbprintf(
        output,
        "  %s = call %s @%s(",
        call_result,
        incremental_llvm_internal_return_type(procedure.result_kind),
        function_name,
    )
    for value, index in loaded_values {
        if index > 0 {
            strings.write_string(output, ", ")
        }
        fmt.sbprintf(
            output,
            "%s %s",
            incremental_llvm_type(procedure.parameter_kinds[index]),
            value,
        )
    }
    if len(loaded_values) > 0 {
        strings.write_string(output, ", ")
    }
    strings.write_string(output, "ptr null)\n")
    if guard_call_status {
        status := fmt.aprintf("%%w%d", next_value)
        next_value += 1
        status_ok := fmt.aprintf("%%w%d", next_value)
        next_value += 1
        status_aborted := fmt.aprintf("%%w%d", next_value)
        next_value += 1
        fmt.sbprintf(
            output,
            "  %s = call i8 inttoptr (%s %d to ptr)(" +
            "ptr inttoptr (%s %d to ptr))\n" +
            "  %s = icmp eq i8 %s, %d\n" +
            "  br i1 %s, label %%wrapper.store, label %%wrapper.status\n" +
            "wrapper.status:\n" +
            "  %s = icmp eq i8 %s, %d\n" +
            "  br i1 %s, label %%wrapper.aborted, label %%wrapper.invalid\n" +
            "wrapper.aborted:\n  ret i8 1\nwrapper.store:\n",
            status,
            incremental_llvm_pointer_int_type(),
            status_address,
            incremental_llvm_pointer_int_type(),
            worker_address,
            status_ok,
            status,
            int(Incremental_Call_Status.Success),
            status_ok,
            status_aborted,
            status,
            int(Incremental_Call_Status.Aborted),
            status_aborted,
        )
        delete(status)
        delete(status_ok)
        delete(status_aborted)
    }
    kind_pointer := fmt.aprintf("%%w%d", next_value)
    next_value += 1
    fmt.sbprintf(
        output,
        "  %s = getelementptr i8, ptr %%result, i64 %d\n" +
        "  store i32 %d, ptr %s, align 4\n",
        kind_pointer,
        kind_offset,
        incremental_llvm_scalar_kind(procedure.result_kind),
        kind_pointer,
    )
    delete(kind_pointer)
    if procedure.result_kind == .Bool || procedure.result_kind == .Int {
        stored_value := call_result
        if procedure.result_kind == .Bool {
            widened := fmt.aprintf("%%w%d", next_value)
            next_value += 1
            fmt.sbprintf(
                output,
                "  %s = zext i8 %s to i64\n",
                widened,
                call_result,
            )
            stored_value = widened
        } else if size_of(int) != 8 {
            widened := fmt.aprintf("%%w%d", next_value)
            next_value += 1
            fmt.sbprintf(
                output,
                "  %s = sext i32 %s to i64\n",
                widened,
                call_result,
            )
            stored_value = widened
        }
        value_pointer := fmt.aprintf("%%w%d", next_value)
        fmt.sbprintf(
            output,
            "  %s = getelementptr i8, ptr %%result, i64 %d\n" +
            "  store i64 %s, ptr %s, align 8\n  ret i8 1\n}\n\n",
            value_pointer,
            int_offset,
            stored_value,
            value_pointer,
        )
        delete(value_pointer)
        if stored_value != call_result {
            delete(stored_value)
        }
    } else if procedure.result_kind == .F64 {
        value_pointer := fmt.aprintf("%%w%d", next_value)
        fmt.sbprintf(
            output,
            "  %s = getelementptr i8, ptr %%result, i64 %d\n" +
            "  store double %s, ptr %s, align 8\n  ret i8 1\n}\n\n",
            value_pointer,
            float_offset,
            call_result,
            value_pointer,
        )
        delete(value_pointer)
    } else {
        delete(call_result)
        return false
    }
    delete(call_result)
    return true
}

incremental_llvm_program_supported :: proc(
    program: ^repl_program.Program,
) -> bool {
    if program == nil || len(program.procedures) == 0 ||
       len(program.procedures) > repl_program.MAX_PROCEDURES {
        return false
    }
    for &procedure in program.procedures {
        if procedure.result_kind != .Bool &&
           procedure.result_kind != .Int &&
           procedure.result_kind != .F64 {
            return false
        }
        for kind in procedure.parameter_kinds {
            if kind != .Bool && kind != .Int && kind != .F64 {
                return false
            }
        }
        for kind in procedure.local_kinds {
            if kind == .Invalid || kind == .Void {
                return false
            }
        }
        for expression in procedure.expressions {
            if expression.kind == .Let &&
               (expression.value_kind == .String ||
                expression.value_kind == .Data) {
                return false
            }
            if expression.kind == .Set_Local && expression.operand >= 0 &&
               expression.operand < len(procedure.local_kinds) &&
               (procedure.local_kinds[expression.operand] == .String ||
                procedure.local_kinds[expression.operand] == .Data) {
                return false
            }
            switch expression.kind {
            case .Sequence, .Discard, .Set_Local, .While, .Return,
                 .Break, .Continue, .Bool_Literal, .Int_Literal,
                 .F64_Literal, .String_Literal, .Local, .Let,
                 .Program_Call, .Native_Call, .If, .Not,
                 .And, .Or, .Add, .Subtract, .Multiply, .Divide,
                 .Modulo, .Equal, .Not_Equal, .Less, .Less_Equal,
                 .Greater, .Greater_Equal:
            case .Invalid, .Recent_Result:
                return false
            }
        }
        for binding in procedure.bindings {
            if !binding.managed_cleanup || binding.value_expr < 0 ||
               binding.value_expr >= len(procedure.expressions) {
                if binding.managed_cleanup {
                    return false
                }
                continue
            }
            value_expression := &procedure.expressions[
                binding.value_expr
            ]
            cleanup_supported := value_expression.kind == .Native_Call &&
                value_expression.value_kind == binding.value_kind
            if binding.value_kind == .String {
                cleanup_supported = cleanup_supported &&
                    strings.has_suffix(
                        value_expression.scalar_signature,
                        ")->string:owned",
                    )
            } else if binding.value_kind == .Data {
                cleanup_supported = cleanup_supported &&
                    (strings.has_suffix(
                        value_expression.scalar_signature,
                        ")->Data:owned",
                    ) || strings.has_suffix(
                        value_expression.scalar_signature,
                        ")->Data:borrowed",
                    ))
            } else {
                cleanup_supported = false
            }
            if !cleanup_supported {
                return false
            }
        }
        for expression, expression_index in procedure.expressions {
            if expression.kind != .Native_Call ||
               (expression.value_kind != .String &&
                expression.value_kind != .Data) ||
               !(strings.has_suffix(
                    expression.scalar_signature,
                    ")->string:owned",
                ) || strings.has_suffix(
                    expression.scalar_signature,
                    ")->Data:owned",
                )) {
                continue
            }
            cleanup_bound := false
            for binding in procedure.bindings {
                if binding.value_expr == expression_index &&
                   binding.managed_cleanup {
                    cleanup_bound = true
                    break
                }
            }
            if !cleanup_bound {
                return false
            }
        }
    }
    return true
}

incremental_llvm_render_string_literals :: proc(
    output: ^strings.Builder,
    program: ^repl_program.Program,
    function_names: []string,
) -> bool {
    if output == nil || program == nil ||
       len(function_names) != len(program.procedures) {
        return false
    }
    for procedure, procedure_index in program.procedures {
        for expression, expression_index in procedure.expressions {
            if expression.kind != .String_Literal {
                continue
            }
            name := incremental_llvm_string_literal_name(
                function_names[procedure_index],
                expression_index,
            )
            byte_count := len(expression.string_value)
            storage_count := byte_count if byte_count > 0 else 1
            fmt.sbprintf(
                output,
                "@%s = private unnamed_addr constant [%d x i8] c\"",
                name,
                storage_count,
            )
            if byte_count == 0 {
                strings.write_string(output, "\\00")
            } else {
                for byte in transmute([]u8)expression.string_value {
                    fmt.sbprintf(output, "\\%02X", byte)
                }
            }
            strings.write_string(output, "\"\n")
            delete(name)
        }
    }
    strings.write_byte(output, '\n')
    return true
}

incremental_llvm_render_module :: proc(
    program: ^repl_program.Program,
    native_targets: []Incremental_LLVM_Native_Targets,
    triple,
    data_layout: string,
    generation: int,
    worker_address,
    invoke_address,
    status_address: uintptr,
    managed_begin_address,
    managed_end_address,
    managed_store_address,
    managed_release_address: uintptr,
) -> (source: string, function_names, wrapper_names: [dynamic]string, ok: bool) {
    if !incremental_llvm_program_supported(program) || triple == "" ||
       data_layout == "" || len(native_targets) != len(program.procedures) ||
       worker_address == 0 || invoke_address == 0 || status_address == 0 ||
       managed_begin_address == 0 || managed_end_address == 0 ||
       managed_store_address == 0 || managed_release_address == 0 {
        return
    }
    output := strings.builder_make()
    defer strings.builder_destroy(&output)
    fmt.sbprintf(
        &output,
        "; Kvist incremental native program\n" +
        "target datalayout = %q\n" +
        "target triple = %q\n\n",
        data_layout,
        triple,
    )
    for _, index in program.procedures {
        append(
            &function_names,
            fmt.aprintf("kvist_jit_proc_%d_%d", generation, index),
        )
        append(
            &wrapper_names,
            fmt.aprintf("kvist_jit_scalar_%d_%d", generation, index),
        )
    }
    if !incremental_llvm_render_string_literals(
        &output,
        program,
        function_names[:],
    ) {
        return
    }
    guard_call_status := false
    for targets in native_targets {
        for slot in targets.slots {
            if slot >= 0 {
                guard_call_status = true
                break
            }
        }
        if guard_call_status {
            break
        }
    }
    for _, index in program.procedures {
        if !incremental_llvm_render_procedure(
            &output,
            program,
            index,
            function_names[:],
            &native_targets[index],
            worker_address,
            invoke_address,
            status_address,
            managed_begin_address,
            managed_end_address,
            managed_store_address,
            managed_release_address,
            guard_call_status,
        ) || !incremental_llvm_render_wrapper(
            &output,
            &program.procedures[index],
            function_names[index],
            wrapper_names[index],
            worker_address,
            status_address,
            guard_call_status,
        ) {
            for name in function_names {
                delete(name)
            }
            delete(function_names)
            function_names = nil
            for name in wrapper_names {
                delete(name)
            }
            delete(wrapper_names)
            wrapper_names = nil
            return "", function_names, wrapper_names, false
        }
    }
    return strings.clone(strings.to_string(output)), function_names, wrapper_names, true
}

incremental_llvm_names_delete :: proc(names: ^[dynamic]string) {
    if names == nil {
        return
    }
    for name in names^ {
        delete(name)
    }
    delete(names^)
    names^ = nil
}

incremental_llvm_compile_program :: proc(
    backend: ^Incremental_LLVM_Backend,
    program: ^repl_program.Program,
    native_targets: []Incremental_LLVM_Native_Targets,
    worker: ^Worker,
) -> (engine: rawptr, proc_addresses, wrapper_addresses: [dynamic]u64, message: string, ok: bool) {
    if backend == nil || program == nil || worker == nil ||
       !incremental_llvm_backend_initialize(backend) {
        reason := "incremental native backend is unavailable"
        if backend != nil && backend.reason != "" {
            reason = backend.reason
        }
        return nil, nil, nil, strings.clone(reason), false
    }
    api := &backend.api
    llvm_error := api.create_jit(&engine, nil)
    if llvm_error != nil || engine == nil {
        return nil,
               nil,
               nil,
               incremental_llvm_error(
                   api,
                   llvm_error,
                   "failed to create LLVM LLJIT",
               ),
               false
    }
    keep_engine := false
    defer if !keep_engine && engine != nil {
        dispose_error := api.dispose_jit(engine)
        if dispose_error != nil {
            ignored := api.error_message(dispose_error)
            if ignored != nil {
                api.error_message_dispose(ignored)
            }
        }
    }
    triple_ptr := api.get_triple(engine)
    layout_ptr := api.get_data_layout(engine)
    if triple_ptr == nil || layout_ptr == nil {
        return nil,
               nil,
               nil,
               strings.clone("LLVM LLJIT did not report a host target"),
               false
    }
    backend.generation += 1
    function_names: [dynamic]string
    wrapper_names: [dynamic]string
    source: string
    rendered: bool
    source, function_names, wrapper_names, rendered =
        incremental_llvm_render_module(
            program,
            native_targets,
            string(triple_ptr),
            string(layout_ptr),
            backend.generation,
            uintptr(rawptr(worker)),
            uintptr(transmute(rawptr)worker_incremental_invoke_scalar),
            uintptr(transmute(rawptr)worker_incremental_execution_status),
            uintptr(transmute(rawptr)worker_incremental_managed_begin),
            uintptr(transmute(rawptr)worker_incremental_managed_end),
            uintptr(transmute(rawptr)worker_incremental_managed_store),
            uintptr(transmute(rawptr)worker_incremental_managed_release),
        )
    defer delete(source)
    defer incremental_llvm_names_delete(&function_names)
    defer incremental_llvm_names_delete(&wrapper_names)
    if !rendered {
        return nil,
               nil,
               nil,
               strings.clone("incremental program cannot be lowered to LLVM"),
               false
    }
    source_c := strings.clone_to_cstring(source, context.temp_allocator)
    name_c := strings.clone_to_cstring(
        "kvist-incremental",
        context.temp_allocator,
    )
    memory_buffer := api.memory_buffer_create(
        source_c,
        uintptr(len(source)),
        name_c,
    )
    if memory_buffer == nil {
        return nil,
               nil,
               nil,
               strings.clone("failed to allocate LLVM IR buffer"),
               false
    }
    context_ref := api.context_create()
    if context_ref == nil {
        api.memory_buffer_dispose(memory_buffer)
        return nil,
               nil,
               nil,
               strings.clone("failed to allocate LLVM context"),
               false
    }
    module: rawptr
    parse_message: cstring
    parse_failed := api.parse_ir(
        context_ref,
        memory_buffer,
        &module,
        &parse_message,
    ) != 0
    api.memory_buffer_dispose(memory_buffer)
    if parse_failed || module == nil {
        api.context_dispose(context_ref)
        result := strings.clone("failed to parse generated LLVM IR")
        if parse_message != nil {
            delete(result)
            result = strings.clone(string(parse_message))
            api.message_dispose(parse_message)
        }
        return nil, nil, nil, result, false
    }
    if parse_message != nil {
        api.message_dispose(parse_message)
    }
    thread_context := api.thread_context_create(context_ref)
    if thread_context == nil {
        // The ownership transfer occurs only on success.
        api.context_dispose(context_ref)
        return nil,
               nil,
               nil,
               strings.clone("failed to create LLVM thread-safe context"),
               false
    }
    thread_module := api.thread_module_create(module, thread_context)
    api.thread_context_dispose(thread_context)
    if thread_module == nil {
        return nil,
               nil,
               nil,
               strings.clone("failed to create LLVM thread-safe module"),
               false
    }
    dylib := api.get_main_dylib(engine)
    if dylib == nil {
        api.thread_module_dispose(thread_module)
        return nil,
               nil,
               nil,
               strings.clone("LLVM LLJIT has no main symbol namespace"),
               false
    }
    add_error := api.add_module(engine, dylib, thread_module)
    if add_error != nil {
        return nil,
               nil,
               nil,
               incremental_llvm_error(
                   api,
                   add_error,
                   "failed to add LLVM IR module",
               ),
               false
    }
    for name in function_names {
        address: u64
        c_name := strings.clone_to_cstring(name, context.temp_allocator)
        lookup_error := api.lookup(engine, &address, c_name)
        if lookup_error != nil || address == 0 {
            return nil,
                   nil,
                   nil,
                   incremental_llvm_error(
                       api,
                       lookup_error,
                       "failed to resolve incremental procedure",
                   ),
                   false
        }
        append(&proc_addresses, address)
    }
    for name in wrapper_names {
        address: u64
        c_name := strings.clone_to_cstring(name, context.temp_allocator)
        lookup_error := api.lookup(engine, &address, c_name)
        if lookup_error != nil || address == 0 {
            delete(proc_addresses)
            proc_addresses = nil
            return nil,
                   nil,
                   nil,
                   incremental_llvm_error(
                       api,
                       lookup_error,
                       "failed to resolve incremental scalar adapter",
                   ),
                   false
        }
        append(&wrapper_addresses, address)
    }
    keep_engine = true
    return engine, proc_addresses, wrapper_addresses, "", true
}

worker_execute_incremental_program :: proc(
    worker: ^Worker,
    encoded: string,
) -> (message: string, ok: bool) {
    if worker == nil {
        return strings.clone("REPL worker is unavailable"), false
    }
    if worker.allocator.procedure == nil {
        worker.allocator = context.allocator
    }
    context = runtime.default_context()
    context.allocator = worker.allocator
    program, decoded := repl_program.program_decode(encoded)
    if !decoded {
        return strings.clone("invalid incremental native program"), false
    }
    defer repl_program.program_delete(&program)
    if !incremental_llvm_program_supported(&program) {
        return strings.clone("incremental native program is unsupported"), false
    }
    native_targets, targets_message, targets_ok :=
        incremental_llvm_resolve_native_targets(worker, &program)
    defer incremental_llvm_native_targets_delete(&native_targets)
    if !targets_ok {
        return targets_message, false
    }
    engine, proc_addresses, wrapper_addresses, compile_message, compiled :=
        incremental_llvm_compile_program(
            &worker.incremental_backend,
            &program,
            native_targets[:],
            worker,
        )
    defer delete(proc_addresses)
    defer delete(wrapper_addresses)
    if !compiled {
        return compile_message, false
    }
    append(&worker.incremental_backend.engines, engine)
    for &procedure, index in program.procedures {
        name_c := strings.clone_to_cstring(
            procedure.name,
            context.temp_allocator,
        )
        signature_c := strings.clone_to_cstring(
            procedure.signature,
            context.temp_allocator,
        )
        result_abi := fmt.tprintf(
            "value:%s",
            "bool" if procedure.result_kind == .Bool else
            "int" if procedure.result_kind == .Int else
            "f64",
        )
        result_abi_c := strings.clone_to_cstring(
            result_abi,
            context.temp_allocator,
        )
        worker_register_proc(
            rawptr(worker),
            name_c,
            signature_c,
            rawptr(uintptr(proc_addresses[index])),
        )
        worker_register_scalar_invoke(
            rawptr(worker),
            name_c,
            signature_c,
            result_abi_c,
            transmute(Scalar_Invoke)rawptr(
                uintptr(wrapper_addresses[index]),
            ),
        )
    }
    worker.last_run_aborted = false
    return "", true
}
