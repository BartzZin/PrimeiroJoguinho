"""Initial transactional schema: receipts independent of events."""

from alembic import op

from app.storage import metadata

revision = "001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    metadata.create_all(op.get_bind())


def downgrade():
    raise RuntimeError("Destructive downgrade disabled; restore the reviewed backup instead.")
