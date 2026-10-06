#!/usr/bin/env python3
"""Fetch the Parrot ISO only after checking its signed release manifest."""

from hashlib import sha256
from fcntl import flock, LOCK_EX
from pathlib import Path
from tempfile import TemporaryDirectory
import json
import os
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
LOCK = json.loads((ROOT / "sources/parrot.json").read_text())
DEST = ROOT / "cache/parrot" / LOCK["filename"]


def checked_manifest():
    with TemporaryDirectory(prefix="aegisos-gpg-") as home:
        os.chmod(home, 0o700)
        key = ROOT / "sources" / LOCK["key"]
        manifest = ROOT / "sources" / LOCK["hashes"]
        subprocess.run(["gpg", "--homedir", home, "--batch", "--quiet", "--import", str(key)], check=True)
        result = subprocess.run(
            ["gpg", "--homedir", home, "--batch", "--status-fd", "1", "--verify", str(manifest)],
            check=True, capture_output=True, text=True,
        )
        if f"[GNUPG:] VALIDSIG {LOCK['signer']} " not in result.stdout:
            raise RuntimeError("Parrot manifest signer did not match the pinned fingerprint")
        entry = f"{LOCK['sha256']}  {LOCK['filename']}"
        if entry not in manifest.read_text().splitlines():
            raise RuntimeError("Pinned image SHA-256 is absent from the signed manifest")


def digest(path):
    value = sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def quarantine_invalid():
    if not DEST.exists():
        return
    backup = DEST.with_name(f"{DEST.name}.invalid-{int(time.time())}")
    while backup.exists():
        backup = DEST.with_name(f"{DEST.name}.invalid-{int(time.time() * 1000)}")
    DEST.replace(backup)
    print(f"Preserved rejected download as {backup}", file=sys.stderr)


def download(resume):
    continuing = resume and DEST.exists()
    for attempt in range(10):
        args = [
            "curl", "--fail", "--location", "--connect-timeout", "20",
            "--speed-limit", "1024", "--speed-time", "120",
            "--silent", "--show-error", "--output", str(DEST), LOCK["url"],
        ]
        if continuing and DEST.exists():
            args[1:1] = ["--continue-at", "-"]
        try:
            subprocess.run(args, check=True)
            return
        except subprocess.CalledProcessError:
            continuing = DEST.exists() and DEST.stat().st_size > 0
            if attempt == 9:
                raise
            time.sleep(min(30, 2 ** (attempt + 1)))


def main():
    DEST.parent.mkdir(parents=True, exist_ok=True)
    lock_path = DEST.with_name(f".{DEST.name}.lock")
    fd = os.open(lock_path, os.O_CREAT | os.O_RDONLY, 0o644)
    try:
        flock(fd, LOCK_EX)
        checked_manifest()
        if DEST.exists() and DEST.stat().st_size == LOCK["size_bytes"]:
            if digest(DEST) == LOCK["sha256"]:
                print(f"Verified cached Parrot ISO: {DEST}")
                return
            quarantine_invalid()
        elif DEST.exists() and DEST.stat().st_size > LOCK["size_bytes"]:
            quarantine_invalid()

        download(resume=DEST.exists())
        if DEST.stat().st_size != LOCK["size_bytes"] or digest(DEST) != LOCK["sha256"]:
            quarantine_invalid()
            download(resume=False)
            if DEST.stat().st_size != LOCK["size_bytes"] or digest(DEST) != LOCK["sha256"]:
                quarantine_invalid()
                raise RuntimeError("Parrot ISO size or SHA-256 did not match the signed manifest after a clean retry")
        print(f"Signature and full ISO SHA-256 verified: {DEST}")
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)
