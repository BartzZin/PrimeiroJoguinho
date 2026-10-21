"""Bounded local fixtures for client connection failures; no game data is changed."""

import argparse
import asyncio
import socket
import subprocess
import threading
import time
from pathlib import Path

import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path)
    args = parser.parse_args()
    app = FastAPI()

    @app.post("/v1/auth/refresh")
    async def refresh():
        return JSONResponse({"code": "NOT_AUTHENTICATED"}, status_code=401)

    @app.websocket("/v1/ws/match/{scenario}")
    async def fixture(ws: WebSocket, scenario: str):
        if scenario == "reject":
            await ws.close(code=1008)
            return
        await ws.accept()
        try:
            while True:
                await ws.receive_text()
        except WebSocketDisconnect:
            pass

    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    port = listener.getsockname()[1]
    with socket.socket() as unused:
        unused.bind(("127.0.0.1", 0))
        refused = unused.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config(app, log_level="critical", access_log=False))
    thread = threading.Thread(target=lambda: asyncio.run(server.serve(sockets=[listener])), daemon=True)
    thread.start()
    try:
        deadline = time.monotonic() + 5
        while not server.started and time.monotonic() < deadline:
            time.sleep(0.02)
        assert server.started, "Fixture server failed to start"
        godot = (args.godot or ROOT / ".tools/godot/Godot_v4.7.2-stable_win64_console.exe").resolve()
        result = subprocess.run(
            [str(godot), "--headless", "--path", str(ROOT / "client-godot"),
             "--script", "res://tests/network.gd", "--",
             f"--fixture=http://127.0.0.1:{port}", f"--refused=http://127.0.0.1:{refused}"],
            capture_output=True, text=True, encoding="utf-8", timeout=75,
        )
        print(result.stdout, result.stderr)
        assert result.returncode == 0 and "failures=0" in result.stdout
        assert "SCRIPT ERROR" not in result.stderr
    finally:
        server.should_exit = True
        thread.join(timeout=5)
        listener.close()


if __name__ == "__main__":
    main()
