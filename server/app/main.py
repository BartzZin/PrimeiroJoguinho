import asyncio
import json
import logging
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager, suppress
from typing import Literal

from fastapi import Depends, FastAPI, Header, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import text

from .diagnostics import event, failure, get_logger
from .domain.game import CARDS, RuleError
from .service import TUTORIALS, Service
from .storage import database

logger = get_logger()


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    database_url: str = "postgresql+psycopg://arcano:arcano@127.0.0.1:55432/arcano"
    admin_token: str = ""


class Schema(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Redeem(Schema):
    invite: str = Field(min_length=16, max_length=128)
    nickname: str = Field(min_length=1, max_length=40, pattern=r"^[\w .-]+$")


class Refresh(Schema):
    refresh_token: str = Field(min_length=16, max_length=128)


class Command(Schema):
    type: Literal["move.request", "spell.request", "match.resign", "draw.offer", "draw.respond"]
    protocol_version: Literal[1] = 1
    request_id: str = Field(min_length=8, max_length=64, pattern=r"^[a-zA-Z0-9_-]+$")
    match_id: str
    expected_version: int = Field(ge=0)
    payload: dict = Field(default_factory=dict)


def create_app(engine=None, settings=None):
    settings = settings or Settings()
    engine = engine or database(settings.database_url)
    service = Service(engine)
    connections = defaultdict(dict)
    rate = defaultdict(deque)

    def rate_limit(key, limit=60):
        queue, now = rate[key], time.monotonic()
        while queue and queue[0] < now - 60:
            queue.popleft()
        if len(queue) >= limit:
            raise HTTPException(429, "RATE_LIMITED")
        queue.append(now)

    async def broadcast(match_id):
        for socket, account_id in list(connections[match_id].items()):
            try:
                view = await asyncio.to_thread(service.view, account_id, match_id)
                await asyncio.wait_for(socket.send_json(view), 2)
            except Exception as exc:
                failure(logger, "broadcast_failed", exc, match_id=match_id)
                connections[match_id].pop(socket, None)

    async def clock_loop():
        while True:
            try:
                changed = await asyncio.to_thread(service.expire)
                for match_id in set(changed) | set(connections):
                    if connections[match_id]:
                        await broadcast(match_id)
            except Exception as exc:
                failure(logger, "clock_loop_failed", exc)
            await asyncio.sleep(1)

    @asynccontextmanager
    async def lifespan(app):
        await asyncio.to_thread(service.void_after_restart)
        event(logger, "server_started")
        task = asyncio.create_task(clock_loop())
        yield
        task.cancel()
        with suppress(asyncio.CancelledError):
            await task
        event(logger, "server_stopped")

    app = FastAPI(title="Xadrez Arcano", version="0.1.0", lifespan=lifespan)
    app.state.service = service

    @app.exception_handler(RuleError)
    async def rule_error(request, exc):
        code = str(exc)
        status = 401 if code == "NOT_AUTHENTICATED" else 403 if code == "NOT_PARTICIPANT" else 400
        return JSONResponse({"code": code}, status_code=status)

    @app.middleware("http")
    async def limited(request: Request, call_next):
        if int(request.headers.get("content-length", "0") or 0) > 8192:
            return JSONResponse({"code": "PAYLOAD_TOO_LARGE"}, status_code=413)
        try:
            rate_limit("http:" + (request.client.host if request.client else "unknown"), 240)
        except HTTPException:
            return JSONResponse({"code": "RATE_LIMITED"}, status_code=429)
        started = time.monotonic()
        try:
            response = await call_next(request)
        except Exception as exc:
            route = getattr(request.scope.get("route"), "path", "unknown")
            failure(logger, "http_exception", exc, route=route, method=request.method)
            return JSONResponse({"code": "INTERNAL_ERROR"}, status_code=500)
        route = getattr(request.scope.get("route"), "path", "unknown")
        if not route.startswith("/health/"):
            event(
                logger, "http_completed", route=route, method=request.method,
                status=response.status_code, duration_ms=round((time.monotonic() - started) * 1000),
            )
        return response

    def actor(authorization: str = Header(default="")):
        if not authorization.startswith("Bearer "):
            raise RuleError("NOT_AUTHENTICATED")
        return service.authenticate(authorization[7:])

    @app.get("/health/live")
    def live():
        return {"status": "ok"}

    @app.get("/health/ready")
    def ready():
        with engine.connect() as db:
            db.execute(text("SELECT 1"))
        return {"status": "ready", "accepting_matches": service.accepting_matches}

    @app.post("/v1/auth/invite")
    def redeem(body: Redeem, request: Request):
        rate_limit("auth:" + request.client.host, 20)
        return service.redeem(body.invite, body.nickname)

    @app.post("/v1/auth/refresh")
    def refresh(body: Refresh):
        return service.refresh(body.refresh_token)

    @app.get("/v1/me")
    def me(account_id=Depends(actor)):
        return {"account_id": account_id}

    @app.get("/v1/cards")
    def cards():
        return [
            {"id": key, "name": val[0], "mana_cost": val[1], "text": val[2]} for key, val in CARDS.items()
        ]

    @app.post("/v1/rooms")
    def create_room(account_id=Depends(actor)):
        return service.create_room(account_id)

    @app.get("/v1/rooms/{code}")
    def room(code: str, account_id=Depends(actor)):
        return service.room(account_id, code)

    @app.post("/v1/rooms/{code}/join")
    def join(code: str, account_id=Depends(actor)):
        return service.join_room(account_id, code)

    @app.get("/v1/matches")
    def mine(account_id=Depends(actor)):
        return service.mine(account_id)

    @app.get("/v1/matches/{match_id}")
    def snapshot(match_id: str, account_id=Depends(actor)):
        return service.view(account_id, match_id)

    @app.get("/v1/matches/{match_id}/history")
    def history(match_id: str, account_id=Depends(actor)):
        return service.history(account_id, match_id)

    @app.get("/v1/tutorials")
    def lessons():
        return [
            {"id": key, "title": value["title"], "text": value["text"]} for key, value in TUTORIALS.items()
        ]

    @app.post("/v1/tutorials/{scenario}/start")
    def tutorial(scenario: str, account_id=Depends(actor)):
        return service.tutorial(account_id, scenario)

    @app.get("/admin/status")
    def admin_status(authorization: str = Header(default="")):
        require_admin(authorization)
        return {"accepting_matches": service.accepting_matches, **service.metrics}

    def require_admin(authorization):
        import secrets

        if not settings.admin_token or not secrets.compare_digest(
            authorization, "Bearer " + settings.admin_token
        ):
            raise HTTPException(403)

    @app.post("/admin/drain")
    def drain(authorization: str = Header(default="")):
        require_admin(authorization)
        service.accepting_matches = False
        return {"accepting_matches": False}

    @app.websocket("/v1/ws/match/{match_id}")
    async def match_socket(socket: WebSocket, match_id: str):
        authorization = socket.headers.get("authorization", "")
        token = authorization[7:] if authorization.startswith("Bearer ") else ""
        try:
            account_id = await asyncio.to_thread(service.authenticate, token)
            view = await asyncio.to_thread(service.view, account_id, match_id)
        except RuleError as exc:
            event(logger, "socket_rejected", level=logging.WARNING, match_id=match_id, code=str(exc))
            await socket.close(code=1008)
            return
        await socket.accept()
        event(logger, "socket_connected", match_id=match_id)
        connections[match_id][socket] = account_id
        try:
            await socket.send_json(view)
            while True:
                raw = await socket.receive_text()
                rate_limit("ws:" + account_id, 120)
                await asyncio.to_thread(service.authenticate, token)
                if len(raw.encode()) > 8192:
                    await socket.close(code=1009)
                    break
                try:
                    data = json.loads(raw)
                    if not isinstance(data, dict):
                        raise RuleError("INVALID_PAYLOAD")
                    if data.get("type") == "match.ping":
                        await socket.send_json(
                            {"type": "clock.sync", "snapshot": service.view(account_id, match_id)}
                        )
                        continue
                    command = Command.model_validate(data)
                    if command.match_id != match_id:
                        raise RuleError("NOT_PARTICIPANT")
                    response = await asyncio.to_thread(
                        service.command, account_id, match_id, command.model_dump()
                    )
                    event(
                        logger, response["type"], match_id=match_id,
                        request_id=command.request_id, kind=command.type,
                        code=response.get("code", "OK"),
                    )
                    await socket.send_json(response)
                    await broadcast(match_id)
                except (ValueError, TypeError, KeyError) as exc:
                    code = str(exc) if isinstance(exc, RuleError) else "INVALID_PAYLOAD"
                    event(logger, "command.rejected", level=logging.WARNING, match_id=match_id, code=code)
                    await socket.send_json({"type": "command.rejected", "code": code})
        except (WebSocketDisconnect, RuleError, HTTPException) as exc:
            event(logger, "socket_closed", match_id=match_id, reason=type(exc).__name__)
            with suppress(Exception):
                await socket.close(code=1008)
        except Exception as exc:
            failure(logger, "socket_exception", exc, match_id=match_id)
            with suppress(Exception):
                await socket.close(code=1011)
        finally:
            connections[match_id].pop(socket, None)

    return app


app = create_app()
