"""OpenAI Sign in with ChatGPT (SIWC) OAuth using PKCE and local keyring storage."""
import base64
import hashlib
import json
import secrets
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import os
import uuid

import jwt
import requests
import keyring
from keyring.errors import PasswordDeleteError

ISSUER = "https://auth.openai.com"
RESOURCE = "https://api.openai.com/v1"
SCOPES = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
SERVICE = "aegisos-chatgpt"


def _b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _host_id():
    path = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "aegisos" / "host-id"
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        return path.read_text().strip()
    except FileNotFoundError:
        value = "urn:uuid:" + str(uuid.uuid4())
        path.write_text(value + "\n")
        os.chmod(path, 0o600)
        return value


def login():
    """Run interactive localhost authorization; returns the signed-in account label."""
    meta = requests.get(ISSUER + "/.well-known/openid-configuration", timeout=15)
    meta.raise_for_status()
    oidc = meta.json()
    verifier = _b64(secrets.token_bytes(48))
    challenge = _b64(hashlib.sha256(verifier.encode()).digest())
    state, nonce = secrets.token_urlsafe(24), secrets.token_urlsafe(24)
    result = {}
    saved = json.loads(keyring.get_password(SERVICE, "oidc") or "{}")
    prior_tokens = get_tokens()
    client_id = saved.get("client_id") or "dynamic_agent_client"

    class Callback(BaseHTTPRequestHandler):
        def do_GET(self):
            if urllib.parse.urlparse(self.path).path != "/auth/callback":
                self.send_error(404)
                return
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            result.update({key: values[0] for key, values in query.items() if values})
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"<p>AegisOS ChatGPT sign-in complete. You may close this tab.</p>")

        def log_message(self, *_):
            return

    server = HTTPServer(("127.0.0.1", 0), Callback)
    server.timeout = 180
    redirect = f"http://127.0.0.1:{server.server_port}/auth/callback"
    params = {
        "client_id": client_id, "redirect_uri": redirect,
        "response_type": "code", "scope": SCOPES, "state": state,
        "nonce": nonce, "code_challenge": challenge, "code_challenge_method": "S256",
        "resource": RESOURCE,
        "ext_agent_host_id": _host_id(),
    }
    if client_id == "dynamic_agent_client":
        params["agent_name_hint"] = "AegisOS Security Assistant"
    else:
        if prior_tokens and prior_tokens.get("id_token"):
            params["id_token_hint"] = prior_tokens["id_token"]
        if saved.get("label"):
            params["login_hint"] = saved["label"]
    webbrowser.open(ISSUER + "/api/accounts/authorize?" + urllib.parse.urlencode(params))
    server.handle_request()
    server.server_close()
    if result.get("state") != state:
        raise RuntimeError("ChatGPT sign-in state validation failed")
    if result.get("error") or "code" not in result:
        raise RuntimeError("ChatGPT sign-in was not completed")
    returned_client_id = result.get("client_id")
    if client_id == "dynamic_agent_client" and not returned_client_id:
        raise RuntimeError("ChatGPT did not return its registered client ID")
    if client_id != "dynamic_agent_client" and returned_client_id and returned_client_id != client_id:
        raise RuntimeError("ChatGPT returned a different registered client ID")
    client_id = returned_client_id or client_id
    if not client_id:
        raise RuntimeError("ChatGPT did not return its registered client ID")
    token_response = requests.post(ISSUER + "/api/accounts/oauth/token", data={
        "grant_type": "authorization_code", "client_id": client_id,
        "code": result["code"], "redirect_uri": redirect, "code_verifier": verifier,
        "resource": RESOURCE,
    }, timeout=20)
    token_response.raise_for_status()
    tokens = token_response.json()
    signing_key = jwt.PyJWKClient(oidc["jwks_uri"]).get_signing_key_from_jwt(tokens["id_token"]).key
    identity = jwt.decode(tokens["id_token"], signing_key, algorithms=["RS256", "ES256"], issuer=ISSUER, audience=client_id, options={"require": ["exp", "iat", "iss", "sub", "aud", "nonce"]})
    if identity.get("nonce") != nonce:
        raise RuntimeError("ChatGPT sign-in nonce validation failed")
    granted = set(tokens.get("scope", "").split())
    if "chatgpt.tokens.use.direct" not in granted:
        raise RuntimeError("ChatGPT plan usage permission was not granted")
    tokens["client_id"] = client_id
    keyring.set_password(SERVICE, "tokens", json.dumps(tokens))
    keyring.set_password(SERVICE, "oidc", json.dumps({"issuer": ISSUER, "token_endpoint": ISSUER + "/api/accounts/oauth/token", "client_id": client_id, "host_id": _host_id(), "id_token": tokens["id_token"], "label": identity.get("email", "ChatGPT account")}))
    return identity.get("email", "ChatGPT account")


def get_tokens():
    raw = keyring.get_password(SERVICE, "tokens")
    return json.loads(raw) if raw else None


def refresh_tokens(tokens):
    metadata = json.loads(keyring.get_password(SERVICE, "oidc") or "{}")
    if not tokens or not tokens.get("refresh_token") or not metadata.get("token_endpoint"):
        raise RuntimeError("ChatGPT sign-in expired; run aegis-agent login")
    response = requests.post(metadata["token_endpoint"], data={
        "grant_type": "refresh_token", "client_id": metadata["client_id"],
        "refresh_token": tokens["refresh_token"], "resource": RESOURCE,
    }, timeout=20)
    response.raise_for_status()
    updated = response.json()
    keyring.set_password(SERVICE, "tokens", json.dumps(updated))
    return updated


def logout():
    tokens = get_tokens() or {}
    metadata = json.loads(keyring.get_password(SERVICE, "oidc") or "{}")
    revoked = not tokens.get("refresh_token")
    if tokens.get("refresh_token") and metadata.get("client_id"):
        try:
            discovery = requests.get(ISSUER + "/.well-known/openid-configuration", timeout=15)
            discovery.raise_for_status()
            endpoint = discovery.json().get("revocation_endpoint")
            if endpoint:
                response = requests.post(endpoint, data={"token": tokens["refresh_token"], "token_type_hint": "refresh_token", "client_id": metadata["client_id"]}, timeout=15)
                revoked = response.status_code == 200
        except requests.RequestException:
            revoked = False
    for username in ("tokens", "oidc"):
        try:
            keyring.delete_password(SERVICE, username)
        except PasswordDeleteError:
            pass
    return revoked
