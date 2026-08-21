// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:os"

import pbt "pbt:pbt"

READER_TAGS := [?]string{"reader", "native"}
EDN_TAGS := [?]string{"edn", "runtime", "external"}
DATA_MAP_TAGS := [?]string{"data", "map", "stateful", "runtime", "external"}
DATA_NESTED_TAGS := [?]string{"data", "nested", "stateful", "runtime", "external"}
DATA_SEQUENCE_TAGS := [?]string{"data", "sequence", "stateful", "runtime", "external"}
SET_TAGS := [?]string{"set", "model", "runtime", "external"}
DATA_TRANSFORM_TAGS := [?]string{"data", "transform", "model", "runtime", "external"}
MAP_TAGS := [?]string{"map", "model", "runtime", "external"}
DATA_AGGREGATE_TAGS := [?]string{"data", "aggregate", "model", "runtime", "external"}
DATA_SCAN_TAGS := [?]string{"data", "scan", "sort", "partition", "model", "runtime", "external"}
DATA_MAP_TRANSFORM_TAGS := [?]string{"data", "map", "transform", "model", "runtime", "external"}
DATA_SET_TAGS := [?]string{"data", "set", "stateful", "model", "runtime", "external"}
DATA_ACCESS_TAGS := [?]string{"data", "access", "decode", "model", "runtime", "external"}
TYPED_DECODE_TAGS := [?]string{"data", "decode", "validate", "typed", "model", "runtime", "external"}

main :: proc() {
	properties := [?]pbt.Property_Case{
		{
			name = "generated reader forms have valid tokens and spans",
			property = generated_reader_forms_have_valid_tokens_and_spans,
			description = "grammar-generated Kvist forms tokenize and parse with source-bounded monotone spans",
			tags = READER_TAGS[:],
		},
		{
			name = "reader sugar matches explicit forms",
			property = reader_sugar_matches_explicit_forms,
			description = "quote, quasiquote, unquote, and splice reader sugar normalize to their explicit list forms",
			tags = READER_TAGS[:],
		},
		{
			name = "reader layout does not change CST",
			property = reader_layout_does_not_change_cst,
			description = "compact and whitespace, comma, and comment-perturbed renderings produce the same normalized CST",
			tags = READER_TAGS[:],
		},
		{
			name = "missing generated closing delimiter is rejected",
			property = missing_generated_closing_delimiter_is_rejected,
			description = "a generated balanced form inside an unclosed list reports a bounded missing-delimiter error",
			tags = READER_TAGS[:],
		},
		{
			name = "generated reader corruption is rejected",
			property = generated_reader_corruption_is_rejected,
			description = "mismatched and extra delimiters and unterminated string and regex literals fail with bounded diagnostics",
			tags = READER_TAGS[:],
		},
		{
			name = "EDN roundtrip is canonical",
			property = edn_roundtrip_is_canonical,
			description = "generated EDN values survive structural and canonical roundtrips through a compiled Kvist target",
			tags = EDN_TAGS[:],
		},
		{
			name = "Data map commands match model",
			property = data_map_commands_match_model,
			description = "stateful assoc, dissoc, and lookup sequences agree with an independent fixed-key map model",
			tags = DATA_MAP_TAGS[:],
		},
		{
			name = "nested Data commands match model",
			property = data_nested_commands_match_model,
			description = "stateful assoc-in, update-in, get-in, and dissoc-in sequences agree with an independent nested map model",
			tags = DATA_NESTED_TAGS[:],
		},
		{
			name = "Data sequence commands match model",
			property = data_sequence_commands_match_model,
			description = "stateful vector and list operations agree with an independent bounded sequence model",
			tags = DATA_SEQUENCE_TAGS[:],
		},
		{
			name = "native set operations match bitmask model",
			property = native_set_operations_match_bitmask_model,
			description = "pure and mutating kvist:set operations agree with an independent finite-domain bitmask model",
			tags = SET_TAGS[:],
		},
		{
			name = "Data transforms match sequence model",
			property = data_transforms_match_sequence_model,
			description = "eager Data sequence transforms and metamorphic identities agree with an independent bounded model",
			tags = DATA_TRANSFORM_TAGS[:],
		},
		{
			name = "native map operations match model",
			property = native_map_operations_match_model,
			description = "pure and mutating kvist:map operations and projections agree with an independent finite-domain model",
			tags = MAP_TAGS[:],
		},
		{
			name = "Data aggregates match model",
			property = data_aggregates_match_model,
			description = "Data reductions, frequencies, grouping, counting, and indexing agree with an independent bounded model",
			tags = DATA_AGGREGATE_TAGS[:],
		},
		{
			name = "Data scans and partitions match model",
			property = data_scans_and_partitions_match_model,
			description = "Data searches, stable ordering, prefix scans, and partitioning agree with an independent bounded model",
			tags = DATA_SCAN_TAGS[:],
		},
		{
			name = "Data map transforms match model",
			property = data_map_transforms_match_model,
			description = "Data map selection, merging, callbacks, projections, and into agree with an independent finite-domain model",
			tags = DATA_MAP_TRANSFORM_TAGS[:],
		},
		{
			name = "Data set commands match bitmask model",
			property = data_set_commands_match_bitmask_model,
			description = "stateful Data set insertion, probing, conversion, and roundtrips agree with a finite-domain bitmask model",
			tags = DATA_SET_TAGS[:],
		},
		{
			name = "Data accessors match shallow model",
			property = data_accessors_match_shallow_model,
			description = "Data kinds, predicates, accessors, descriptions, and primitive decoders agree with a shallow typed model",
			tags = DATA_ACCESS_TAGS[:],
		},
		{
			name = "typed decode and validate match model",
			property = typed_decode_and_validate_match_model,
			description = "typed nested decoding and validation agree on generated values and exact targeted error metadata",
			tags = TYPED_DECODE_TAGS[:],
		},
	}

	pbt.run_cli(properties[:], os.args[1:], {
		num_tests = 1_000,
		max_size = 64,
		shrink = true,
	})
}
