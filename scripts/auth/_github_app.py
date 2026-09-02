"""Shared helpers for GitHub App auth: read a persona's authority block,
locate its private key, and sign the JWT the App API needs. Not a CLI —
imported by mint_app_token.py and discover_installations.py so the JWT
logic exists in exactly one place.

For CI (GitHub Actions), do not use this module directly: use the
`actions/create-github-app-token` action instead (the predecessor
repo's docs/ARGUS_SETUP.md appendix), which does the same JWT-exchange
inside the runner. This module is for interactive sessions and other
non-Actions machines, where that action isn't available.
"""

import os
import re
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import jwt
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
PERSONAS_DIR = REPO_ROOT / "personas"
LOCAL_KEY_DIR = Path.home() / ".keys"
CALLBACK_PORT = 9999


def get_repo_info() -> tuple[str, str]:
    """Derive (owner, repo) from this checkout's `origin` remote, so a fork
    automatically registers its own non-colliding App names instead of
    inheriting the upstream owner hardcoded into the source.
    """
    result = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "remote", "get-url", "origin"],
        capture_output=True,
        text=True,
        check=True,
    )
    url = result.stdout.strip()
    # matches both git@github.com:owner/repo.git and https://github.com/owner/repo(.git)
    match = re.search(r"github\.com[:/]([^/]+)/([^/]+?)(\.git)?$", url)
    if not match:
        sys.exit(f"couldn't parse owner/repo out of origin remote: {url}")
    return match.group(1), match.group(2)


def load_authority(persona: str, require_installation: bool) -> dict:
    source = PERSONAS_DIR / f"{persona}.yaml"
    if not source.exists():
        sys.exit(f"no persona source at {source}")
    data = yaml.safe_load(source.read_text())
    if data.get("kind") != "persona":
        sys.exit(f"{persona} is not kind: persona (has no GitHub identity)")
    authority = data.get("authority", {})
    required = ["identity", "token"]
    required += ["client_id"] if not authority.get("app_id") else []
    if require_installation:
        required.append("installation_id")
    missing = [k for k in required if not authority.get(k)]
    if missing or not (authority.get("client_id") or authority.get("app_id")):
        sys.exit(
            f"{persona}: authority.{'/'.join(missing) or 'client_id or app_id'} "
            "not set yet — the App hasn't been registered/installed (see issue #7)"
        )
    return authority


def load_private_key(token_name: str, identity: str) -> str:
    env_value = os.environ.get(token_name)
    if env_value:
        return env_value
    slug = identity.removesuffix("[bot]")
    matches = sorted(LOCAL_KEY_DIR.glob(f"{slug}.*.private-key.pem"))
    if matches:
        return matches[-1].read_text()  # dated filenames sort chronologically
    sys.exit(
        f"no private key for {slug}: set env var {token_name}, or place the "
        f"key GitHub generated at {LOCAL_KEY_DIR}/{slug}.<date>.private-key.pem"
    )


def mint_jwt(authority: dict, private_key: str) -> str:
    now = int(time.time())
    issuer = authority.get("client_id") or authority["app_id"]
    payload = {"iat": now - 60, "exp": now + 9 * 60, "iss": issuer}
    return jwt.encode(payload, private_key, algorithm="RS256")


class _CallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        code = parse_qs(urlparse(self.path).query).get("code", [None])[0]
        self.server.captured_code = code
        self.send_response(200 if code else 400)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        message = "Got it — you can close this tab." if code else "No code in that redirect."
        self.wfile.write(f"<html><body><h3>{message}</h3></body></html>".encode())

    def log_message(self, format, *args):  # noqa: A002 - silence default request logging
        pass


def wait_for_callback_code(timeout_secs: int = 180) -> str | None:
    """Listen on localhost for GitHub's manifest-flow redirect and grab its
    `code`. Only receives the request if the browser doing the redirect can
    reach this machine's CALLBACK_PORT (true when the browser runs on this
    same machine; false for a browser on a separate laptop/workstation) —
    callers must fall back to a manual paste prompt on a None/timeout return.
    """
    try:
        server = HTTPServer(("0.0.0.0", CALLBACK_PORT), _CallbackHandler)
    except OSError:
        return None
    server.captured_code = None
    server.timeout = timeout_secs
    server.handle_request()
    server.server_close()
    return server.captured_code
