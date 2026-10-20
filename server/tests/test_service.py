import os
import threading
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.domain.game import RuleError
from app.main import Settings, create_app
from app.service import Service
from app.storage import database, events, metadata


@pytest.fixture
def service(tmp_path):
    engine = database(f"sqlite:///{tmp_path / 'test.db'}")
    metadata.create_all(engine)
    return Service(engine)


def pair(service):
    white = service.redeem(service.issue_invite(), "White")
    black = service.redeem(service.issue_invite(), "Black")
    room = service.create_room(white["account_id"])
    match_id = service.join_room(black["account_id"], room["code"])["match_id"]
    return white, black, match_id


def command(match_id, version=0, move="e2e4", request_id=None):
    return {
        "type": "move.request",
        "request_id": request_id or str(uuid4()),
        "match_id": match_id,
        "expected_version": version,
        "payload": {"from": move[:2], "to": move[2:4]},
    }


def test_idempotency_stale_version_and_authorization(service):
    white, black, match_id = pair(service)
    request = command(match_id)
    accepted = service.command(white["account_id"], match_id, request)
    assert accepted["type"] == "command.accepted"
    assert service.command(white["account_id"], match_id, request) == accepted
    with pytest.raises(RuleError, match="REQUEST_ID_REUSED"):
        service.command(white["account_id"], match_id, {**request, "payload": {"from": "d2", "to": "d4"}})
    assert (
        service.command(black["account_id"], match_id, command(match_id, 0, "e7e5"))["code"]
        == "STALE_VERSION"
    )
    with pytest.raises(RuleError, match="NOT_PARTICIPANT"):
        service.view("forged", match_id)


def test_invalid_move_never_changes_board(service):
    white, _, match_id = pair(service)
    before = service.view(white["account_id"], match_id)
    assert (
        service.command(white["account_id"], match_id, command(match_id, move="e2e5"))["code"]
        == "INVALID_MOVE"
    )
    after = service.view(white["account_id"], match_id)
    assert before["pieces"] == after["pieces"] and after["state_version"] == 0


def test_restart_voids_once_and_preserves_history(service):
    white, _, match_id = pair(service)
    service.command(white["account_id"], match_id, command(match_id))
    service.void_after_restart()
    history = service.history(white["account_id"], match_id)
    assert service.view(white["account_id"], match_id)["result_reason"] == "server_failure"
    service.void_after_restart()
    assert service.history(white["account_id"], match_id) == history


def test_timeout_without_client_command(service):
    white, _, match_id = pair(service)
    service.stamps[match_id] -= 601
    assert service.expire() == [match_id]
    assert service.expire() == []
    assert service.view(white["account_id"], match_id)["winner"] == "black"


def test_invite_single_use_and_refresh_rotation(service):
    invite = service.issue_invite()
    session = service.redeem(invite, "Player")
    with pytest.raises(RuleError):
        service.redeem(invite, "Duplicate")
    fresh = service.refresh(session["refresh_token"])
    assert service.authenticate(fresh["access_token"]) == session["account_id"]
    with pytest.raises(RuleError):
        service.refresh(session["refresh_token"])


def test_draw_response_is_allowed_outside_own_turn(service):
    white, black, match_id = pair(service)
    offer = {**command(match_id), "type": "draw.offer", "payload": {}}
    service.command(white["account_id"], match_id, offer)
    response = {**command(match_id, 1), "type": "draw.respond", "payload": {"accept": True}}
    assert service.command(black["account_id"], match_id, response)["type"] == "command.accepted"
    assert service.view(white["account_id"], match_id)["result_reason"] == "agreement"


def test_real_websocket_two_clients_and_reconnect(service):
    white, black, match_id = pair(service)
    app = create_app(service.engine, Settings(database_url="sqlite://"))
    with TestClient(app) as client:
        # Startup intentionally voids old games: create a new match after startup.
        white, black, match_id = pair(app.state.service)
        wh = {"Authorization": "Bearer " + white["access_token"]}
        bh = {"Authorization": "Bearer " + black["access_token"]}
        with client.websocket_connect(f"/v1/ws/match/{match_id}", headers=wh) as ws1:
            assert ws1.receive_json()["viewer_side"] == "white"
            with client.websocket_connect(f"/v1/ws/match/{match_id}", headers=bh) as ws2:
                assert ws2.receive_json()["viewer_side"] == "black"
                ws1.send_json(command(match_id))
                result = ws1.receive_json()
                while result["type"] != "command.accepted":
                    result = ws1.receive_json()
                view = ws2.receive_json()
                while view["state_version"] < 1:
                    view = ws2.receive_json()
                assert any(p["square"] == "e4" for p in view["pieces"])
        with client.websocket_connect(f"/v1/ws/match/{match_id}", headers=wh) as ws:
            assert ws.receive_json()["state_version"] == 1
        assert client.get(f"/v1/matches/{match_id}").status_code == 401


@pytest.mark.skipif(
    not os.getenv("TEST_DATABASE_URL"), reason="requires isolated PostgreSQL TEST_DATABASE_URL"
)
def test_postgresql_concurrent_commands():
    engine = database(os.environ["TEST_DATABASE_URL"])
    metadata.create_all(engine)
    service = Service(engine)
    white, _, match_id = pair(service)
    barrier = threading.Barrier(2)

    def run(move):
        writer = Service(engine)
        writer.stamps[match_id] = service.stamps[match_id]
        barrier.wait()
        return writer.command(white["account_id"], match_id, command(match_id, move=move))

    with ThreadPoolExecutor(2) as executor:
        outcomes = list(executor.map(run, ["e2e4", "d2d4"]))
    assert sum(r["type"] == "command.accepted" for r in outcomes) == 1
    assert service.view(white["account_id"], match_id)["state_version"] == 1
    with engine.connect() as db:
        assert len(db.execute(select(events).where(events.c.match_id == match_id)).all()) == 1
