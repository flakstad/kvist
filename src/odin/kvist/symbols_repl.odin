// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "base:runtime"

language_entry_signature :: proc(entry: Language_Source_Entry) -> string {
    if entry.signature != "" {
        return entry.signature
    }
    switch entry.name {
    case "package": return "(package name)"
    case "import": return "(import \"path\" :as alias :refer [name ...])"
    case "foreign-import": return "(foreign-import alias \"library\")"
    case "def", "def-": return "(def name: Type value)"
    case "defvar", "defvar-": return "(defvar name: Type value?)"
    case "defstruct", "defstruct-": return "(defstruct Name {field: Type ...})"
    case "defenum", "defenum-": return "(defenum Name [Member ...])"
    case "defunion", "defunion-": return "(defunion Name {variant: Type ...})"
    case "defn", "defn-": return "(defn name docstring? [params ...] -> Return body ...)"
    case "defmacro", "defmacro-": return "(defmacro name docstring? [params ...] body ...)"
    case "deftransform", "deftransform-": return "(deftransform name transform)"
    case "defiter", "defiter-": return "(defiter name [params ...] -> State :yield Item :next next-fn :dispose dispose-fn? opener)"
    case "@export": return "@export declaration"
    case "@private": return "@private declaration"
    case "@exports": return "(@exports [Odin-Name ...])"
    case "fn": return "(fn [params ...] -> Return body ...)"
    case "odin": return "(odin \"Odin source\")"
    case "let": return "(let [binding value ...] body ...)"
    case "block": return "(block label? body ...)"
    case "do": return "(do expression ...)"
    case "if": return "(if test then else?)"
    case "match": return "(match value pattern body ... :else fallback ...)"
    case "set!": return "(set! place value)"
    case "mut!": return "(mut! place operator value)"
    case "return": return "(return value ...)"
    case "discard": return "(discard expression ...)"
    case "defer": return "(defer expression ...)"
    case "for": return "(for [binding collection] body ...)"
    case "make": return "(make Type length? capacity?)"
    case "alloc": return "(alloc Type allocator?)"
    case "delete": return "(delete owned-value)"
    case "zero": return "(zero Type)"
    case "overload": return "(overload function ...)"
    case "where": return "(where compile-time-condition)"
    case "type": return "(type value)"
    case "typeid": return "(typeid Type-Constructor Type ...)"
    case "ptr": return "(ptr Type)"
    case "transmute": return "(transmute Type value)"
    case "type-assert": return "(type-assert value Type)"
    case "as->": return "(as-> value name expression ...)"
    case "deref": return "(deref pointer)"
    case "addr": return "(addr place)"
    case "break": return "(break label?)"
    case "continue": return "(continue label?)"
    case "while": return "(while test body ...)"
    case "with-allocator": return "(with-allocator [allocator expression] body ...)"
    case "with-temp-allocator": return "(with-temp-allocator [allocator] body ...)"
    }
    return ""
}
language_entry_doc :: proc(entry: Language_Source_Entry) -> string {
    if entry.doc != "" {
        return entry.doc
    }
    switch entry.name {
    case "package":
        return "Declare the Odin package emitted by this Kvist source package. Imported package files must declare exactly one consistent package name.\n\nExample:\n  (package main)"
    case "import":
        return "Load a Kvist or Odin package. Use :as for qualified access, :refer for selected bare names, or both; relative paths follow Odin's folder-based package model.\n\nExamples:\n  (import \"kvist:arr\" :as arr)\n  (import \"kvist:data\" :as data :refer [empty-map])"
    case "foreign-import":
        return "Declare an Odin foreign library import for symbols provided by the linker.\n\nExample:\n  (foreign-import sqlite \"system:sqlite3\")"
    case "def", "def-":
        return "Define an immutable package or local binding. A top-level def is exported; def- is package-private. Explicit types make retained REPL definitions stable across generations.\n\nExample:\n  (def answer: int 42)"
    case "defvar", "defvar-":
        return "Define mutable package state. A top-level defvar is exported; defvar- is package-private. Use set!, mut!, or the unary mutation forms to update it.\n\nExample:\n  (defvar requests: int 0)"
    case "defstruct", "defstruct-":
        return "Define a nominal struct with named fields. defstruct- keeps the type private to its source package. Construct values with type-call syntax.\n\nExample:\n  (defstruct User {name: string age: int})\n  (User {name: \"Ada\" age: 36})"
    case "defenum", "defenum-":
        return "Define a nominal enum. Members may be listed in a vector or assigned explicit values in braces; defenum- is package-private.\n\nExample:\n  (defenum Status [Ready Running Done])"
    case "defunion", "defunion-":
        return "Define a tagged union of named payload alternatives. defunion- keeps it package-private; use case to inspect the active payload.\n\nExample:\n  (defunion Value {number: int text: string})"
    case "defn", "defn-":
        return "Define a native, eagerly compiled procedure. Parameters and return values use Odin types; an optional docstring follows the name. defn- is package-private. Re-evaluating a compatible defn updates its live REPL slot.\n\nExample:\n  (defn square \"Return x squared.\" [x: int] -> int\n    (* x x))"
    case "defmacro", "defmacro-":
        return "Define a compile-time source transformation using Kvist forms, quoting, and unquote. defmacro- keeps the macro private to its package.\n\nExample:\n  (defmacro unless [test & body]\n    `(if (not ~test) (do ~@body)))"
    case "deftransform", "deftransform-":
        return "Name a reusable fused transform pipeline. Consumers such as into and transduce compile the composed stages into one eager loop without intermediate collections. deftransform- is package-private.\n\nExample:\n  (deftransform active-names\n    (comp (filter .active) (map .name)))"
    case "defiter", "defiter-":
        return "Define a reusable stateful source for for, into, and transduce. The opener returns State; :next yields [Item bool], and optional :dispose releases producer state. defiter- is package-private."
    case "@export": return "Attach Odin @(export) to the next declaration, commonly for a foreign-ABI callback.\n\nExample:\n  @export\n  (defn callback :abi \"c\" [ctx: rawptr] -> void ...)"
    case "@private": return "Attach Odin @(private) to the next declaration. Prefer the trailing-dash declaration forms for ordinary Kvist package privacy."
    case "@exports": return "Expose named declarations supplied by raw Odin sidecar files through a Kvist source package.\n\nExample:\n  (@exports [Raw_Handle])"
    case "fn": return "Create an anonymous native procedure value, or describe a procedure type in type position.\n\nExample:\n  (fn [x: int] -> int (+ x 1))"
    case "odin": return "Embed explicit Odin source when no canonical Kvist form exists. Expression escapes can be evaluated at the REPL; arbitrary result types are not inferred for *1 history.\n\nExample:\n  (odin \"1 + 1\")"
    case "let": return "Evaluate binding expressions from left to right, then evaluate the body in their lexical scope. The final body expression is the result.\n\nExample:\n  (let [x 2 y 3] (+ x y))"
    case "block": return "Evaluate a statement block, optionally named for labelled break. Use do for ordinary expression sequencing."
    case "do": return "Evaluate expressions eagerly from left to right and return the final value.\n\nExample:\n  (do (println \"starting\") 42)"
    case "if": return "Evaluate test, then exactly one branch. Tests must be boolean; the optional missing else produces the zero value required by context.\n\nExample:\n  (if (> n 0) n (- n))"
    case "match": return "Match a value against patterns in order and evaluate the first matching body; use :else for the fallback."
    case "set!": return "Assign value directly to a mutable place such as a defvar, local var, field, index, or dereferenced pointer.\n\nExample:\n  (set! user.name \"Grace\")"
    case "mut!": return "Apply an Odin compound assignment operator to a mutable place.\n\nExample:\n  (mut! total += amount)"
    case "return": return "Return immediately from the enclosing procedure, optionally with multiple native return values.\n\nExample:\n  (return value true)"
    case "discard": return "Evaluate expressions for their effects while explicitly discarding their results."
    case "defer": return "Schedule an expression to run when the enclosing native scope exits, following Odin's defer semantics.\n\nExample:\n  (defer (file.close handle))"
    case "for": return "Iterate eagerly over a native collection, map, or defiter source. Transform clauses can fuse mapping and filtering into the loop.\n\nExample:\n  (for [x xs] (println x))"
    case "make": return "Allocate and initialize a native slice, dynamic array, map, or other Odin make-compatible type with the current allocator.\n\nExample:\n  (make [dynamic]int 0 16)"
    case "alloc": return "Allocate one zero-initialized value of Type and return a pointer, using the current allocator unless another allocator is supplied.\n\nExample:\n  (alloc Node context.temp_allocator)"
    case "delete": return "Release storage owned by a pointer, dynamic array, map, slice allocation, or other Odin delete-compatible value. Do not use the value afterward.\n\nExample:\n  (defer (delete xs))"
    case "zero": return "Construct the zero value of an explicitly named type without allocating.\n\nExample:\n  (zero [2]f32)"
    case "overload": return "Construct an Odin procedure overload set from compatible function declarations; bind it with def or a local def.\n\nExample:\n  (def render (overload render-int render-user))"
    case "where": return "Constrain a polymorphic defn with a compile-time boolean predicate, following the parameter vector.\n\nExample:\n  (where (intrinsics.type-is-comparable T))"
    case "type": return "Return a comparable descriptor for the type of a value, function, type name, or Data runtime kind.\n\nExample:\n  (type 42) ; => int"
    case "typeid": return "Instantiate an Odin polymorphic type constructor or pass a type as a typeid value.\n\nExample:\n  (typeid chan.Chan int)"
    case "ptr": return "Construct a pointer type in type position. The equivalent compact spelling is ^Type.\n\nExample:\n  (ptr User)"
    case "transmute": return "Reinterpret value as Type using Odin's explicit transmute operation. This is low-level and does not perform a semantic conversion.\n\nExample:\n  (transmute []byte text)"
    case "type-assert": return "Assert that a union or any-like value contains Type and return the asserted payload, following Odin selector assertion semantics.\n\nExample:\n  (type-assert handler.next ^h.Handler)"
    case "as->": return "Thread a value through expressions by repeatedly binding name to the previous result. The name may appear anywhere, and steps may change type.\n\nExample:\n  (as-> user x (visit x) (attach-bonus bonus x) x.age)"
    case "deref": return "Read the value addressed by a pointer. The shorthand spelling is ^ in expression position.\n\nExample:\n  (deref user-pointer)"
    case "addr": return "Take the address of an addressable place. The shorthand spelling is &.\n\nExample:\n  (addr user)"
    case "break": return "Exit the nearest loop or named block immediately. An optional label selects the target block."
    case "continue": return "Skip the rest of the current loop iteration and begin the next one. An optional label selects the loop."
    case "while": return "Repeatedly evaluate body while the boolean test remains true.\n\nExample:\n  (while (< i 10) (inc! i))"
    case "with-allocator": return "Temporarily install an allocator as context.allocator for the body, restoring the previous allocator on exit.\n\nExample:\n  (with-allocator [a context.temp_allocator] (build a))"
    case "with-temp-allocator": return "Start a scoped temporary allocator region, bind its allocator, evaluate the body, then release the entire region. Values backed by it must not escape.\n\nExample:\n  (with-temp-allocator [a] (build-temporary a))"
    }
    return ""
}

language_symbol_doc_text :: proc(internal_name: string) -> (string, bool) {
    for entry in LANGUAGE_SOURCE_ENTRIES {
        mapped_name := map_name(entry.name)
        matches := entry.name == internal_name || mapped_name == internal_name
        delete(mapped_name)
        doc := language_entry_doc(entry)
        if !matches || doc == "" {
            continue
        }
        return strings.clone(doc), true
    }
    return "", false
}

symbols_unescape_doc_text :: proc(text: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    i := 0
    for i < len(text) {
        if text[i] == '\\' && i+1 < len(text) {
            switch text[i+1] {
            case 'n':
                strings.write_byte(&builder, '\n')
                i += 2
                continue
            case 't':
                strings.write_byte(&builder, '\t')
                i += 2
                continue
            case '\\':
                strings.write_byte(&builder, '\\')
                i += 2
                continue
            }
        }
        strings.write_byte(&builder, text[i])
        i += 1
    }
    return strings.clone(strings.to_string(builder))
}
