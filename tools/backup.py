"""Encrypted pg_dump backups and restoration into a NEW isolated database only."""

import argparse
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from cryptography.fernet import Fernet
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]


def main():
    load_dotenv(ROOT / ".env")
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["create", "restore"])
    parser.add_argument("file", nargs="?", type=Path)
    parser.add_argument("--database", default="arcano_restore")
    args = parser.parse_args()
    key = os.environ.get("BACKUP_KEY")
    if not key:
        raise SystemExit("Configure BACKUP_KEY em .env e guarde uma cópia fora deste computador.")
    cipher = Fernet(key.encode())
    compose = ["docker", "compose", "--env-file", str(ROOT / ".env"), "-f", str(ROOT / "ops/compose.yaml")]
    if args.action == "create":
        result = subprocess.run(
            compose + ["exec", "-T", "db", "pg_dump", "-U", "arcano", "-Fc", "arcano"],
            check=True,
            capture_output=True,
        )
        destination = (
            ROOT / "backups" / (datetime.now(timezone.utc).strftime("arcano-%Y%m%dT%H%M%SZ") + ".fernet")
        )
        destination.parent.mkdir(exist_ok=True)
        destination.write_bytes(cipher.encrypt(result.stdout))
        print(destination)
    else:
        if not args.file or not re.fullmatch(r"arcano_restore[a-z0-9_]*", args.database):
            raise SystemExit(
                "Restaure somente em um banco novo arcano_restore...; banco principal é protegido."
            )
        payload = cipher.decrypt(args.file.read_bytes())
        subprocess.run(compose + ["exec", "-T", "db", "createdb", "-U", "arcano", args.database], check=True)
        subprocess.run(
            compose
            + [
                "exec",
                "-T",
                "db",
                "pg_restore",
                "-U",
                "arcano",
                "-d",
                args.database,
                "--exit-on-error",
                "--no-owner",
            ],
            input=payload,
            check=True,
        )
        print("Backup autenticado e restaurado em", args.database, "sem alterar arcano.")


if __name__ == "__main__":
    main()
