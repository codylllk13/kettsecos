"""Private-by-default local model routing; cloud is never contacted implicitly."""
import json
import os
import requests


def route_task(prompt: str, cloud_signed_in=False) -> str:
    low = prompt.lower()
    if cloud_signed_in and len(prompt) > 1200 and any(w in low for w in ("analyze", "plan", "explain", "review")):
        return "chatgpt"
    # A LAN model is opt-in through the loopback SSH tunnel. Never send a task
    # to an absent endpoint just because it contains a security keyword.
    if os.environ.get("AEGIS_LAN_URL") and any(w in low for w in ("scan", "nmap", "security", "pentest", "audit")):
        return "lan"
    return "local"


def local_chat(prompt: str, model=None, base_url=None, structured=False) -> str:
    endpoint = (base_url or os.environ.get("AEGIS_OLLAMA_URL", "http://127.0.0.1:11434")).rstrip("/") + "/api/chat"
    model = model or os.environ.get("AEGIS_LOCAL_MODEL", "huihui_ai/qwen3.5-abliterated:9b")
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
        "options": {"temperature": 0},
    }
    if structured:
        payload["format"] = "json"
    response = requests.post(endpoint, json=payload, timeout=300)
    response.raise_for_status()
    return response.json()["message"]["content"]


def lan_chat(prompt: str, base_url=None, structured=False) -> str:
    """Use configured OpenAI-compatible endpoint, expected to be an SSH tunnel."""
    endpoint = (base_url or os.environ.get("AEGIS_LAN_URL", "http://127.0.0.1:8080/v1")).rstrip("/") + "/chat/completions"
    payload = {
        "model": os.environ.get("AEGIS_LAN_MODEL", "lfm2.5-8b"),
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
        "temperature": 0,
    }
    if structured:
        payload["response_format"] = {"type": "json_object"}
    response = requests.post(endpoint, json=payload, timeout=300)
    response.raise_for_status()
    return response.json()["choices"][0]["message"]["content"]


def local_status(base_url=None) -> dict:
    """Return truthful loopback model readiness without contacting the cloud."""
    endpoint = (base_url or os.environ.get("AEGIS_OLLAMA_URL", "http://127.0.0.1:11434")).rstrip("/") + "/api/tags"
    model = os.environ.get("AEGIS_LOCAL_MODEL", "huihui_ai/qwen3.5-abliterated:9b")
    try:
        response = requests.get(endpoint, timeout=3)
        response.raise_for_status()
        names = {item.get("name") for item in response.json().get("models", [])}
        return {"available": model in names, "model": model, "endpoint": endpoint}
    except (OSError, requests.RequestException, ValueError):
        return {"available": False, "model": model, "endpoint": endpoint}
