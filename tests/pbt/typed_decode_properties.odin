package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import pbt "pbt:pbt"

TYPED_DECODE_CAPACITY :: 4
TYPED_DECODE_SUMMARY_COUNT :: 14

Typed_Decode_Corruption :: enum {
	Valid,
	Root_Vector,
	Port_Missing,
	Port_String,
	Enabled_Int,
	Ratio_Int,
	Mode_Int,
	Mode_Invalid,
	Name_Keyword,
	Child_Int,
	Child_Id_Missing,
	Child_Id_Bool,
	Nums_Map,
	Nums_Item_String,
	Flags_Item_Int,
	Ratios_Item_Bool,
	Modes_Item_Invalid,
	Children_Item_Int,
	Children_Id_String,
}

TYPED_DECODE_CORRUPTION_NAMES := [?]string {
	"valid",
	"root-vector",
	"port-missing",
	"port-string",
	"enabled-int",
	"ratio-int",
	"mode-int",
	"mode-invalid",
	"name-keyword",
	"child-int",
	"child-id-missing",
	"child-id-bool",
	"nums-map",
	"nums-item-string",
	"flags-item-int",
	"ratios-item-bool",
	"modes-item-invalid",
	"children-item-int",
	"children-id-string",
}

Typed_Decode_Input :: struct {
	corruption:     Typed_Decode_Corruption,
	length:         int,
	index:          int,
	port:           int,
	enabled:        bool,
	ratio_whole:    int,
	mode:           int,
	child_id:       int,
	child_active:   bool,
	nums:           [TYPED_DECODE_CAPACITY]int,
	flags:          [TYPED_DECODE_CAPACITY]bool,
	ratios:         [TYPED_DECODE_CAPACITY]int,
	modes:          [TYPED_DECODE_CAPACITY]int,
	children_ids:   [TYPED_DECODE_CAPACITY]int,
	children_active: [TYPED_DECODE_CAPACITY]bool,
	raw_seed:       int,
}

Typed_Decode_Error_Model :: struct {
	ok:            bool,
	path:          string,
	expected_kind: int,
	actual_kind:   int,
	enum_value:    bool,
	expected_type: string,
	actual_value:  string,
}

typed_decode_and_validate_match_model :: proc(t: ^pbt.T) -> pbt.Result {
	input := generated_typed_decode_input(t)
	request := typed_decode_request(input)
	expected_error := typed_decode_error_model(input)
	expected_summary := typed_decode_summary(input)
	pbt.note(t, fmt.tprintf("request=%s", request))
	for name, corruption_index in TYPED_DECODE_CORRUPTION_NAMES {
		pbt.cover(t, int(input.corruption) == corruption_index, 3, name)
	}

	target_path := os.get_env("KVIST_PBT_TYPED_DECODE_TARGET", t.value_allocator)
	if target_path == "" {
		return pbt.error("KVIST_PBT_TYPED_DECODE_TARGET is not set")
	}
	command := [?]string{target_path}
	process := pbt.process_run_with_options(t, command[:], {
		stdin = request,
		timeout_ms = 1_000,
		max_output_bytes = 32_768,
	})
	if !process.success {
		if process.stderr != "" {
			return pbt.fail(process.stderr)
		}
		if process.error != "" {
			return pbt.fail(process.error)
		}
		return pbt.fail(fmt.tprintf("typed decode target exited with %d", process.exit_code))
	}

	parts := strings.split(process.stdout, "\t", t.value_allocator)
	if len(parts) != TYPED_DECODE_SUMMARY_COUNT + 10 {
		return pbt.fail(fmt.tprintf("typed decode target returned %d fields, expected %d", len(parts), TYPED_DECODE_SUMMARY_COUNT + 10))
	}
	decode_ok, decode_ok_valid := strconv.parse_int(parts[0], 10)
	validate_ok, validate_ok_valid := strconv.parse_int(parts[1], 10)
	agreement, agreement_valid := strconv.parse_int(parts[2], 10)
	if !decode_ok_valid || !validate_ok_valid || !agreement_valid ||
	   (decode_ok == 1) != expected_error.ok || (validate_ok == 1) != expected_error.ok || agreement != 1 {
		return pbt.fail(fmt.tprintf("decode/validate status mismatch for %s", TYPED_DECODE_CORRUPTION_NAMES[input.corruption]))
	}
	if parts[3] != expected_error.path || parts[7] != expected_error.expected_type || parts[8] != expected_error.actual_value {
		return pbt.fail(fmt.tprintf(
			"decode error text mismatch: expected-path=%s actual-path=%s expected-type=%s actual-type=%s expected-value=%s actual-value=%s",
			expected_error.path,
			parts[3],
			expected_error.expected_type,
			parts[7],
			expected_error.actual_value,
			parts[8],
		))
	}
	error_ints := [?]int{expected_error.expected_kind, expected_error.actual_kind, expected_error.enum_value ? 1 : 0}
	for expected_value, index in error_ints {
		actual, ok := strconv.parse_int(parts[index + 4], 10)
		if !ok || actual != expected_value {
			return pbt.fail(fmt.tprintf("decode error field %d mismatch: expected=%d actual=%q", index, expected_value, parts[index + 4]))
		}
	}
	for expected_value, index in expected_summary {
		actual, ok := strconv.parse_int(parts[index + 9], 10)
		if !ok || actual != expected_value {
			return pbt.fail(fmt.tprintf("decoded summary %d mismatch: expected=%d actual=%q", index, expected_value, parts[index + 9]))
		}
	}
	if parts[len(parts) - 1] != "done" {
		return pbt.fail(fmt.tprintf("unexpected typed decode trailer: %q", process.stdout))
	}
	return pbt.pass()
}

generated_typed_decode_input :: proc(t: ^pbt.T) -> Typed_Decode_Input {
	result := Typed_Decode_Input {
		corruption = Typed_Decode_Corruption(pbt.draw(t, pbt.int_range(0, len(TYPED_DECODE_CORRUPTION_NAMES) - 1))),
		length = pbt.draw(t, pbt.int_range(1, TYPED_DECODE_CAPACITY)),
		port = pbt.draw(t, pbt.int_range(1, 65_535)),
		enabled = pbt.draw(t, pbt.boolean()),
		ratio_whole = pbt.draw(t, pbt.int_range(-20, 20)),
		mode = pbt.draw(t, pbt.int_range(0, 2)),
		child_id = pbt.draw(t, pbt.int_range(-100, 100)),
		child_active = pbt.draw(t, pbt.boolean()),
		raw_seed = pbt.draw(t, pbt.int_range(-100, 100)),
	}
	result.index = pbt.draw(t, pbt.int_range(0, result.length - 1))
	for index in 0 ..< result.length {
		result.nums[index] = pbt.draw(t, pbt.int_range(-100, 100))
		result.flags[index] = pbt.draw(t, pbt.boolean())
		result.ratios[index] = pbt.draw(t, pbt.int_range(-20, 20))
		result.modes[index] = pbt.draw(t, pbt.int_range(0, 2))
		result.children_ids[index] = pbt.draw(t, pbt.int_range(-100, 100))
		result.children_active[index] = pbt.draw(t, pbt.boolean())
	}
	return result
}

typed_decode_error_model :: proc(input: Typed_Decode_Input) -> Typed_Decode_Error_Model {
	result := Typed_Decode_Error_Model{ok = false, expected_type = "-", actual_value = "-"}
	root := "[:config]"
	switch input.corruption {
	case .Valid:
		return {ok = true, path = "-", expected_kind = -1, actual_kind = -1, expected_type = "-", actual_value = "-"}
	case .Root_Vector:
		result.path, result.expected_kind, result.actual_kind = root, int(Data_Access_Kind.Map), int(Data_Access_Kind.Vector)
	case .Port_Missing:
		result.path, result.expected_kind, result.actual_kind = "[:config :port]", int(Data_Access_Kind.Int), int(Data_Access_Kind.Nil)
	case .Port_String:
		result.path, result.expected_kind, result.actual_kind = "[:config :port]", int(Data_Access_Kind.Int), int(Data_Access_Kind.String)
	case .Enabled_Int:
		result.path, result.expected_kind, result.actual_kind = "[:config :enabled]", int(Data_Access_Kind.Bool), int(Data_Access_Kind.Int)
	case .Ratio_Int:
		result.path, result.expected_kind, result.actual_kind = "[:config :ratio]", int(Data_Access_Kind.Float), int(Data_Access_Kind.Int)
	case .Mode_Int:
		result.path, result.expected_kind, result.actual_kind = "[:config :mode]", int(Data_Access_Kind.Keyword), int(Data_Access_Kind.Int)
	case .Mode_Invalid:
		result.path, result.expected_kind, result.actual_kind = "[:config :mode]", int(Data_Access_Kind.Keyword), int(Data_Access_Kind.Keyword)
		result.enum_value, result.expected_type, result.actual_value = true, "Mode", ":unknown"
	case .Name_Keyword:
		result.path, result.expected_kind, result.actual_kind = "[:config :name]", int(Data_Access_Kind.String), int(Data_Access_Kind.Keyword)
	case .Child_Int:
		result.path, result.expected_kind, result.actual_kind = "[:config :child]", int(Data_Access_Kind.Map), int(Data_Access_Kind.Int)
	case .Child_Id_Missing:
		result.path, result.expected_kind, result.actual_kind = "[:config :child :host-id]", int(Data_Access_Kind.Int), int(Data_Access_Kind.Nil)
	case .Child_Id_Bool:
		result.path, result.expected_kind, result.actual_kind = "[:config :child :host-id]", int(Data_Access_Kind.Int), int(Data_Access_Kind.Bool)
	case .Nums_Map:
		result.path, result.expected_kind, result.actual_kind = "[:config :nums]", int(Data_Access_Kind.Vector), int(Data_Access_Kind.Map)
	case .Nums_Item_String:
		result.path, result.expected_kind, result.actual_kind = fmt.tprintf("[:config :nums %d]", input.index), int(Data_Access_Kind.Int), int(Data_Access_Kind.String)
	case .Flags_Item_Int:
		result.path, result.expected_kind, result.actual_kind = fmt.tprintf("[:config :flags %d]", input.index), int(Data_Access_Kind.Bool), int(Data_Access_Kind.Int)
	case .Ratios_Item_Bool:
		result.path, result.expected_kind, result.actual_kind = fmt.tprintf("[:config :ratios %d]", input.index), int(Data_Access_Kind.Float), int(Data_Access_Kind.Bool)
	case .Modes_Item_Invalid:
		result.path, result.expected_kind, result.actual_kind = fmt.tprintf("[:config :modes %d]", input.index), int(Data_Access_Kind.Keyword), int(Data_Access_Kind.Keyword)
		result.enum_value, result.expected_type, result.actual_value = true, "Mode", ":unknown"
	case .Children_Item_Int:
		result.path, result.expected_kind, result.actual_kind = fmt.tprintf("[:config :children %d]", input.index), int(Data_Access_Kind.Map), int(Data_Access_Kind.Int)
	case .Children_Id_String:
		result.path, result.expected_kind, result.actual_kind = fmt.tprintf("[:config :children %d :host-id]", input.index), int(Data_Access_Kind.Int), int(Data_Access_Kind.String)
	}
	return result
}

typed_decode_summary :: proc(input: Typed_Decode_Input) -> [TYPED_DECODE_SUMMARY_COUNT]int {
	result: [TYPED_DECODE_SUMMARY_COUNT]int
	if input.corruption != .Valid {
		return result
	}
	result[0] = input.port
	result[1] = input.enabled ? 1 : 0
	result[2] = input.mode
	result[3] = input.child_id
	result[4] = input.child_active ? 1 : 0
	for index in 0 ..< input.length {
		result[5] += input.nums[index]
		result[6] += input.flags[index] ? 1 : 0
		result[7] += input.modes[index]
		result[8] += input.children_ids[index]
		result[9] += input.children_active[index] ? 1 : 0
	}
	result[10], result[11], result[12], result[13] = 1, 1, 1, 1
	return result
}

typed_decode_request :: proc(input: Typed_Decode_Input) -> string {
	if input.corruption == .Root_Vector {
		return "[]"
	}
	builder: strings.Builder
	strings.builder_init(&builder, context.temp_allocator)
	strings.write_byte(&builder, '{')
	if input.corruption != .Port_Missing {
		strings.write_string(&builder, ":port ")
		if input.corruption == .Port_String {
			strings.write_string(&builder, `"bad"`)
		} else {
			fmt.sbprintf(&builder, "%d", input.port)
		}
		strings.write_byte(&builder, ' ')
	}
	strings.write_string(&builder, ":enabled ")
	if input.corruption == .Enabled_Int {
		strings.write_byte(&builder, '1')
	} else {
		strings.write_string(&builder, input.enabled ? "true" : "false")
	}
	strings.write_string(&builder, " :ratio ")
	if input.corruption == .Ratio_Int {
		strings.write_byte(&builder, '1')
	} else {
		fmt.sbprintf(&builder, "%d.250", input.ratio_whole)
	}
	strings.write_string(&builder, " :mode ")
	if input.corruption == .Mode_Int {
		strings.write_byte(&builder, '1')
	} else if input.corruption == .Mode_Invalid {
		strings.write_string(&builder, ":unknown")
	} else {
		strings.write_string(&builder, typed_decode_mode_keyword(input.mode))
	}
	strings.write_string(&builder, " :name ")
	strings.write_string(&builder, input.corruption == .Name_Keyword ? ":bad" : `"service"`)
	strings.write_string(&builder, " :child ")
	typed_decode_write_child(&builder, input.child_id, input.child_active, input.corruption, false)
	strings.write_string(&builder, " :nums ")
	if input.corruption == .Nums_Map {
		strings.write_string(&builder, "{}")
	} else {
		typed_decode_write_ints(&builder, input, .Nums_Item_String)
	}
	strings.write_string(&builder, " :flags ")
	typed_decode_write_bools(&builder, input, .Flags_Item_Int)
	strings.write_string(&builder, " :ratios ")
	typed_decode_write_ratios(&builder, input)
	strings.write_string(&builder, " :modes ")
	typed_decode_write_modes(&builder, input)
	strings.write_string(&builder, " :children ")
	typed_decode_write_children(&builder, input)
	strings.write_string(&builder, " :raw {:seed ")
	fmt.sbprintf(&builder, "%d", input.raw_seed)
	strings.write_string(&builder, "}}")
	return strings.to_string(builder)
}

typed_decode_write_child :: proc(builder: ^strings.Builder, id: int, active: bool, corruption: Typed_Decode_Corruption, nested: bool) {
	if (!nested && corruption == .Child_Int) || (nested && corruption == .Children_Item_Int) {
		strings.write_byte(builder, '1')
		return
	}
	strings.write_byte(builder, '{')
	if (!nested && corruption != .Child_Id_Missing) {
		strings.write_string(builder, ":host-id ")
		if corruption == .Child_Id_Bool {
			strings.write_string(builder, "false")
		} else {
			fmt.sbprintf(builder, "%d", id)
		}
		strings.write_byte(builder, ' ')
	} else if nested {
		strings.write_string(builder, ":host-id ")
		if corruption == .Children_Id_String {
			strings.write_string(builder, `"bad"`)
		} else {
			fmt.sbprintf(builder, "%d", id)
		}
		strings.write_byte(builder, ' ')
	}
	strings.write_string(builder, active ? ":active true}" : ":active false}")
}

typed_decode_write_ints :: proc(builder: ^strings.Builder, input: Typed_Decode_Input, corruption: Typed_Decode_Corruption) {
	strings.write_byte(builder, '[')
	for index in 0 ..< input.length {
		if index > 0 { strings.write_byte(builder, ' ') }
		if input.corruption == corruption && index == input.index {
			strings.write_string(builder, `"bad"`)
		} else {
			fmt.sbprintf(builder, "%d", input.nums[index])
		}
	}
	strings.write_byte(builder, ']')
}

typed_decode_write_bools :: proc(builder: ^strings.Builder, input: Typed_Decode_Input, corruption: Typed_Decode_Corruption) {
	strings.write_byte(builder, '[')
	for index in 0 ..< input.length {
		if index > 0 { strings.write_byte(builder, ' ') }
		if input.corruption == corruption && index == input.index {
			strings.write_byte(builder, '1')
		} else {
			strings.write_string(builder, input.flags[index] ? "true" : "false")
		}
	}
	strings.write_byte(builder, ']')
}

typed_decode_write_ratios :: proc(builder: ^strings.Builder, input: Typed_Decode_Input) {
	strings.write_byte(builder, '[')
	for index in 0 ..< input.length {
		if index > 0 { strings.write_byte(builder, ' ') }
		if input.corruption == .Ratios_Item_Bool && index == input.index {
			strings.write_string(builder, "false")
		} else {
			fmt.sbprintf(builder, "%d.500", input.ratios[index])
		}
	}
	strings.write_byte(builder, ']')
}

typed_decode_write_modes :: proc(builder: ^strings.Builder, input: Typed_Decode_Input) {
	strings.write_byte(builder, '[')
	for index in 0 ..< input.length {
		if index > 0 { strings.write_byte(builder, ' ') }
		if input.corruption == .Modes_Item_Invalid && index == input.index {
			strings.write_string(builder, ":unknown")
		} else {
			strings.write_string(builder, typed_decode_mode_keyword(input.modes[index]))
		}
	}
	strings.write_byte(builder, ']')
}

typed_decode_write_children :: proc(builder: ^strings.Builder, input: Typed_Decode_Input) {
	strings.write_byte(builder, '[')
	for index in 0 ..< input.length {
		if index > 0 { strings.write_byte(builder, ' ') }
		corruption := Typed_Decode_Corruption.Valid
		if index == input.index && (input.corruption == .Children_Item_Int || input.corruption == .Children_Id_String) {
			corruption = input.corruption
		}
		typed_decode_write_child(builder, input.children_ids[index], input.children_active[index], corruption, true)
	}
	strings.write_byte(builder, ']')
}

typed_decode_mode_keyword :: proc(mode: int) -> string {
	switch mode {
	case 0: return ":manual"
	case 1: return ":automatic"
	case 2: return ":read-only"
	}
	return ":manual"
}
