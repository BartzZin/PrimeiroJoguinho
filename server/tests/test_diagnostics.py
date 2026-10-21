import io
import json
import logging

from fastapi.testclient import TestClient

from app.diagnostics import OperationalFormatter, failure, get_logger
from app.main import Settings, create_app
from app.storage import database, metadata


def test_exception_logs_keep_source_without_exception_text_or_payload():
    logger = get_logger()
    stream = io.StringIO()
    capture = logging.StreamHandler(stream)
    capture.setFormatter(OperationalFormatter())
    logger.addHandler(capture)
    try:
        try:
            raise RuntimeError("PRIVATE_ACCESS_TOKEN_AND_HAND")
        except RuntimeError as exc:
            failure(logger, "test_failure", exc, payload="PRIVATE_TRAP", password="PRIVATE_PASSWORD")
    finally:
        logger.removeHandler(capture)
    text = stream.getvalue()
    entry = json.loads(text)
    assert entry["exception_type"] == "RuntimeError"
    assert entry["frames"][0]["file"] == "test_diagnostics.py"
    assert "PRIVATE_" not in text


def test_http_and_socket_logs_exclude_credentials_and_private_state(tmp_path):
    engine = database(f"sqlite:///{tmp_path / 'diagnostics.db'}")
    assert engine.hide_parameters
    metadata.create_all(engine)
    app = create_app(engine, Settings(database_url="sqlite://"))
    logger = get_logger()
    stream = io.StringIO()
    capture = logging.StreamHandler(stream)
    capture.setFormatter(OperationalFormatter())
    logger.addHandler(capture)
    try:
        with TestClient(app) as client:
            service = app.state.service
            invite = service.issue_invite()
            white = client.post("/v1/auth/invite", json={"invite": invite, "nickname": "White"}).json()
            black = service.redeem(service.issue_invite(), "Black")
            room = service.create_room(white["account_id"])
            match_id = service.join_room(black["account_id"], room["code"])["match_id"]
            headers = {"Authorization": "Bearer " + white["access_token"]}
            with client.websocket_connect(f"/v1/ws/match/{match_id}", headers=headers) as ws:
                ws.receive_json()
                ws.send_json({"type": "INVALID", "payload": {"PRIVATE_HAND": "PRIVATE_TRAP"}})
                response = ws.receive_json()
                while response["type"] != "command.rejected":
                    response = ws.receive_json()
                assert response["code"] == "INVALID_PAYLOAD"

            def fail_mine(_account):
                raise RuntimeError("PRIVATE_DATABASE_PASSWORD")

            service.mine = fail_mine
            assert client.get("/v1/matches", headers=headers).status_code == 500
    finally:
        logger.removeHandler(capture)
    text = stream.getvalue()
    for secret in (invite, white["access_token"], white["refresh_token"], room["code"], "PRIVATE_"):
        assert secret not in text
    entries = [json.loads(line) for line in text.splitlines()]
    assert {"socket_connected", "command.rejected", "http_exception"} <= {e["event"] for e in entries}
