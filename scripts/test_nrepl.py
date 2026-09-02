#!/usr/bin/env python3
"""Cross-platform end-to-end test for the Kvist nREPL adapter."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from typing import BinaryIO, Any
import uuid


ROOT = Path(__file__).resolve().parent.parent


def encode(value: Any) -> bytes:
    if isinstance(value, str):
        raw = value.encode("utf-8")
        return str(len(raw)).encode("ascii") + b":" + raw
    if isinstance(value, int):
        return b"i" + str(value).encode("ascii") + b"e"
    if isinstance(value, list):
        return b"l" + b"".join(encode(item) for item in value) + b"e"
    if isinstance(value, dict):
        return b"d" + b"".join(
            encode(key) + encode(item) for key, item in value.items()
        ) + b"e"
    raise TypeError(type(value))


def decode(stream: BinaryIO, first: bytes | None = None) -> Any:
    marker = first if first is not None else stream.read(1)
    if not marker:
        raise EOFError("nREPL connection closed")
    if marker == b"i":
        raw = bytearray()
        while True:
            byte = stream.read(1)
            if byte == b"e":
                return int(raw)
            raw.extend(byte)
    if marker == b"l":
        values = []
        while True:
            byte = stream.read(1)
            if byte == b"e":
                return values
            values.append(decode(stream, byte))
    if marker == b"d":
        values = {}
        while True:
            byte = stream.read(1)
            if byte == b"e":
                return values
            key = decode(stream, byte).decode("utf-8")
            values[key] = decode(stream)
    if b"0" <= marker <= b"9":
        digits = bytearray(marker)
        while True:
            byte = stream.read(1)
            if byte == b":":
                break
            digits.extend(byte)
        size = int(digits)
        value = stream.read(size)
        if len(value) != size:
            raise EOFError("short bencode string")
        return value
    raise ValueError(f"invalid bencode marker: {marker!r}")


def text(value: bytes) -> str:
    return value.decode("utf-8")


class Client:
    def __init__(self, port: int) -> None:
        self.socket = socket.create_connection(("127.0.0.1", port), timeout=10)
        self.stream = self.socket.makefile("rb")

    def close(self) -> None:
        self.stream.close()
        self.socket.close()

    def request(self, message: dict[str, Any]) -> list[dict[str, Any]]:
        self.socket.sendall(encode(message))
        responses = []
        while True:
            response = decode(self.stream)
            responses.append(response)
            statuses = [text(status) for status in response.get("status", [])]
            if "done" in statuses:
                return responses

    def send(self, message: dict[str, Any]) -> None:
        self.socket.sendall(encode(message))

    def receive_until_done(
        self, request_ids: set[str]
    ) -> dict[str, list[dict[str, Any]]]:
        responses = {request_id: [] for request_id in request_ids}
        done: set[str] = set()
        while done != request_ids:
            response = decode(self.stream)
            request_id = text(response.get("id", b""))
            if request_id not in responses:
                raise AssertionError(f"unexpected nREPL response id: {request_id!r}")
            responses[request_id].append(response)
            statuses = [text(status) for status in response.get("status", [])]
            if "done" in statuses:
                done.add(request_id)
        return responses


def exercise_adapter(client: Client) -> None:
    # This is Calva's TCP handshake: eval *ns*, clone, then describe the clone.
    namespace = client.request({"op": "eval", "code": "*ns*", "id": "namespace"})
    assert any(text(response.get("ns", b"")) == "user" for response in namespace)
    assert any(text(response.get("value", b"")) == "user" for response in namespace)
    assert not any(response.get("ex") for response in namespace)

    cloned = client.request(
        {
            "op": "clone",
            "client-name": "Calva",
            "client-version": "test",
            "id": "clone",
        }
    )[-1]
    session = text(cloned["new-session"])
    assert str(uuid.UUID(session)) == session
    assert uuid.UUID(session).version == 4

    described = client.request(
        {"op": "describe", "id": "describe", "verbose": 1, "session": session}
    )[-1]
    for operation in (
        "eval",
        "interrupt",
        "load-file",
        "complete",
        "info",
        "ns-list",
    ):
        assert operation in described["ops"]

    # Calva evaluates this Clojure-only form after connecting. Kvist treats it
    # as a compatibility probe rather than forwarding it to the compiler.
    calva_on_connect = client.request(
        {
            "id": "on-connect",
            "op": "eval",
            "ns": "user",
            "session": session,
            "code": "(when-let [requires (resolve 'clojure.main/repl-requires)] "
            "(clojure.core/apply clojure.core/require @requires))",
            "pprint": 0,
        }
    )
    assert any(
        text(response.get("value", b"")) == "nil" for response in calva_on_connect
    )
    assert not any(
        response.get("err") or response.get("ex") for response in calva_on_connect
    )

    unknown_session = client.request(
        {
            "id": "unknown-session-probe",
            "op": "eval",
            "session": "not-a-session",
            "code": "*ns*",
        }
    )
    assert "unknown-session" in [
        text(status) for status in unknown_session[-1]["status"]
    ]

    namespaces = client.request(
        {
            "op": "ns-list",
            "id": "namespaces",
            "session": session,
            "filter-regexps": [],
        }
    )[-1]
    assert [text(namespace) for namespace in namespaces["ns-list"]] == ["user"]

    client.request(
        {
            "id": "define",
            "op": "eval",
            "session": session,
            "code": "(def adapter-value: int 40)",
        }
    )
    evaluated = client.request(
        {
            "id": "eval",
            "op": "eval",
            "session": session,
            "code": "(+ adapter-value 2)",
        }
    )
    assert any(text(response.get("value", b"")) == "42" for response in evaluated)

    # Calva's "Copy last result" command evaluates *1 in the active session.
    last_result = client.request(
        {
            "id": "last-result",
            "op": "eval",
            "ns": "user",
            "session": session,
            "code": "*1",
        }
    )
    assert any(text(response.get("value", b"")) == "42" for response in last_result)

    loaded = client.request(
        {
            "id": "load",
            "op": "load-file",
            "session": session,
            "file-path": "adapter-test.kvist",
            "file": """(package adapter-test)
(comment (+ 100 200))
(def loaded-value: int 41)
(defstruct LoadedGreeting [message: string])
(defn main [] -> int 0)
(defn loaded-side-effect []
  (println "load-file-side-effect"))
(+ loaded-value 1)
(-> (LoadedGreeting :message "hei") .message count)
(loaded-side-effect)
(if true (loaded-side-effect) (loaded-side-effect))
(println "load-file-output")
(+ loaded-value 2)
""",
        }
    )
    assert any(
        text(response.get("value", b"")) == "43" for response in loaded
    ), loaded
    assert any(
        text(response.get("out", b"")) == "load-file-side-effect\n"
        for response in loaded
    )
    assert sum(
        text(response.get("out", b"")) == "load-file-side-effect\n"
        for response in loaded
    ) == 2
    assert any(
        text(response.get("out", b"")) == "load-file-output\n"
        for response in loaded
    )

    void_result = client.request(
        {
            "id": "void-result",
            "op": "eval",
            "session": session,
            "code": "(loaded-side-effect)",
        }
    )
    assert any(text(response.get("value", b"")) == "nil" for response in void_result)
    assert any(
        text(response.get("out", b"")) == "load-file-side-effect\n"
        for response in void_result
    )

    completed = client.request(
        {
            "id": "complete",
            "op": "completions",
            "session": session,
            "prefix": "pri",
        }
    )[-1]
    assert "println" in [text(item["candidate"]) for item in completed["completions"]]

    cider_completed = client.request(
        {
            "id": "cider-complete",
            "op": "cider/complete",
            "session": session,
            "prefix": "pri",
        }
    )[-1]
    cider_candidates = {
        text(item["candidate"]): text(item["type"])
        for item in cider_completed["completions"]
    }
    assert cider_candidates["println"] == "function"

    for request_id, context in (
        ("calva-complete", 0),
        ("calva-context-complete", "(println __prefix__)"),
    ):
        calva_completed = client.request(
            {
                "op": "complete",
                "ns": "user",
                "symbol": "pri",
                "id": request_id,
                "session": session,
                "context": context,
            }
        )[-1]
        assert "println" in [
            text(item["candidate"]) for item in calva_completed["completions"]
        ]

    looked_up = client.request(
        {
            "id": "lookup",
            "op": "lookup",
            "session": session,
            "sym": "println",
        }
    )[-1]
    assert text(looked_up["info"]["name"]) == "core.println"

    cider_info = client.request(
        {
            "id": "cider-info",
            "op": "cider/info",
            "session": session,
            "sym": "println",
        }
    )[-1]
    assert text(cider_info["name"]) == "core.println"
    assert text(cider_info["type"]) == "function"

    calva_info = client.request(
        {
            "op": "info",
            "ns": "user",
            "symbol": "println",
            "id": "calva-info",
            "session": session,
        }
    )[-1]
    assert text(calva_info["name"]) == "core.println"
    assert text(calva_info["type"]) == "function"
    assert text(calva_info["file"]).startswith("file:///")
    assert "println" in text(calva_info["arglists-str"])

    failed = client.request(
        {
            "id": "failed-eval",
            "op": "eval",
            "ns": "user",
            "session": session,
            "code": "(def broken-value: definitely-not-a-type 1)",
        }
    )
    final_failure = failed[-1]
    failure_statuses = [text(status) for status in final_failure["status"]]
    assert "eval-error" in failure_statuses
    assert text(final_failure["ex"]) == "kvist.EvaluationError"
    assert text(final_failure["root-ex"]) == "kvist.EvaluationError"
    assert not any("value" in response for response in failed)

    # Interrupt is read while eval is active, checks interrupt-id, terminates
    # arbitrary native code, and restarts the backend for later evaluations.
    client.send(
        {
            "id": "long-eval",
            "op": "eval",
            "session": session,
            "code": "(do (while true (discard 1)) 0)",
        }
    )
    client.send(
        {
            "id": "calva-java-version",
            "op": "eval",
            "session": session,
            "code": '(System/getProperty "java.version")',
        }
    )
    client.send(
        {
            "id": "active-unknown-session-probe",
            "op": "eval",
            "session": "not-a-session",
            "code": "*ns*",
        }
    )
    active_probes = client.receive_until_done(
        {"calva-java-version", "active-unknown-session-probe"}
    )
    active_unknown = active_probes["active-unknown-session-probe"]
    assert "unknown-session" in [
        text(status) for status in active_unknown[-1]["status"]
    ]
    java_probe = active_probes["calva-java-version"]
    assert any(text(response.get("value", b"")) == "nil" for response in java_probe)

    client.send(
        {
            "id": "interrupt-mismatch",
            "op": "interrupt",
            "session": session,
            "interrupt-id": "some-other-eval",
        }
    )
    mismatch = client.receive_until_done({"interrupt-mismatch"})[
        "interrupt-mismatch"
    ]
    assert "interrupt-id-mismatch" in [
        text(status) for status in mismatch[-1]["status"]
    ]

    client.send(
        {
            "id": "interrupt",
            "op": "interrupt",
            "session": session,
            "interrupt-id": "long-eval",
        }
    )
    interrupted = client.receive_until_done({"long-eval", "interrupt"})
    for request_id in ("long-eval", "interrupt"):
        assert "interrupted" in [
            text(status) for status in interrupted[request_id][-1]["status"]
        ]

    lost_state = client.request(
        {
            "id": "state-after-interrupt",
            "op": "eval",
            "session": session,
            "code": "adapter-value",
        }
    )
    assert "eval-error" in [
        text(status) for status in lost_state[-1]["status"]
    ]

    recovered = client.request(
        {
            "id": "recover-after-interrupt",
            "op": "eval",
            "session": session,
            "code": "(+ 1 2)",
        }
    )
    assert any(text(response.get("value", b"")) == "3" for response in recovered)

    idle_interrupt = client.request(
        {
            "id": "interrupt-idle",
            "op": "interrupt",
            "session": session,
        }
    )
    assert "session-idle" in [
        text(status) for status in idle_interrupt[-1]["status"]
    ]

    client.request({"id": "close", "op": "close", "session": session})


def wait_for_port(process: subprocess.Popen[str], port_file: Path) -> int:
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if port_file.exists() and port_file.stat().st_size:
            return int(port_file.read_text(encoding="utf-8").strip())
        if process.poll() is not None:
            stdout, stderr = process.communicate()
            raise RuntimeError(f"nREPL exited early\nstdout:\n{stdout}\nstderr:\n{stderr}")
        time.sleep(0.1)
    raise TimeoutError("nREPL server did not write its port file")


def main() -> int:
    if shutil.which("odin") is None:
        raise RuntimeError("odin is required")
    with tempfile.TemporaryDirectory(prefix="kvist-nrepl-") as temp_name:
        temp_dir = Path(temp_name)
        binary = temp_dir / ("kvist.exe" if os.name == "nt" else "kvist")
        port_file = temp_dir / "port"
        subprocess.run(
            ["odin", "build", "src/cli/kvist", f"-out:{binary}"],
            cwd=ROOT,
            check=True,
        )
        env = os.environ.copy()
        env["KVIST_ROOT"] = str(ROOT / "src" / "kvist")
        process = subprocess.Popen(
            [
                str(binary),
                "nrepl",
                "examples/language/hello.kvist",
                "--port",
                "0",
                "--port-file",
                str(port_file),
                "--once",
            ],
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        client: Client | None = None
        try:
            client = Client(wait_for_port(process, port_file))
            exercise_adapter(client)
            client.close()
            client = None
            stdout, stderr = process.communicate(timeout=30)
            if process.returncode != 0:
                raise RuntimeError(
                    f"nREPL exited with {process.returncode}\nstdout:\n{stdout}\nstderr:\n{stderr}"
                )
            if port_file.exists():
                raise AssertionError("nREPL server left its port file behind")
        finally:
            if client is not None:
                client.close()
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        print("nrepl: ok")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"failed: {error}", file=sys.stderr)
        raise
