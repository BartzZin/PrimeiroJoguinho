import argparse
import json

from .main import Settings
from .service import Service
from .storage import database


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["invite", "metrics"])
    args = parser.parse_args()
    service = Service(database(Settings().database_url))
    if args.command == "invite":
        print(service.issue_invite())
    else:
        print(json.dumps(service.metrics))


if __name__ == "__main__":
    main()
