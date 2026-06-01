#!/usr/bin/env python3
import argparse
import asyncio
import json
import time
import urllib.parse


async def read_headers(reader: asyncio.StreamReader):
    status = await reader.readline()
    if not status:
        return None, {}
    headers = {}
    while True:
        line = await reader.readline()
        if not line or line in (b"\r\n", b"\n"):
            break
        text = line.decode("utf-8", "replace").strip()
        if ":" in text:
            key, value = text.split(":", 1)
            headers[key.strip().lower()] = value.strip()
    return status.decode("utf-8", "replace").strip(), headers


async def one_connection(host: str, port: int, path: str, duration: float, grace: float):
    result = {
        "connected": False,
        "status": None,
        "welcome": False,
        "ticks": 0,
        "bytes": 0,
        "error": None,
    }
    writer = None
    try:
        reader, writer = await asyncio.open_connection(host, port)
        req = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Accept: text/event-stream\r\n"
            "Cache-Control: no-cache\r\n"
            "Connection: keep-alive\r\n\r\n"
        )
        writer.write(req.encode("utf-8"))
        await writer.drain()
        result["connected"] = True

        status, _headers = await read_headers(reader)
        result["status"] = status
        deadline = time.monotonic() + duration
        saw_tick_event = False

        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            try:
                line = await asyncio.wait_for(reader.readline(), timeout=remaining + grace)
            except asyncio.TimeoutError:
                break
            if not line:
                break
            result["bytes"] += len(line)
            text = line.decode("utf-8", "replace").rstrip("\r\n")
            if text == "event: welcome":
                pass
            elif text == "data: ready":
                result["welcome"] = True
            elif text == "event: tick":
                saw_tick_event = True
            elif saw_tick_event and text.startswith("data:"):
                result["ticks"] += 1
                saw_tick_event = False
        return result
    except Exception as exc:  # noqa: BLE001
        result["error"] = repr(exc)
        return result
    finally:
        if writer is not None:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:  # noqa: BLE001
                pass


async def run(url: str, connections: int, duration: float, grace: float):
    parsed = urllib.parse.urlparse(url)
    host = parsed.hostname or "127.0.0.1"
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"

    tasks = [
        asyncio.create_task(one_connection(host, port, path, duration, grace))
        for _ in range(connections)
    ]
    results = await asyncio.gather(*tasks)
    summary = {
        "connections": connections,
        "ok_status": sum(1 for r in results if r["status"] and "200" in r["status"]),
        "connected": sum(1 for r in results if r["connected"]),
        "welcome": sum(1 for r in results if r["welcome"]),
        "tick_connections": sum(1 for r in results if r["ticks"] > 0),
        "total_ticks": sum(r["ticks"] for r in results),
        "total_bytes": sum(r["bytes"] for r in results),
        "errors": sum(1 for r in results if r["error"]),
    }
    print(json.dumps(summary))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--connections", type=int, required=True)
    parser.add_argument("--duration", type=float, default=5.0)
    parser.add_argument("--grace", type=float, default=0.5)
    args = parser.parse_args()
    asyncio.run(run(args.url, args.connections, args.duration, args.grace))


if __name__ == "__main__":
    main()
