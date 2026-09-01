#!/usr/bin/env python3
"""Register a GitHub App from a manifest — the automatable 90% of App
creation, for one persona at a time.

GitHub requires one human click to consent to creating an App; nothing
can skip that. Everything else — name, description, permissions — is
scripted here via the App Manifest flow
(https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest).

Step 1 — generate the pre-filled form:

    scripts/auth/create_github_app.py athena

This writes an HTML file with an auto-submitting form and prints its
path. Open it in a browser (copy its contents to a local .html file
first if your browser isn't on this machine) — it lands on GitHub's
"Create GitHub App" review page with every field already filled in
from scripts/auth/app_manifests.yaml. Click **Create GitHub App**.

GitHub then redirects to a localhost URL that won't load — that's
expected. Copy the `code=...` value out of the browser's address bar.

Step 2 — exchange the code for real credentials:

    scripts/auth/create_github_app.py athena --code <code>

This calls the one-time conversion endpoint, then:
  - writes the private key to ~/.keys/<slug>.<today>.private-key.pem (chmod 600)
  - writes a redacted record (id/slug/client_id only, no secrets) next to it
  - prints the app_id and client_id to paste into personas/<persona>.yaml

Then run discover_installations.py <persona> after installing the App
on the repo, same as the Athena flow.
"""

import argparse
import json
import sys
import urllib.error
import urllib.request
from datetime import date
from pathlib import Path

import yaml

from _github_app import get_repo_info

REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFESTS_FILE = REPO_ROOT / "scripts" / "auth" / "app_manifests.yaml"
LOCAL_KEY_DIR = Path.home() / ".keys"
OWNER, REPO = get_repo_info()
REPO_URL = f"https://github.com/{OWNER}/{REPO}"
FAKE_REDIRECT = "http://localhost:9999/callback"

FORM_HTML = """<!doctype html>
<html>
<body onload="document.forms[0].submit()">
  <form action="https://github.com/settings/apps/new" method="post">
    <input type="hidden" name="manifest" value='{manifest_json}'>
    <noscript><button type="submit">Create GitHub App: {name}</button></noscript>
  </form>
  <p>Submitting to GitHub to create <b>{name}</b>... if nothing happens, click the button.</p>
</body>
</html>
"""


def load_manifest_source(persona: str) -> dict:
    manifests = yaml.safe_load(MANIFESTS_FILE.read_text())
    if persona not in manifests:
        sys.exit(f"no manifest data for {persona} in {MANIFESTS_FILE}")
    source = manifests[persona]
    source["name"] = f"{OWNER}-{source['slug_suffix']}"
    return source


def build_manifest(source: dict) -> dict:
    return {
        "name": source["name"],
        "url": REPO_URL,
        "description": source["description"].strip(),
        "redirect_url": FAKE_REDIRECT,
        "public": False,
        # hook_attributes requires a url whenever the key is present at all —
        # omitting url here left the block malformed and GitHub silently
        # dropped the whole manifest, falling back to a blank form.
        "hook_attributes": {"url": REPO_URL, "active": False},
        "default_permissions": source["default_permissions"],
    }


def write_form(persona: str, source: dict, manifest: dict) -> Path:
    # json.dumps then escape single quotes for the HTML attribute
    manifest_json = json.dumps(manifest).replace("'", "&#39;")
    html = FORM_HTML.format(manifest_json=manifest_json, name=source["name"])
    out_path = Path(f"/tmp/github_app_manifest_{persona}.html")
    out_path.write_text(html)
    return out_path


def exchange_code(code: str) -> dict:
    request = urllib.request.Request(
        f"https://api.github.com/app-manifests/{code}/conversions",
        method="POST",
        headers={"Accept": "application/vnd.github+json"},
    )
    try:
        with urllib.request.urlopen(request) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        sys.exit(f"GitHub rejected the code exchange ({error.code}): {error.read().decode()}")


def save_credentials(persona: str, result: dict) -> None:
    LOCAL_KEY_DIR.mkdir(mode=0o700, exist_ok=True)
    slug = result["slug"]
    today = date.today().isoformat()
    key_path = LOCAL_KEY_DIR / f"{slug}.{today}.private-key.pem"
    key_path.write_text(result["pem"])
    key_path.chmod(0o600)

    record_path = LOCAL_KEY_DIR / f"{slug}.{today}.app-record.json"
    record = {k: result[k] for k in ("id", "slug", "client_id", "name") if k in result}
    record_path.write_text(json.dumps(record, indent=2))
    record_path.chmod(0o600)

    print(f"private key saved: {key_path}")
    print(f"app_id: {result['id']}")
    print(f"client_id: {result['client_id']}")
    print(
        f"\nNext: fill these into personas/{persona}.yaml's authority block "
        f"(app_id, client_id, token: {persona.upper()}_APP_PRIVATE_KEY), "
        "install the App on the repo, then run "
        f"discover_installations.py {persona} for the installation_id."
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("persona", help="persona name, e.g. athena")
    parser.add_argument("--code", help="the code= value from the redirect URL, to finish registration")
    args = parser.parse_args()

    source = load_manifest_source(args.persona)

    if args.code:
        result = exchange_code(args.code)
        save_credentials(args.persona, result)
        return

    manifest = build_manifest(source)
    form_path = write_form(args.persona, source, manifest)
    print(f"wrote {form_path}")
    print(
        "\nOpen it in a browser (copy its contents to a local .html file first "
        "if your browser isn't on this machine). It auto-submits to GitHub's "
        f"pre-filled 'Create GitHub App: {source['name']}' review page.\n"
        "Click Create GitHub App, then copy the code=... value from the "
        "(failing-to-load) redirect URL and run:\n"
        f"  scripts/auth/create_github_app.py {args.persona} --code <code>"
    )


if __name__ == "__main__":
    main()
