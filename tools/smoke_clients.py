"""Two real Godot clients against the running PostgreSQL-backed API."""

import argparse
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx
from app.main import Settings
from app.service import Service
from app.storage import database, matches
from sqlalchemy import select, update

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--visible", action="store_true")
    parser.add_argument("--executable", type=Path)
    parser.add_argument("--show-settings", action="store_true")
    parser.add_argument("--reconnect", action="store_true")
    parser.add_argument("--spell", choices=["frost_bind", "hidden_snare"])
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
    if args.spell:
        # Seed only this freshly created test match; no public testing API or schema change.
        with service.engine.begin() as connection:
            state = connection.execute(select(matches.c.snapshot).where(matches.c.id == match_id)).scalar_one()
            state["players"]["white"]["hand"][0]["definition_id"] = args.spell
            state["players"]["white"]["mana"] = 5
            connection.execute(update(matches).where(matches.c.id == match_id).values(snapshot=state))

    executable = args.executable or ROOT / ".tools/godot/Godot_v4.7.2-stable_win64_console.exe"

    def run(side):
        data = {
            "server": base,
            "session": sessions[side],
            "match_id": match_id,
            "expected_version": 3 if args.spell else 2,
            "wait_for_version": 0 if side == "white" else (2 if args.spell else 1),
            "show_settings": args.show_settings,
            "sidebar_visible": side == "white",
            "reconnect": args.reconnect,
            "move": "e2e4" if side == "white" else "e7e5",
        }
        if args.spell and side == "white":
            data.update(spell=args.spell, spell_square="a7" if args.spell == "frost_bind" else "d4", reconnect_spell=args.reconnect)
        if args.spell == "frost_bind" and side == "black":
            data["verify_frozen_a7"] = True
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
        assert result.returncode == 0, f"{side}: Godot exited with {result.returncode}"
        report = json.loads(Path(str(path) + ".result.json").read_text(encoding="utf-8"))
        assert result.returncode == 0 and int(report["state_version"]) >= 2
        assert report["connection_state"] == "connected"
        assert report["pending_count"] == 0
        if args.spell and side == "white":
            assert report["card_resolutions"] == 1
        assert report["sidebar_visible"] == (side == "white")
        if args.spell == "frost_bind" and side == "black":
            assert report["frozen_verified"]
        if args.reconnect:
            assert report["replayed_request_id"]
        assert "SCRIPT ERROR" not in result.stderr and "ERROR:" not in result.stderr

    with ThreadPoolExecutor(2) as executor:
        list(executor.map(run, ("white", "black")))
    view = client.get(f"/v1/matches/{match_id}", headers=black_header).json()
    assert any(p["square"] == "e4" and p["kind"] == "p" for p in view["pieces"])
    assert view["state_version"] == (3 if args.spell else 2), "Reconnect must not apply a command twice"
    if args.spell == "hidden_snare":
        assert not view["revealed_traps"] and not view["my_traps"]
        own = client.get(f"/v1/matches/{match_id}", headers=white_header).json()
        assert any(trap["square"] == "d4" for trap in own["my_traps"])
    print("Two Godot clients synchronized successfully.")


if __name__ == "__main__":
    main()
