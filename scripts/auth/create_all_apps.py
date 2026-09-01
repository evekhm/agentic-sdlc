#!/usr/bin/env python3
"""Single wrapper: walk through registering every persona's GitHub App,
one after another, in one command:

    python3 scripts/auth/create_all_apps.py

For each persona in scripts/auth/app_manifests.yaml, it checks
personas/<persona>.yaml first: if an app_id is already set — whether
or not it's been installed yet — that persona is skipped, since an
App of that name already exists and re-running the manifest flow
would register a duplicate. Otherwise it: prints the description,
writes the pre-filled manifest form, waits for you to click through
GitHub and paste back the code, exchanges it, has you install the
App, then auto-discovers the installation_id and writes
app_id/client_id/installation_id straight into personas/<persona>.yaml.

You still do exactly what GitHub requires and nothing more, per App:
one click to create it, one click to install it, one paste of the
code. Everything else — typing commands, filling forms, editing yaml —
is done for you. Type 'skip' at any prompt to leave a persona for
later; re-running this script picks up where you left off.
"""

import yaml

from _github_app import PERSONAS_DIR, get_repo_info, load_authority, load_private_key, mint_jwt, wait_for_callback_code
from create_github_app import build_manifest, exchange_code, load_manifest_source, save_credentials, write_form
from discover_installations import list_installations

ORDER = ["athena", "daedalus", "cassandra", "odyssey", "argus", "atlas"]
OWNER, REPO = get_repo_info()


def app_status(persona: str) -> str:
    """'installed' or 'created' (App already registered under this name,
    with or without an install — either way, skip: never re-register a
    duplicate App of the same name) vs 'new' (nothing registered yet).
    """
    path = PERSONAS_DIR / f"{persona}.yaml"
    data = yaml.safe_load(path.read_text())
    authority = data.get("authority", {})
    if authority.get("installation_id"):
        return "installed"
    if authority.get("app_id") or authority.get("client_id"):
        return "created"
    return "new"


def patch_yaml(persona: str, old: str, new: str) -> bool:
    path = PERSONAS_DIR / f"{persona}.yaml"
    text = path.read_text()
    if old not in text:
        print(f"  (couldn't auto-patch personas/{persona}.yaml — format changed; edit it by hand)")
        return False
    path.write_text(text.replace(old, new, 1))
    return True


def create_one(persona: str) -> bool:
    source = load_manifest_source(persona)
    print(f"\n=== {persona} ({source['name']}) ===")
    print(f"Description (paste into GitHub's Description field):\n  {source['description'].strip()}")

    manifest = build_manifest(source)
    form_path = write_form(persona, source, manifest)
    print(f"\nForm written to {form_path}")
    print(
        "Open it in a browser (copy its contents to a local .html file first "
        "if your browser isn't on this machine). It auto-submits to GitHub's "
        f"pre-filled 'Create GitHub App: {source['name']}' review page — "
        "name, description, and permissions are already filled in. Just click "
        "Create GitHub App."
    )
    print("Waiting for the redirect (up to 3 min) — I'll grab the code automatically if your browser can reach this machine...")
    code = wait_for_callback_code(timeout_secs=180)
    if not code:
        code = input(
            "Didn't catch it automatically — paste the code=... value from the "
            "redirect URL (or 'skip'): "
        ).strip()
    if not code or code.lower() == "skip":
        print(f"skipping {persona} — re-run this script later to finish it")
        return False
    print("got the code.")

    result = exchange_code(code)
    save_credentials(persona, result)

    patched = patch_yaml(
        persona,
        "  # app_id: <fill in once the App is registered, #7>\n"
        "  # installation_id: <fill in once the App is installed on this repo, #7>\n",
        f"  app_id: {result['id']}\n"
        f"  client_id: \"{result['client_id']}\"\n"
        "  # installation_id: <fill in once the App is installed on this repo, #7>\n",
    )
    if not patched:
        return False

    install_url = f"https://github.com/apps/{result['slug']}/installations/new"
    print(f"\nNow install it on the repo: {install_url}")
    input(f"Press Enter once you've installed it (select {OWNER}/{REPO}, not All repositories)... ")

    authority = load_authority(persona, require_installation=False)
    private_key = load_private_key(authority["token"], authority["identity"])
    signed_jwt = mint_jwt(authority, private_key)
    installations = list_installations(signed_jwt)
    matches = [i for i in installations if i["account"]["login"] == OWNER]
    if len(matches) != 1:
        print(f"  found {len(matches)} matching installations, expected 1 — set installation_id by hand")
        return False
    installation_id = matches[0]["id"]
    patch_yaml(
        persona,
        "  # installation_id: <fill in once the App is installed on this repo, #7>\n",
        f"  installation_id: {installation_id}\n",
    )
    print(f"personas/{persona}.yaml fully configured (installation_id={installation_id})")
    return True


def main() -> None:
    done, skipped = [], []
    for persona in ORDER:
        status = app_status(persona)
        if status != "new":
            reason = "already installed" if status == "installed" else "App already registered but not installed"
            print(f"=== {persona}: {reason}, skipping (edit personas/{persona}.yaml by hand if that's wrong) ===")
            continue
        if create_one(persona):
            done.append(persona)
        else:
            skipped.append(persona)

    print("\n--- summary ---")
    print(f"configured this run: {done or 'none'}")
    print(f"still pending: {skipped or 'none'}")
    if skipped:
        print("re-run this script to pick up where you left off")


if __name__ == "__main__":
    main()
