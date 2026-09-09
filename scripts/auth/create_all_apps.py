#!/usr/bin/env python3
"""Single wrapper: walk through registering every GitHub App this repo
needs, one after another, in one command:

    python3 scripts/auth/create_all_apps.py

It walks scripts/auth/app_manifests.yaml in file order. An entry with no
`kind` is a persona; an entry with `kind: system` is a system actor.

For a persona it checks personas/<persona>.yaml first: if an app_id is
already set — whether or not it's been installed yet — that persona is
skipped, since an App of that name already exists and re-running the
manifest flow would register a duplicate. Otherwise it: prints the
description, writes the pre-filled manifest form, waits for you to click
through GitHub and paste back the code, exchanges it, has you install
the App, then auto-discovers the installation_id and writes
app_id/client_id/installation_id straight into personas/<persona>.yaml.

A system actor has no persona file. Themis, the merge actor of the
autonomous loop (#64), is the only one today. It is registered the same
way, and then provisioned: the script creates the GitHub Environment
named by the entry, restricts that Environment's deployment-branch
policy to `main`, and loads the App id and private key into it as the
two environment secrets the entry names. The Actions workflows mint the
token from that Environment, so a pull request running the workflow file
from its own branch can never reach the key. Provisioning needs
repository admin: run it as the repo owner, or run the gh commands the
script prints. It is idempotent, so re-running it is safe. No
installation-id discovery happens for a system actor, because
actions/create-github-app-token discovers it at mint time.

You still do exactly what GitHub requires and nothing more, per App:
one click to create it, one click to install it, one paste of the
code. Everything else — typing commands, filling forms, editing yaml —
is done for you. Type 'skip' at any prompt to leave an entry for
later; re-running this script picks up where you left off.

Two read-only flags help:

    python3 scripts/auth/create_all_apps.py --check
    python3 scripts/auth/create_all_apps.py --only themis

`--check` prints one status row per manifest entry and exits 0 only when
every row is complete. `--only <name>` restricts the run, or the check,
to a single entry.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

import yaml

from _github_app import LOCAL_KEY_DIR, PERSONAS_DIR, get_repo_info, load_authority, load_private_key, mint_jwt, wait_for_callback_code
from create_github_app import MANIFESTS_FILE, build_manifest, exchange_code, load_manifest_source, save_credentials, write_form
from discover_installations import list_installations

OWNER, REPO = get_repo_info()
NWO = f"{OWNER}/{REPO}"


# --- manifest ---------------------------------------------------------


def load_entries() -> dict:
    """Every manifest entry, in file order."""
    return yaml.safe_load(MANIFESTS_FILE.read_text())


def entry_kind(entry: dict) -> str:
    """An entry with no `kind` is a persona."""
    return entry.get("kind", "persona")


def app_slug(entry: dict) -> str:
    """The App's slug: the owner from `git remote` plus the suffix."""
    return f"{OWNER}-{entry['slug_suffix']}"


# --- local artifacts --------------------------------------------------


def newest_key_file(slug: str, pattern: str) -> Path | None:
    """The newest ~/.keys/<slug>.<date>.<pattern> — dated filenames sort
    chronologically, so the last match is the current one.
    """
    matches = sorted(LOCAL_KEY_DIR.glob(f"{slug}.*.{pattern}"))
    return matches[-1] if matches else None


def local_key(slug: str) -> Path | None:
    return newest_key_file(slug, "private-key.pem")


def local_record(slug: str) -> dict | None:
    path = newest_key_file(slug, "app-record.json")
    if not path:
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return None


# --- gh ---------------------------------------------------------------


def run_gh(args: list[str], stdin_text: str | None = None) -> subprocess.CompletedProcess:
    """Run `gh` and hand back the result. GH_TOKEN, when the environment
    sets one, is inherited; otherwise gh uses its own stored auth.
    """
    return subprocess.run(["gh", *args], input=stdin_text, capture_output=True, text=True)


def gh_json(args: list[str]) -> dict | list | None:
    """The parsed body of a successful `gh api` read, else None."""
    result = run_gh(args)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def gh_error(result: subprocess.CompletedProcess) -> str:
    """The first meaningful line of a failed gh call, for the operator."""
    for line in (result.stderr or result.stdout).splitlines():
        if line.strip():
            return line.strip()
    return f"exit {result.returncode}"


def bot_user_id(slug: str) -> int | None:
    """The bot user's id when the App exists on GitHub, else None. This
    is NOT the App id: the two are different numbers.
    """
    data = gh_json(["api", f"users/{slug}%5Bbot%5D"])
    return data.get("id") if isinstance(data, dict) else None


# --- status -----------------------------------------------------------


def persona_status(persona: str) -> str:
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


def system_status(slug: str) -> str:
    """'created' when the App resolves on GitHub or a local record exists,
    else 'new'. A system actor has no persona file to read.
    """
    if bot_user_id(slug) is not None:
        return "created"
    if local_record(slug) is not None:
        return "created"
    return "new"


# --- registration -----------------------------------------------------


def patch_yaml(persona: str, old: str, new: str) -> bool:
    path = PERSONAS_DIR / f"{persona}.yaml"
    text = path.read_text()
    if old not in text:
        print(f"  (couldn't auto-patch personas/{persona}.yaml — format changed; edit it by hand)")
        return False
    path.write_text(text.replace(old, new, 1))
    return True


def register_app(name: str, source: dict) -> dict | None:
    """The manifest flow, identical for a persona and a system actor:
    pre-filled form, one human click, code exchange, credentials saved.
    Returns GitHub's conversion result, or None when you skip.
    """
    print(f"\n=== {name} ({source['name']}) ===")
    print(f"Description (paste into GitHub's Description field):\n  {source['description'].strip()}")

    manifest = build_manifest(source)
    form_path = write_form(name, source, manifest)
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
        print(f"skipping {name} — re-run this script later to finish it")
        return None
    print("got the code.")

    return exchange_code(code)


def install_prompt(slug: str) -> None:
    install_url = f"https://github.com/apps/{slug}/installations/new"
    print(f"\nNow install it on the repo: {install_url}")
    input(f"Press Enter once you've installed it (select {NWO}, not All repositories)... ")


def create_persona(persona: str, source: dict) -> bool:
    result = register_app(persona, source)
    if result is None:
        return False
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

    install_prompt(result["slug"])

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


def create_system(name: str, source: dict) -> str | None:
    """Register a system actor's App. Returns its slug, or None on skip."""
    result = register_app(name, source)
    if result is None:
        return None
    save_credentials(name, result, kind="system")
    install_prompt(result["slug"])
    return result["slug"]


# --- provisioning -----------------------------------------------------


def resolve_app_id(slug: str) -> str | None:
    """The App id, from the record file written at registration. The bot
    user id from users/<slug>[bot] is a different number and cannot
    stand in for it, so ask when the record is missing.
    """
    record = local_record(slug)
    if record and record.get("id"):
        return str(record["id"])
    answer = input(
        f"no ~/.keys/{slug}.<date>.app-record.json — paste the App id from "
        f"https://github.com/settings/apps/{slug} (the App id from that "
        "page, which is a different number from the bot user id), or Enter "
        "to skip: "
    ).strip()
    return answer or None


def provision_system(name: str, entry: dict, slug: str) -> bool:
    """Create the Environment, hold its deployment-branch policy to
    `main`, and load the two secrets. Idempotent: every step is a
    create-or-confirm. Needs repository admin; on a refusal it prints the
    command for the operator and carries on. Never prints a secret value.
    """
    env_name = entry["environment"]
    secret_names = entry["secrets"]
    print(f"\n--- provisioning {name}: environment `{env_name}` on {NWO} ---")
    manual: list[str] = []
    ok = True

    # a. the Environment itself, with custom branch policies enabled so a
    #    `main`-only policy can exist at all.
    body = json.dumps({"deployment_branch_policy": {"protected_branches": False, "custom_branch_policies": True}})
    env_path = f"repos/{NWO}/environments/{env_name}"
    result = run_gh(["api", "--method", "PUT", env_path, "--input", "-"], stdin_text=body)
    if result.returncode == 0:
        print(f"  environment `{env_name}`: ready")
    else:
        ok = False
        print(f"  environment `{env_name}`: {gh_error(result)}")
        manual.append(f"echo '{body}' | gh api --method PUT {env_path} --input -")

    # b. the deployment-branch policy. The Environment must admit `main`
    #    and nothing else (spec P1): that is what keeps a workflow file on
    #    any other branch from minting the key.
    policies_path = f"{env_path}/deployment-branch-policies"
    add = json.dumps({"name": "main", "type": "branch"})
    listing = gh_json(["api", policies_path])
    policies = listing.get("branch_policies", []) if isinstance(listing, dict) else None
    if policies is None:
        ok = False
        print("  branch policy: could not read the current policies")
        manual.append(f"gh api {policies_path}  # confirm main is the only policy")
        manual.append(f"echo '{add}' | gh api --method POST {policies_path} --input -  # if main is missing")
    else:
        others = [p["name"] for p in policies if not (p.get("name") == "main" and p.get("type") == "branch")]
        if others:
            print(f"  WARNING: this environment also admits {', '.join(others)} — it must admit main only (spec P1). Remove them.")
            ok = False
        if any(p.get("name") == "main" and p.get("type") == "branch" for p in policies):
            print("  branch policy `main`: present")
        else:
            add = json.dumps({"name": "main", "type": "branch"})
            result = run_gh(["api", "--method", "POST", policies_path, "--input", "-"], stdin_text=add)
            if result.returncode == 0:
                print("  branch policy `main`: created")
            else:
                ok = False
                print(f"  branch policy `main`: {gh_error(result)}")
                manual.append(f"echo '{add}' | gh api --method POST {policies_path} --input -")

    # c. the two environment secrets. The value never reaches a print or
    #    an argv: the App id goes through --body, the key through stdin.
    app_id = resolve_app_id(slug)
    id_secret = secret_names["app_id"]
    if app_id:
        result = run_gh(["secret", "set", id_secret, "--env", env_name, "--repo", NWO, "--body", app_id])
        if result.returncode == 0:
            print(f"  secret {id_secret}: set")
        else:
            ok = False
            print(f"  secret {id_secret}: {gh_error(result)}")
            manual.append(f"gh secret set {id_secret} --env {env_name} --repo {NWO} --body <app id>")
    else:
        ok = False
        print(f"  secret {id_secret}: skipped, no App id")
        manual.append(f"gh secret set {id_secret} --env {env_name} --repo {NWO} --body <app id>")

    key_secret = secret_names["private_key"]
    key_path = local_key(slug)
    if key_path:
        result = run_gh(
            ["secret", "set", key_secret, "--env", env_name, "--repo", NWO],
            stdin_text=key_path.read_text(),
        )
        if result.returncode == 0:
            print(f"  secret {key_secret}: set from {key_path}")
        else:
            ok = False
            print(f"  secret {key_secret}: {gh_error(result)}")
            manual.append(f"gh secret set {key_secret} --env {env_name} --repo {NWO} < {key_path}")
    else:
        ok = False
        print(f"  secret {key_secret}: no private key under {LOCAL_KEY_DIR}/{slug}.<date>.private-key.pem")
        manual.append(f"gh secret set {key_secret} --env {env_name} --repo {NWO} < ~/.keys/{slug}.<date>.private-key.pem")

    if manual:
        print(
            "\n  Provisioning needs repository admin. Run these under an "
            "account that has it (gh auth as the repo owner), then re-run "
            "this script with --check:"
        )
        for command in manual:
            print(f"    {command}")
    return ok


# --- check ------------------------------------------------------------

CHECK_COLUMNS = ["name", "kind", "slug", "app", "key", "install", "env", "policy", "sec:app_id", "sec:key"]


def check_row(name: str, entry: dict) -> tuple[dict[str, str], bool]:
    """One status row, and whether that row counts as complete. The row
    holds display strings only; completeness travels beside it.
    """
    kind = entry_kind(entry)
    slug = app_slug(entry)
    row: dict[str, str] = {c: "-" for c in CHECK_COLUMNS}
    row["name"] = name
    row["kind"] = kind
    row["slug"] = slug
    row["app"] = "yes" if bot_user_id(slug) is not None else "no"
    row["key"] = "yes" if local_key(slug) else "no"

    if kind == "persona":
        row["install"] = "yes" if persona_status(name) == "installed" else "no"
        return row, all(row[c] == "yes" for c in ("app", "key", "install"))

    env_name = entry["environment"]
    env_path = f"repos/{NWO}/environments/{env_name}"
    row["env"] = "yes" if gh_json(["api", env_path]) is not None else "no"

    listing = gh_json(["api", f"{env_path}/deployment-branch-policies"])
    policies = listing.get("branch_policies", []) if isinstance(listing, dict) else None
    if policies is None:
        row["policy"] = "no"
    else:
        main_only = len(policies) == 1 and policies[0].get("name") == "main" and policies[0].get("type") == "branch"
        row["policy"] = "yes" if main_only else "no"

    secrets = gh_json(["api", f"{env_path}/secrets"])
    present = {s["name"] for s in secrets.get("secrets", [])} if isinstance(secrets, dict) else set()
    row["sec:app_id"] = "yes" if entry["secrets"]["app_id"] in present else "no"
    row["sec:key"] = "yes" if entry["secrets"]["private_key"] in present else "no"
    return row, all(row[c] == "yes" for c in ("app", "key", "env", "policy", "sec:app_id", "sec:key"))


def run_check(entries: dict) -> int:
    results = [check_row(name, entry) for name, entry in entries.items()]
    rows = [row for row, _ in results]
    widths = {c: max(len(c), *(len(r[c]) for r in rows)) for c in CHECK_COLUMNS}
    print("  ".join(c.ljust(widths[c]) for c in CHECK_COLUMNS))
    print("  ".join("-" * widths[c] for c in CHECK_COLUMNS))
    for row in rows:
        print("  ".join(row[c].ljust(widths[c]) for c in CHECK_COLUMNS))

    incomplete = [row["name"] for row, complete in results if not complete]
    print()
    if incomplete:
        print(f"incomplete: {', '.join(incomplete)}")
        print("run this script without --check to finish them")
        return 1
    print("every entry is complete")
    return 0


# --- main -------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="read-only status table; exit 0 only when every entry is complete")
    parser.add_argument("--only", metavar="NAME", help="restrict the run, or the check, to one manifest entry")
    args = parser.parse_args()

    entries = load_entries()
    if args.only:
        if args.only not in entries:
            sys.exit(f"no manifest entry named {args.only} in {MANIFESTS_FILE}")
        entries = {args.only: entries[args.only]}

    if args.check:
        sys.exit(run_check(entries))

    done, skipped = [], []
    for name, entry in entries.items():
        kind = entry_kind(entry)
        slug = app_slug(entry)
        source = load_manifest_source(name)

        if kind == "persona":
            status = persona_status(name)
            if status != "new":
                reason = "already installed" if status == "installed" else "App already registered but not installed"
                print(f"=== {name}: {reason}, skipping (edit personas/{name}.yaml by hand if that's wrong) ===")
                continue
            (done if create_persona(name, source) else skipped).append(name)
            continue

        if system_status(slug) == "new":
            created = create_system(name, source)
            if created is None:
                skipped.append(name)
                continue
            slug = created
        else:
            print(f"=== {name}: App {slug} already registered, skipping registration ===")
        (done if provision_system(name, entry, slug) else skipped).append(name)

    print("\n--- summary ---")
    print(f"configured this run: {done or 'none'}")
    print(f"still pending: {skipped or 'none'}")
    if skipped:
        print("re-run this script to pick up where you left off")


if __name__ == "__main__":
    main()
