"""Operational JSON logs with explicit fields; exception messages may contain secrets."""

import json
import logging
import sys
import traceback
from datetime import UTC, datetime
from pathlib import Path

FIELDS = {
    "route", "method", "status", "duration_ms", "match_id", "request_id", "kind",
    "code", "reason", "exception_type", "frames",
}


class OperationalFormatter(logging.Formatter):
    def format(self, record):
        entry = {
            "time": datetime.fromtimestamp(record.created, UTC).isoformat(),
            "level": record.levelname,
            "event": record.msg,
        }
        entry.update({k: v for k, v in getattr(record, "diagnostic_fields", {}).items() if k in FIELDS})
        return json.dumps(entry, ensure_ascii=False)


def get_logger():
    logger = logging.getLogger("arcano")
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(OperationalFormatter())
        logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    return logger


def event(logger, name, *, level=logging.INFO, **fields):
    logger.log(level, name, extra={"diagnostic_fields": fields})


def failure(logger, name, exc, **fields):
    # Capture source locations, never exception text, SQL bindings, or frame locals.
    event(
        logger, name, level=logging.ERROR, exception_type=type(exc).__name__,
        frames=[{"file": Path(f.filename).name, "function": f.name, "line": f.lineno}
                for f in traceback.extract_tb(exc.__traceback__)], **fields,
    )
