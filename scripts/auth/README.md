# GitHub App identities (#7)

Each of the six personas (athena, daedalus, cassandra, odyssey, argus,
atlas) is its own GitHub App — no shared App, no PAT-backed bot users.
`personas/<name>.yaml`'s `authority` block carries the public identifiers
(`identity`, `app_id`, `client_id`, `installation_id`); the private key
never lives in the repo.

## One-time: registering the Apps

```
python3 scripts/auth/create_all_apps.py
```

Loops over every persona in `app_manifests.yaml`, skipping any that
already has an `app_id` (never re-registers a duplicate App of the same
name). Per persona, it does everything GitHub's Manifest flow allows to
be scripted, and stops only at the two clicks GitHub itself requires:

1. Writes a pre-filled `/tmp/github_app_manifest_<persona>.html` (name,
   description, permissions already filled in from `app_manifests.yaml`).
2. **You**: open it in a browser, click **Create GitHub App**.
3. GitHub redirects to `http://localhost:9999/callback?code=...`. The
   script listens on that port and grabs the code automatically if your
   browser is on the same machine; otherwise paste the `code=` value back
   in when prompted.
4. Exchanges the code, saves the private key to
   `~/.keys/<slug>.<date>.private-key.pem` (chmod 600), patches
   `app_id`/`client_id` into `personas/<persona>.yaml`.
5. **You**: install the App on the repo at the printed
   `https://github.com/apps/<slug>/installations/new` URL.
6. Auto-discovers the `installation_id` and patches it in.

To do one persona at a time instead, use `create_github_app.py` and
`discover_installations.py` directly — see their docstrings.

## Naming: why `-app`, not `-bot`

Every App name is `<owner>-<persona>-app` (e.g. `evekhm-athena-app`).
App slugs and GitHub usernames share one namespace, so an App can't take
a name an existing user account already holds — this bit the three
carry-over personas (Odyssey, Argus, Atlas), which previously had plain
PAT-backed accounts named `evekhm-odyssey-bot`/`evekhm-argus`/
`evekhm-atlas-bot`. `-app` avoids that collision and is applied
uniformly to all six, not just the three that needed it.

## Forking this repo

Nothing here is hardcoded to `evekhm`. `_github_app.py:get_repo_info()`
derives `(owner, repo)` from `git remote get-url origin`, so running
`create_all_apps.py` in a fork registers Apps named
`<fork-owner>-<persona>-app` and installs them on the fork — no script
edits needed.

## Runtime: minting a token

```
python3 scripts/auth/mint_app_token.py <persona>
```

Signs a short-lived JWT with the persona's private key (env var named by
`authority.token`, or looked up under `~/.keys/`), exchanges it for a
~1-hour installation token, and prints it — usable directly as `GH_TOKEN`
for `gh`, or as the password half of a git credential helper. This is
what lets any machine (this one, another laptop, a CI runner) act as a
given persona: only the private-key file needs to move, everything else
is already in the repo.

In GitHub Actions, don't use this script — use
[`actions/create-github-app-token`](https://github.com/actions/create-github-app-token)
instead (same JWT exchange, done inside the runner); see the predecessor
repo's `ARGUS_SETUP.md` appendix.

## Files

- `app_manifests.yaml` — reviewable source data (name suffix,
  description, permissions) per persona. Editing an entry only affects
  Apps created *after* the edit.
- `_github_app.py` — shared JWT/auth helpers, not a CLI.
- `create_github_app.py` — register one App via the Manifest flow.
- `create_all_apps.py` — the six-persona wrapper described above.
- `discover_installations.py` — find an App's `installation_id`.
- `mint_app_token.py` — mint a working installation token.
