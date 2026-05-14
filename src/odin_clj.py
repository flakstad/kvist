from __future__ import annotations

import argparse
import dataclasses
import pathlib
import sys
from typing import Iterable


@dataclasses.dataclass(frozen=True)
class Symbol:
    name: str


Atom = Symbol | str | int | float
Form = Atom | list["Form"]


INFIX = {
    "+": "+",
    "-": "-",
    "*": "*",
    "/": "/",
    "%": "%",
    "==": "==",
    "!=": "!=",
    "<": "<",
    "<=": "<=",
    ">": ">",
    ">=": ">=",
    "and": "&&",
    "or": "||",
    "&": "&",
    "|": "|",
    "^": "~",
}


class ReaderError(Exception):
    pass


class EmitError(Exception):
    pass


def tokenize(source: str) -> list[str]:
    tokens: list[str] = []
    i = 0
    while i < len(source):
        ch = source[i]
        if ch.isspace():
            i += 1
            continue
        if ch == ";":
            while i < len(source) and source[i] != "\n":
                i += 1
            continue
        if ch in "()[]":
            tokens.append(ch)
            i += 1
            continue
        if ch == '"':
            start = i
            i += 1
            escaped = False
            while i < len(source):
                c = source[i]
                if escaped:
                    escaped = False
                elif c == "\\":
                    escaped = True
                elif c == '"':
                    i += 1
                    tokens.append(source[start:i])
                    break
                i += 1
            else:
                raise ReaderError("unterminated string literal")
            continue
        start = i
        while i < len(source) and (not source[i].isspace()) and source[i] not in "()[]":
            i += 1
        tokens.append(source[start:i])
    return tokens


def parse_atom(token: str) -> Atom:
    if token.startswith('"'):
        return token
    try:
        if "." not in token:
            return int(token)
        return float(token)
    except ValueError:
        return Symbol(token)


def read_forms(source: str) -> list[Form]:
    tokens = tokenize(source)
    index = 0

    def read_one() -> Form:
        nonlocal index
        if index >= len(tokens):
            raise ReaderError("unexpected end of input")
        token = tokens[index]
        index += 1
        if token in ("(", "["):
            closer = ")" if token == "(" else "]"
            out: list[Form] = []
            while index < len(tokens) and tokens[index] != closer:
                out.append(read_one())
            if index >= len(tokens):
                raise ReaderError(f"missing {closer}")
            index += 1
            return out
        if token in (")", "]"):
            raise ReaderError(f"unexpected {token}")
        return parse_atom(token)

    forms: list[Form] = []
    while index < len(tokens):
        forms.append(read_one())
    return forms


def sym_name(form: Form) -> str:
    if isinstance(form, Symbol):
        return form.name
    raise EmitError(f"expected symbol, got {form!r}")


def is_symbol(form: Form, name: str) -> bool:
    return isinstance(form, Symbol) and form.name == name


def indent(level: int) -> str:
    return "    " * level


def emit_type(form: Form) -> str:
    if isinstance(form, Symbol):
        return form.name
    if isinstance(form, str):
        return form
    if isinstance(form, list) and form:
        head = sym_name(form[0])
        if head == "^" and len(form) == 2:
            return f"^{emit_type(form[1])}"
        if head == "[]" and len(form) == 2:
            return f"[]{emit_type(form[1])}"
        if head == "[dynamic]" and len(form) == 2:
            return f"[dynamic]{emit_type(form[1])}"
    raise EmitError(f"unsupported type form: {form!r}")


def emit_expr(form: Form) -> str:
    if isinstance(form, Symbol):
        return form.name
    if isinstance(form, (int, float)):
        return str(form)
    if isinstance(form, str):
        return form
    if not form:
        raise EmitError("empty expression list")

    head = sym_name(form[0])
    args = form[1:]

    if head == "odin":
        if len(args) != 1 or not isinstance(args[0], str):
            raise EmitError("(odin ...) expression expects one string")
        return args[0][1:-1]

    if head in INFIX:
        if len(args) == 1 and head == "-":
            return f"-{emit_expr(args[0])}"
        return f" {INFIX[head]} ".join(emit_expr(arg) for arg in args)

    if head == "cast":
        if len(args) != 2:
            raise EmitError("cast expects type and expression")
        return f"cast({emit_type(args[0])})({emit_expr(args[1])})"

    if head == "index":
        if len(args) != 2:
            raise EmitError("index expects collection and index")
        return f"{emit_expr(args[0])}[{emit_expr(args[1])}]"

    if head == "field":
        if len(args) != 2:
            raise EmitError("field expects value and field name")
        return f"{emit_expr(args[0])}.{sym_name(args[1])}"

    return f"{head}({', '.join(emit_expr(arg) for arg in args)})"


def emit_block(forms: Iterable[Form], level: int) -> str:
    lines: list[str] = ["{"]
    for form in forms:
        lines.append(emit_stmt(form, level + 1))
    lines.append(f"{indent(level)}}}")
    return "\n".join(lines)


def emit_params(params: Form) -> str:
    if not isinstance(params, list):
        raise EmitError("proc params must be a vector/list")
    out: list[str] = []
    for param in params:
        if not isinstance(param, list) or len(param) != 2:
            raise EmitError(f"param must be (name type), got {param!r}")
        out.append(f"{sym_name(param[0])}: {emit_type(param[1])}")
    return ", ".join(out)


def emit_stmt(form: Form, level: int = 0) -> str:
    prefix = indent(level)
    if not isinstance(form, list) or not form:
        return f"{prefix}{emit_expr(form)}"

    head = sym_name(form[0])
    args = form[1:]

    if head == "package":
        if len(args) != 1:
            raise EmitError("package expects one name")
        return f"package {sym_name(args[0])}"

    if head == "import":
        if len(args) != 1:
            raise EmitError("import expects one path")
        return f'import {emit_expr(args[0])}'

    if head == "proc":
        if len(args) < 3:
            raise EmitError("proc expects name, params, return type, and body")
        name = sym_name(args[0])
        params = emit_params(args[1])
        ret = emit_type(args[2])
        arrow = "" if ret == "void" else f" -> {ret}"
        return f"{name} :: proc({params}){arrow} {emit_block(args[3:], level)}"

    if head == "let":
        if len(args) == 2:
            return f"{prefix}{sym_name(args[0])} := {emit_expr(args[1])}"
        if len(args) == 3:
            return f"{prefix}{sym_name(args[0])}: {emit_type(args[1])} = {emit_expr(args[2])}"
        raise EmitError("let expects name expr or name type expr")

    if head == "const":
        if len(args) == 2:
            return f"{prefix}{sym_name(args[0])} :: {emit_expr(args[1])}"
        if len(args) == 3:
            return f"{prefix}{sym_name(args[0])}: {emit_type(args[1])} : {emit_expr(args[2])}"
        raise EmitError("const expects name expr or name type expr")

    if head == "set!":
        if len(args) != 2:
            raise EmitError("set! expects place and expression")
        return f"{prefix}{emit_expr(args[0])} = {emit_expr(args[1])}"

    if head in {"+=", "-=", "*=", "/="}:
        if len(args) != 2:
            raise EmitError(f"{head} expects place and expression")
        return f"{prefix}{emit_expr(args[0])} {head} {emit_expr(args[1])}"

    if head == "return":
        if len(args) == 0:
            return f"{prefix}return"
        if len(args) == 1:
            return f"{prefix}return {emit_expr(args[0])}"
        raise EmitError("return expects zero or one expression")

    if head == "if":
        if len(args) not in (2, 3):
            raise EmitError("if expects test, then, optional else")
        then = emit_block([args[1]], level)
        out = f"{prefix}if {emit_expr(args[0])} {then}"
        if len(args) == 3:
            out += f" else {emit_block([args[2]], level)}"
        return out

    if head == "when":
        if len(args) < 2:
            raise EmitError("when expects test and body")
        return f"{prefix}if {emit_expr(args[0])} {emit_block(args[1:], level)}"

    if head == "for":
        if len(args) < 2 or not isinstance(args[0], list) or len(args[0]) != 3:
            raise EmitError("for expects [init test post] and body")
        init = emit_for_clause(args[0][0])
        test = emit_expr(args[0][1])
        post = emit_for_clause(args[0][2])
        return f"{prefix}for {init}; {test}; {post} {emit_block(args[1:], level)}"

    if head == "for-in":
        if len(args) < 3:
            raise EmitError("for-in expects name, collection, and body")
        return f"{prefix}for {sym_name(args[0])} in {emit_expr(args[1])} {emit_block(args[2:], level)}"

    if head == "block":
        return prefix + emit_block(args, level)

    if head == "odin":
        if len(args) != 1 or not isinstance(args[0], str):
            raise EmitError("(odin ...) statement expects one string")
        return f"{prefix}{args[0][1:-1]}"

    return f"{prefix}{emit_expr(form)}"


def emit_for_clause(form: Form) -> str:
    stmt = emit_stmt(form, 0).strip()
    return stmt[:-1] if stmt.endswith(";") else stmt


def emit_program(forms: list[Form]) -> str:
    chunks: list[str] = []
    for form in forms:
        chunks.append(emit_stmt(form, 0))
    return "\n\n".join(chunks) + "\n"


def translate(source: str) -> str:
    return emit_program(read_forms(source))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Translate odin-clj source to Odin.")
    parser.add_argument("input", type=pathlib.Path)
    parser.add_argument("-o", "--output", type=pathlib.Path)
    args = parser.parse_args(argv)

    try:
        output = translate(args.input.read_text())
    except (ReaderError, EmitError) as exc:
        print(f"odin-clj: {exc}", file=sys.stderr)
        return 1

    if args.output:
        args.output.write_text(output)
    else:
        print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
