// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist_live

import "core:strings"
import kvist "../kvist"

clone_string_slice :: proc(values: []string) -> (out: [dynamic]string) {
    for value in values {
        append(&out, strings.clone(value))
    }
    return out
}

delete_string_slice :: proc(values: ^[dynamic]string) {
    for i in 0 ..< len(values^) {
        if values^[i] != "" {
            delete(values^[i])
        }
    }
    delete(values^)
    values^ = nil
}

clone_cst_form :: proc(form: kvist.CST_Form) -> kvist.CST_Form {
    cloned := form
    cloned.text = strings.clone(form.text)
    cloned.items = nil
    for item in form.items {
        append(&cloned.items, clone_cst_form(item))
    }
    return cloned
}

delete_cst_form :: proc(form: ^kvist.CST_Form) {
    if form.text != "" {
        delete(form.text)
    }
    for i in 0 ..< len(form.items) {
        delete_cst_form(&form.items[i])
    }
    delete(form.items)
    form^ = kvist.CST_Form{}
}

clone_cst_form_slice :: proc(forms: []kvist.CST_Form) -> (out: [dynamic]kvist.CST_Form) {
    for form in forms {
        append(&out, clone_cst_form(form))
    }
    return out
}

delete_cst_form_slice :: proc(forms: ^[dynamic]kvist.CST_Form) {
    for i in 0 ..< len(forms^) {
        delete_cst_form(&forms^[i])
    }
    delete(forms^)
    forms^ = nil
}

clone_behavior_definition :: proc(def: Behavior_Definition) -> Behavior_Definition {
    return Behavior_Definition{
        name = strings.clone(def.name),
        doc = strings.clone(def.doc),
        params = clone_string_slice(def.params[:]),
        body = clone_cst_form_slice(def.body[:]),
    }
}

delete_behavior_definition :: proc(def: ^Behavior_Definition) {
    if def.name != "" {
        delete(def.name)
    }
    if def.doc != "" {
        delete(def.doc)
    }
    delete_string_slice(&def.params)
    delete_cst_form_slice(&def.body)
    def^ = Behavior_Definition{}
}

clone_behavior_definition_slice :: proc(defs: []Behavior_Definition) -> (out: [dynamic]Behavior_Definition) {
    for def in defs {
        append(&out, clone_behavior_definition(def))
    }
    return out
}

delete_behavior_definition_slice :: proc(defs: ^[dynamic]Behavior_Definition) {
    for i in 0 ..< len(defs^) {
        delete_behavior_definition(&defs^[i])
    }
    delete(defs^)
    defs^ = nil
}
