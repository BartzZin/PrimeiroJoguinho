from sqlalchemy import (
    JSON,
    BigInteger,
    CheckConstraint,
    Column,
    Float,
    ForeignKey,
    Integer,
    MetaData,
    String,
    Table,
    UniqueConstraint,
    create_engine,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.pool import StaticPool

metadata = MetaData()
document = JSON().with_variant(JSONB(), "postgresql")
accounts = Table(
    "accounts",
    metadata,
    Column("id", String(64), primary_key=True),
    Column("nickname", String(40), nullable=False),
)
invites = Table(
    "invites",
    metadata,
    Column("hash", String(64), primary_key=True),
    Column("expires", Float, nullable=False),
    Column("used_by", String(64), ForeignKey("accounts.id")),
)
sessions = Table(
    "sessions",
    metadata,
    Column("hash", String(64), primary_key=True),
    Column("account_id", String(64), ForeignKey("accounts.id")),
    Column("kind", String(12), nullable=False),
    Column("expires", Float, nullable=False),
)
matches = Table(
    "matches",
    metadata,
    Column("id", String(64), primary_key=True),
    Column("white", String(64), ForeignKey("accounts.id"), nullable=False),
    Column("black", String(64), ForeignKey("accounts.id"), nullable=False),
    Column("version", BigInteger, nullable=False),
    Column("status", String(20), nullable=False),
    Column("snapshot", document, nullable=False),
    Column("created_at", Float, nullable=False),
    CheckConstraint("white <> black"),
    CheckConstraint("version >= 0"),
)
rooms = Table(
    "rooms",
    metadata,
    Column("code", String(64), primary_key=True),
    Column("owner", String(64), ForeignKey("accounts.id")),
    Column("match_id", String(64), ForeignKey("matches.id")),
    Column("expires", Float, nullable=False),
)
events = Table(
    "match_events",
    metadata,
    Column("match_id", String(64), ForeignKey("matches.id"), primary_key=True),
    Column("seq", Integer, primary_key=True),
    Column("version", BigInteger, nullable=False),
    Column("payload", document, nullable=False),
    Column("created_at", Float, nullable=False),
)
receipts = Table(
    "command_receipts",
    metadata,
    Column("match_id", String(64), ForeignKey("matches.id"), primary_key=True),
    Column("actor", String(64), ForeignKey("accounts.id"), primary_key=True),
    Column("request_id", String(64), primary_key=True),
    Column("digest", String(64), nullable=False),
    Column("response", document, nullable=False),
    UniqueConstraint("match_id", "actor", "request_id"),
)


def database(url):
    options = {"pool_pre_ping": True}
    if url == "sqlite://":
        options.update(poolclass=StaticPool, connect_args={"check_same_thread": False})
    return create_engine(url, **options)
