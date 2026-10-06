"""ChatGPT plan usage; caller must disclose payload and obtain task-specific consent."""
import json
import requests


def chatgpt_task(prompt: str, disclose_and_approve) -> str:
    """Send the prompt only after the caller confirms the exact local data."""
    if not disclose_and_approve(prompt):
        raise PermissionError("Cloud upload was not approved; use a local or LAN model")
    from .auth import get_tokens, refresh_tokens
    tokens = get_tokens()
    if not tokens or not tokens.get("access_token"):
        raise RuntimeError("Sign in with ChatGPT before requesting cloud routing")
    headers = {"Authorization": "Bearer " + tokens["access_token"], "Content-Type": "application/json"}
    models_response = requests.get("https://api.openai.com/v1/models", headers=headers, timeout=30)
    if models_response.status_code == 401:
        tokens = refresh_tokens(tokens)
        headers["Authorization"] = "Bearer " + tokens["access_token"]
        models_response = requests.get("https://api.openai.com/v1/models", headers=headers, timeout=30)
    models_response.raise_for_status()
    available = [item["slug"] for item in models_response.json().get("models", []) if item.get("visibility") == "list" and item.get("slug")]
    if not available:
        raise RuntimeError("No ChatGPT plan models are available for this account")
    payload = {"model": available[0], "input": prompt, "stream": True, "store": False}
    response = requests.post("https://api.openai.com/v1/responses", headers=headers, json=payload, timeout=180, stream=True)
    if response.status_code == 401:
        tokens = refresh_tokens(tokens)
        headers["Authorization"] = "Bearer " + tokens["access_token"]
        response = requests.post("https://api.openai.com/v1/responses", headers=headers, json=payload, timeout=180, stream=True)
    response.raise_for_status()
    text, completed = [], False
    for line in response.iter_lines(decode_unicode=True):
        if not line or not line.startswith("data: ") or line == "data: [DONE]": continue
        event = json.loads(line[6:])
        if event.get("type") == "response.output_text.delta": text.append(event.get("delta", ""))
        elif event.get("type") == "response.completed": completed = True
        elif event.get("type") in {"response.failed", "error"}:
            raise RuntimeError("ChatGPT plan inference failed")
    if not completed:
        raise RuntimeError("ChatGPT stream ended before completion")
    return "".join(text)
