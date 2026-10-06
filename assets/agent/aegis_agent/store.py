"""Private local task history and append-only audit records."""
import json
import os
from pathlib import Path
import sqlite3
import time


class Store:
    def __init__(self, path: str | None = None):
        self.path = Path(path or Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "aegisos" / "agent.sqlite3")
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.path.parent, 0o700)
        self.db = sqlite3.connect(self.path)
        os.chmod(self.path, 0o600)
        self.db.execute("CREATE TABLE IF NOT EXISTS tasks(id INTEGER PRIMARY KEY, created REAL, prompt TEXT, route TEXT, result TEXT)")
        self.db.execute("CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY, created REAL, event TEXT, detail TEXT)")
        self.db.commit()

    def audit(self, event: str, **detail) -> None:
        self.db.execute("INSERT INTO audit(created,event,detail) VALUES(?,?,?)", (time.time(), event, json.dumps(detail, sort_keys=True)))
        self.db.commit()

    def task(self, prompt: str, route: str, result: str) -> None:
        self.db.execute("INSERT INTO tasks(created,prompt,route,result) VALUES(?,?,?,?)", (time.time(), prompt, route, result))
        self.db.commit()

    def history(self, limit: int = 20):
        return self.db.execute("SELECT created,prompt,route,result FROM tasks ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
