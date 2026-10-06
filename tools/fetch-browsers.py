#!/usr/bin/env python3
"""Fetch and verify the Tor Browser archive bundled in AegisOS."""
import hashlib
from fcntl import flock, LOCK_EX
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
LOCK_FILE = json.loads((ROOT / "sources/browser-lock.json").read_text())
LOCK = LOCK_FILE["tor_browser"]
ARCHIVE = ROOT / "cache/browsers" / LOCK["filename"]
SIGNATURE = ROOT / "sources/tor-browser-15.0.24.tar.xz.asc"
KEY = ROOT / "sources/tor-browser-signing-key.asc"


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def quarantine_invalid():
    if not ARCHIVE.exists():
        return
    backup = ARCHIVE.with_name(f"{ARCHIVE.name}.invalid-{time.time_ns()}")
    ARCHIVE.replace(backup)
    print(f"Preserved rejected Tor Browser download as {backup}", file=sys.stderr)


def download_archive():
    for attempt in range(6):
        args = [
            "curl", "--fail", "--location", "--connect-timeout", "20",
            "--speed-limit", "1024", "--speed-time", "120",
            "--silent", "--show-error", "--output", str(ARCHIVE), LOCK["url"],
        ]
        if ARCHIVE.exists() and ARCHIVE.stat().st_size:
            args[1:1] = ["--continue-at", "-"]
        try:
            subprocess.run(args, check=True)
            return
        except subprocess.CalledProcessError as exc:
            # Some mirrors do not honor range requests. Restart the transfer
            # if curl reports that the requested range cannot be fulfilled.
            if exc.returncode == 33:
                quarantine_invalid()
            if attempt == 5:
                raise
            time.sleep(min(16, 2 ** (attempt + 1)))


def verify_archive_signature():
    with tempfile.TemporaryDirectory(prefix="aegis-tor-gpg-") as home:
        os.chmod(home, 0o700)
        subprocess.run(["gpg", "--homedir", home, "--batch", "--import", str(KEY)], check=True, capture_output=True)
        result = subprocess.run(["gpg", "--homedir", home, "--batch", "--status-fd", "1", "--verify", str(SIGNATURE), str(ARCHIVE)], check=True, capture_output=True, text=True)
        primary = LOCK["signer"]
        if not any(line.startswith("[GNUPG:] VALIDSIG ") and line.split()[-1] == primary for line in result.stdout.splitlines()):
            raise RuntimeError("Tor Browser archive signature did not come from the pinned Tor Browser Developers key")


def main():
    key_listing = subprocess.run(["gpg", "--batch", "--show-keys", "--with-colons", str(ROOT / "sources/mullvad-keyring.asc")], check=True, capture_output=True, text=True)
    records = key_listing.stdout.splitlines()
    primary = next((records[i + 1].split(":")[9] for i, line in enumerate(records[:-1]) if line.startswith("pub:")), "")
    if primary != LOCK_FILE["mullvad_key_fingerprint"]:
        raise RuntimeError("Mullvad package signing key did not match the pinned fingerprint")
    ARCHIVE.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(ARCHIVE.with_name(f".{ARCHIVE.name}.lock"), os.O_CREAT | os.O_RDONLY, 0o644)
    try:
        flock(fd, LOCK_EX)
        if not SIGNATURE.exists():
            subprocess.run(["curl", "--fail", "--location", "--retry", "3", "--output", str(SIGNATURE), LOCK["signature_url"]], check=True)
        if ARCHIVE.exists() and digest(ARCHIVE) != LOCK["sha256"]:
            quarantine_invalid()
        if not ARCHIVE.exists():
            download_archive()
        if digest(ARCHIVE) != LOCK["sha256"]:
            quarantine_invalid()
            download_archive()
            if digest(ARCHIVE) != LOCK["sha256"]:
                quarantine_invalid()
                raise RuntimeError("Tor Browser archive SHA-256 mismatch after a clean retry")
        verify_archive_signature()
    finally:
        os.close(fd)
    print(f"Verified Tor Browser {LOCK['version']} archive and signature")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)
