CREATE TABLE accounts (
	id VARCHAR(64) NOT NULL,
	nickname VARCHAR(40) NOT NULL,
	PRIMARY KEY (id)
);

CREATE TABLE invites (
	hash VARCHAR(64) NOT NULL,
	expires FLOAT NOT NULL,
	used_by VARCHAR(64),
	PRIMARY KEY (hash),
	FOREIGN KEY(used_by) REFERENCES accounts (id)
);

CREATE TABLE matches (
	id VARCHAR(64) NOT NULL,
	white VARCHAR(64) NOT NULL,
	black VARCHAR(64) NOT NULL,
	version BIGINT NOT NULL,
	status VARCHAR(20) NOT NULL,
	snapshot JSONB NOT NULL,
	created_at FLOAT NOT NULL,
	PRIMARY KEY (id),
	CHECK (white <> black),
	CHECK (version >= 0),
	FOREIGN KEY(white) REFERENCES accounts (id),
	FOREIGN KEY(black) REFERENCES accounts (id)
);

CREATE TABLE sessions (
	hash VARCHAR(64) NOT NULL,
	account_id VARCHAR(64),
	kind VARCHAR(12) NOT NULL,
	expires FLOAT NOT NULL,
	PRIMARY KEY (hash),
	FOREIGN KEY(account_id) REFERENCES accounts (id)
);

CREATE TABLE command_receipts (
	match_id VARCHAR(64) NOT NULL,
	actor VARCHAR(64) NOT NULL,
	request_id VARCHAR(64) NOT NULL,
	digest VARCHAR(64) NOT NULL,
	response JSONB NOT NULL,
	PRIMARY KEY (match_id, actor, request_id),
	UNIQUE (match_id, actor, request_id),
	FOREIGN KEY(match_id) REFERENCES matches (id),
	FOREIGN KEY(actor) REFERENCES accounts (id)
);

CREATE TABLE match_events (
	match_id VARCHAR(64) NOT NULL,
	seq INTEGER NOT NULL,
	version BIGINT NOT NULL,
	payload JSONB NOT NULL,
	created_at FLOAT NOT NULL,
	PRIMARY KEY (match_id, seq),
	FOREIGN KEY(match_id) REFERENCES matches (id)
);

CREATE TABLE rooms (
	code VARCHAR(64) NOT NULL,
	owner VARCHAR(64),
	match_id VARCHAR(64),
	expires FLOAT NOT NULL,
	PRIMARY KEY (code),
	FOREIGN KEY(owner) REFERENCES accounts (id),
	FOREIGN KEY(match_id) REFERENCES matches (id)
);
