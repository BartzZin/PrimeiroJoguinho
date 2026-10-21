"""Manual two-player launcher with unique bootstrap files and bounded diagnostics."""

import argparse
import json
import logging
import subprocess
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path
from uuid import uuid4

import httpx
from app.diagnostics import OperationalFormatter, event, failure
from app.main import Settings
from app.service import Service
from app.storage import database

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke-test", action="store_true")
    args = parser.parse_args()
    runtime = ROOT / ".runtime"
    logs = runtime / "logs"
    runtime.mkdir(parents=True, exist_ok=True)
    run_id = uuid4().hex
    log_path = logs / f"local-{run_id}.log"
    logger = logging.getLogger("local-launcher")
    log_available = True
    try:
        logs.mkdir(parents=True, exist_ok=True)
        handler = RotatingFileHandler(log_path, maxBytes=2 * 1024 * 1024, backupCount=2, encoding="utf-8")
    except OSError:
        handler = logging.NullHandler()
        log_available = False
    handler.setFormatter(OperationalFormatter())
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    processes, paths = [], []
    try:
        godot = ROOT / ".tools/godot/Godot_v4.7.2-stable_win64.exe"
        if not godot.is_file():
            raise RuntimeError("GODOT_NOT_INSTALLED")
        event(logger, "launcher_started")
        service = Service(database(Settings().database_url))
        with httpx.Client(base_url="http://127.0.0.1:8000", timeout=10) as client:
            ready = client.get("/health/ready")
            ready.raise_for_status()
            if not ready.json().get("accepting_matches"):
                raise RuntimeError("SERVER_MAINTENANCE")
            players = []
            for side in ("Solar", "Lunar"):
                response = client.post(
                    "/v1/auth/invite", json={"invite": service.issue_invite(), "nickname": side}
                )
                response.raise_for_status()
                players.append(response.json())
            headers = [{"Authorization": "Bearer " + p["access_token"]} for p in players]
            response = client.post("/v1/rooms", headers=headers[0])
            response.raise_for_status()
            response = client.post(
                "/v1/rooms/" + response.json()["code"] + "/join", headers=headers[1]
            )
            response.raise_for_status()
            match_id = response.json()["match_id"]
        event(logger, "match_created", match_id=match_id)
        for index, session in enumerate(players):
            path = runtime / f"local-{run_id}-{index}.json"
            paths.append(path)
            data = {"server": "http://127.0.0.1:8000", "session": session, "match_id": match_id}
            if args.smoke_test:
                data.update(
                    move="e2e4" if index == 0 else "e7e5",
                    wait_for_version=index, expected_version=2,
                )
            path.write_text(json.dumps(data), encoding="utf-8")
            profile = f"launcher-smoke-{index}" if args.smoke_test else f"local-{index}"
            command = [str(godot), "--path", str(ROOT / "client-godot")]
            if log_available:
                command += ["--log-file", str(logs / f"godot-{run_id}-{index}.log")]
            processes.append(subprocess.Popen(
                [*command, "--",
                 f"--profile={profile}", f"--{'smoke' if args.smoke_test else 'bootstrap'}={path}"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            ))
        deadline = time.monotonic() + 30
        while any(path.exists() for path in paths):
            if any(p.poll() is not None for p in processes):
                raise RuntimeError("CLIENT_EXITED_DURING_STARTUP")
            if time.monotonic() >= deadline:
                raise RuntimeError("CLIENT_STARTUP_TIMEOUT")
            time.sleep(0.1)
        event(logger, "bootstrap_consumed")
        if args.smoke_test:
            for process, path in zip(processes, paths, strict=True):
                code = process.wait(timeout=60)
                report = json.loads(Path(str(path) + ".result.json").read_text(encoding="utf-8"))
                if code or report["state_version"] < 2 or report["connection_state"] != "connected":
                    raise RuntimeError("CLIENT_SMOKE_FAILED")
            print("Jogar.cmd: dois clientes conectados e dois movimentos por clique confirmados.")
        else:
            print("Duas janelas abertas. Na engrenagem, ative os logs detalhados se necessario.")
        event(logger, "launcher_completed")
        print(f"Log da partida local: {log_path}" if log_available else "Registro do iniciador indisponivel; use os logs no menu do jogo.")
        return 0
    except Exception as exc:
        failure(logger, "launcher_failed", exc)
        for process in processes:
            if process.poll() is None:
                process.terminate()
        for path in paths:
            path.unlink(missing_ok=True)
        print(f"Falha na abertura ({type(exc).__name__}). Consulte: {log_path}" if log_available else f"Falha na abertura ({type(exc).__name__}); pasta de logs indisponivel.")
        return 1
    finally:
        logger.removeHandler(handler)
        handler.close()


if __name__ == "__main__":
    raise SystemExit(main())
