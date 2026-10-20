"""Manual local two-player launcher; no resident helper or Windows startup entry."""

import json
import subprocess
from pathlib import Path

import httpx
from app.main import Settings
from app.service import Service
from app.storage import database

ROOT = Path(__file__).resolve().parents[1]


def main():
    service = Service(database(Settings().database_url))
    client = httpx.Client(base_url="http://127.0.0.1:8000", timeout=10)
    client.get("/health/ready").raise_for_status()
    players = []
    for side in ("Solar", "Lunar"):
        response = client.post("/v1/auth/invite", json={"invite": service.issue_invite(), "nickname": side})
        response.raise_for_status()
        players.append(response.json())
    headers = [{"Authorization": "Bearer " + p["access_token"]} for p in players]
    response = client.post("/v1/rooms", headers=headers[0])
    response.raise_for_status()
    response = client.post("/v1/rooms/" + response.json()["code"] + "/join", headers=headers[1])
    response.raise_for_status()
    match_id = response.json()["match_id"]
    runtime = ROOT / ".runtime"
    runtime.mkdir(exist_ok=True)
    for index, session in enumerate(players):
        path = runtime / f"local-{index}.json"
        path.write_text(
            json.dumps(
                {"server": str(client.base_url).rstrip("/"), "session": session, "match_id": match_id}
            ),
            encoding="utf-8",
        )
        subprocess.Popen(
            [
                str(ROOT / ".tools/godot/Godot_v4.7.2-stable_win64.exe"),
                "--path",
                str(ROOT / "client-godot"),
                "--",
                f"--profile=local-{index}",
                "--bootstrap=" + str(path),
            ],
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    print("Duas janelas autenticadas abertas. Feche-as normalmente; tools/Stop-Dev.ps1 para os containers.")


if __name__ == "__main__":
    main()
