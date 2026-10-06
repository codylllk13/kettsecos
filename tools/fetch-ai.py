#!/usr/bin/env python3
"""Fetch the pinned KettsecOS AI payloads into the ignored build cache.

Every artifact is downloaded to a temporary sibling and promoted only after
its locked size and digest match. Partial transfers remain resumable, while a
rejected payload is retained with an ``.invalid-*`` suffix for diagnosis.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parent.parent
LOCK = json.loads((ROOT / "sources/ai-lock.json").read_text())
CACHE = ROOT / "cache/ai"


def digest(path: Path, algorithm: str = "sha256") -> str:
    hasher = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def reject(path: Path) -> None:
    if path.exists():
        target = path.with_name(f"{path.name}.invalid-{time.time_ns()}")
        path.replace(target)
        print(f"Preserved rejected AI payload as {target}")


def download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    args = [
        "curl", "--fail", "--location", "--connect-timeout", "20",
        "--speed-limit", "1024", "--speed-time", "120", "--retry", "3",
        "--silent", "--show-error", "--continue-at", "-",
        "--output", str(destination), url,
    ]
    subprocess.run(args, check=True)


def download_large(url: str, destination: Path, size: int) -> None:
    """Download a large immutable blob with resumable parallel byte ranges."""
    parts_dir = destination.parent / (destination.name + ".parts")
    parts_dir.mkdir(parents=True, exist_ok=True)
    chunk = 256 * 1024 * 1024
    ranges = [(start, min(size - 1, start + chunk - 1)) for start in range(0, size, chunk)]

    def fetch_range(bounds: tuple[int, int]) -> None:
        start, end = bounds
        part = parts_dir / f"{start:016x}-{end:016x}"
        expected = end - start + 1
        if part.exists() and part.stat().st_size == expected:
            return
        current = part.stat().st_size if part.exists() else 0
        if current > expected:
            reject(part)
            current = 0
        request_start = start + current
        destination = part if current == 0 else part.with_name(part.name + ".resume")
        subprocess.run([
            "curl", "--fail", "--location", "--connect-timeout", "20",
            "--speed-limit", "1024", "--speed-time", "120", "--retry", "5",
            "--silent", "--show-error", "-H", f"Range: bytes={request_start}-{end}",
            "--output", str(destination), url,
        ], check=True)
        if current:
            with part.open("ab") as output, destination.open("rb") as resume:
                shutil.copyfileobj(resume, output, 8 * 1024 * 1024)
            destination.unlink()
        if part.stat().st_size != expected:
            reject(part)
            raise RuntimeError(f"range {start}-{end} returned an unexpected size")

    with ThreadPoolExecutor(max_workers=32) as executor:
        list(executor.map(fetch_range, ranges))
    with destination.open("wb") as output:
        for start, end in ranges:
            part = parts_dir / f"{start:016x}-{end:016x}"
            with part.open("rb") as source:
                shutil.copyfileobj(source, output, 8 * 1024 * 1024)
    for part in parts_dir.iterdir():
        part.unlink()
    parts_dir.rmdir()


def verify_or_fetch(name: str, spec: dict, algorithm: str, expected: str) -> Path:
    destination = CACHE / spec["filename"]
    if destination.exists():
        valid = destination.stat().st_size == spec.get("size", destination.stat().st_size)
        valid = valid and digest(destination, algorithm) == expected
        if valid:
            return destination
        reject(destination)
    partial = destination.with_suffix(destination.suffix + ".part")
    if partial.exists() and partial.stat().st_size == spec.get("size", -1):
        reject(partial)
    download(spec["url"], partial)
    if "size" in spec and partial.stat().st_size != spec["size"]:
        reject(partial)
        raise RuntimeError(f"{name} size mismatch")
    if digest(partial, algorithm) != expected:
        reject(partial)
        raise RuntimeError(f"{name} {algorithm} mismatch")
    partial.replace(destination)
    return destination


def fetch_model() -> tuple[Path, dict]:
    spec = LOCK["model"]
    response = subprocess.run(
        ["curl", "--fail", "--location", "--silent", "--show-error", spec["manifest_url"]],
        check=True, capture_output=True,
    ).stdout
    if hashlib.sha256(response).hexdigest() != spec["manifest_sha256"]:
        raise RuntimeError("locked Ollama manifest changed upstream")
    manifest = json.loads(response)
    layers = {item["digest"]: item for item in spec["layers"]}
    descriptors = manifest.get("layers", []) + [manifest.get("config", {})]
    if {item.get("digest") for item in descriptors} != set(layers):
        raise RuntimeError("Ollama manifest layer set changed upstream")
    model_cache = CACHE / "model"
    model_cache.mkdir(parents=True, exist_ok=True)
    for descriptor in manifest.get("layers", []) + [manifest.get("config", {})]:
        digest_name = descriptor.get("digest")
        if digest_name not in layers:
            raise RuntimeError(f"unexpected Ollama model layer: {digest_name}")
        expected_size = layers[digest_name]["size"]
        if descriptor.get("size") != expected_size:
            raise RuntimeError(f"unexpected size for Ollama layer {digest_name}")
        target = model_cache / ("sha256-" + digest_name.split(":", 1)[1])
        if not target.exists() or target.stat().st_size != expected_size or digest(target) != digest_name.split(":", 1)[1]:
            if target.exists(): reject(target)
            partial = target.with_name(target.name + ".part")
            if partial.exists():
                reject(partial)
            download_large(
                f"https://{spec['registry']}/v2/{spec['namespace']}/{spec['name']}/blobs/{digest_name}",
                partial, expected_size,
            )
            if partial.stat().st_size != expected_size or digest(partial) != digest_name.split(":", 1)[1]:
                reject(partial)
                raise RuntimeError(f"Ollama layer verification failed: {digest_name}")
            partial.replace(target)
    manifest_path = model_cache / "manifest.json"
    manifest_path.write_bytes(response)
    return model_cache, manifest


def main() -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    verify_or_fetch("Codex CLI", LOCK["codex"], "sha512", base64.b64decode(LOCK["codex"]["sha512_sri"].split("-", 1)[1]).hex())
    verify_or_fetch("ChatGPT", LOCK["chatgpt"], "sha256", LOCK["chatgpt"]["sha256"])
    verify_or_fetch("Ollama", LOCK["ollama"], "sha256", LOCK["ollama"]["sha256"])
    fetch_model()
    print("Verified Codex, ChatGPT, Ollama, and Huihui Qwen3.5 9B model payloads")


if __name__ == "__main__":
    main()
