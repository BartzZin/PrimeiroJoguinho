"""20 paired WebSocket matches with real PostgreSQL, no public registration bypass."""

import asyncio
import json
import os
import platform
import statistics
import time
from pathlib import Path
from uuid import uuid4

import httpx
from app.main import Settings
from app.service import Service
from app.storage import database
from websockets.asyncio.client import connect


async def until(socket, predicate):
    async with asyncio.timeout(15):
        while True:
            message = json.loads(await socket.recv())
            if predicate(message):
                return message


async def main():
    service = Service(database(Settings().database_url))
    prepared = []
    async with httpx.AsyncClient(base_url="http://127.0.0.1:8000", timeout=20) as client:
        for _ in range(20):
            tokens = [service.redeem(service.issue_invite(), "Carga")["access_token"] for _ in range(2)]
            room = await client.post("/v1/rooms", headers={"Authorization": "Bearer " + tokens[0]})
            room.raise_for_status()
            joined = await client.post(
                "/v1/rooms/" + room.json()["code"] + "/join", headers={"Authorization": "Bearer " + tokens[1]}
            )
            joined.raise_for_status()
            prepared.append((tokens, joined.json()["match_id"]))
    samples = []

    async def play(pair):
        tokens, match_id = pair
        uri = "ws://127.0.0.1:8000/v1/ws/match/" + match_id
        async with connect(uri, additional_headers={"Authorization": "Bearer " + tokens[0]}) as white:
            async with connect(uri, additional_headers={"Authorization": "Bearer " + tokens[1]}) as black:
                await until(white, lambda m: m["type"] == "match.snapshot")
                await until(black, lambda m: m["type"] == "match.snapshot")
                for version, move in enumerate(["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6"]):
                    socket = white if version % 2 == 0 else black
                    rival = black if version % 2 == 0 else white
                    request_id = str(uuid4())
                    start = time.perf_counter()
                    await socket.send(
                        json.dumps(
                            {
                                "type": "move.request",
                                "request_id": request_id,
                                "match_id": match_id,
                                "expected_version": version,
                                "payload": {"from": move[:2], "to": move[2:]},
                            }
                        )
                    )
                    result = await until(socket, lambda m: m.get("request_id") == request_id)
                    assert result["type"] == "command.accepted", result
                    await until(rival, lambda m: m.get("state_version", -1) == version + 1)
                    samples.append((time.perf_counter() - start) * 1000)
                await white.send(
                    json.dumps(
                        {
                            "type": "match.resign",
                            "request_id": str(uuid4()),
                            "match_id": match_id,
                            "expected_version": 6,
                            "payload": {},
                        }
                    )
                )
                await until(white, lambda m: m["type"] == "command.accepted")

    start = time.perf_counter()
    await asyncio.gather(*(play(pair) for pair in prepared))
    ordered = sorted(samples)
    report = {
        "matches": 20,
        "connections": 40,
        "moves": len(samples),
        "duration_seconds": round(time.perf_counter() - start, 3),
        "median_ms": round(statistics.median(samples), 2),
        "p95_ms": round(ordered[int(len(ordered) * 0.95) - 1], 2),
        "max_ms": round(max(samples), 2),
        "platform": platform.platform(),
        "logical_cpus": os.cpu_count(),
        "measurement": "Local client send to rival snapshot, includes network/DB/broadcast.",
    }
    destination = Path(__file__).resolve().parents[1] / ".runtime/load-report.json"
    destination.parent.mkdir(exist_ok=True)
    destination.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    asyncio.run(main())
