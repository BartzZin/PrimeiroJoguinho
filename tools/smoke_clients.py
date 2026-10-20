"""Two real Godot clients against the running PostgreSQL-backed API."""

import argparse
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx
from app.main import Settings
from app.service import Service
from app.storage import database

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--visible", action="store_true")
    parser.add_argument("--executable", type=Path)
    args = parser.parse_args()
    runtime = ROOT / ".runtime"
    runtime.mkdir(exist_ok=True)
    service = Service(database(Settings().database_url))
    base = "http://127.0.0.1:8000"
    client = httpx.Client(base_url=base, timeout=10)
    client.get("/health/ready").raise_for_status()
    sessions = {}
    for side in ("white", "black"):
        response = client.post(
            "/v1/auth/invite",
            json={"invite": service.issue_invite(), "nickname": "Smoke " + side},
        )
        response.raise_for_status()
        sessions[side] = response.json()
    white_header = {"Authorization": "Bearer " + sessions["white"]["access_token"]}
    black_header = {"Authorization": "Bearer " + sessions["black"]["access_token"]}
    response = client.post("/v1/rooms", headers=white_header)
    response.raise_for_status()
    code = response.json()["code"]
    response = client.post(f"/v1/rooms/{code}/join", headers=black_header)
    response.raise_for_status()
    match_id = response.json()["match_id"]
    executable = args.executable or ROOT / ".tools/godot/Godot_v4.7.2-stable_win64_console.exe"

    def run(side):
        data = {
            "server": base,
            "session": sessions[side],
            "match_id": match_id,
            "expected_version": 1,
        }
        if side == "white":
            data["move"] = "e2e4"
        path = runtime / f"smoke-{side}.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        command = [str(executable)]
        if not args.executable:
            command += ["--path", str(ROOT / "client-godot")]
        if not args.visible:
            command += ["--headless"]
        command += ["--", f"--profile=smoke-{side}", "--smoke=" + str(path)]
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=60,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        path.unlink(missing_ok=True)  # remove short-lived session credentials, keep screenshots
        print(side, result.returncode, result.stdout, result.stderr)
        report = json.loads(Path(str(path) + ".result.json").read_text(encoding="utf-8"))
        assert result.returncode == 0 and int(report["state_version"]) >= 1
        assert "SCRIPT ERROR" not in result.stderr and "ERROR:" not in result.stderr

    with ThreadPoolExecutor(2) as executor:
        list(executor.map(run, ("white", "black")))
    view = client.get(f"/v1/matches/{match_id}", headers=black_header).json()
    assert any(p["square"] == "e4" and p["kind"] == "p" for p in view["pieces"])
    print("Two Godot clients synchronized successfully.")


if __name__ == "__main__":
    main()
