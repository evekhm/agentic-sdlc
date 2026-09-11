# GitHub App identities (#7)

This repo registers seven GitHub Apps: one per persona (athena,
daedalus, cassandra, odyssey, argus, atlas), plus one system actor
(themis). There is no shared App and there are no PAT-backed bot users.
For a persona, `personas/<name>.yaml`'s `authority` block carries the
public identifiers (`identity`, `app_id`, `client_id`,
`installation_id`). The system actor has no persona file; its
identifiers live in the GitHub Environment named in `app_manifests.yaml`.
The private key never lives in the repo.

`app_manifests.yaml` tells the two apart. An entry with no `kind` is a
persona. An entry with `kind: system` is a system actor.

## One-time: registering the Apps

```
python3 scripts/auth/create_all_apps.py
python3 scripts/auth/create_all_apps.py --check
python3 scripts/auth/create_all_apps.py --only themis
```

The first command walks every entry in `app_manifests.yaml` in file
order. It skips any persona that already has an `app_id`, so it never
registers a duplicate App of the same name.

`--check` is read-only. It prints one status row per entry: whether the
App exists on GitHub, whether its private key is on this machine, and
then, for a persona, whether `installation_id` is set, or, for a system
actor, whether its Environment, its branch policy and its two secrets
are in place. It exits 0 only when every row is complete.

`--only <name>` restricts the run, or the check, to a single entry.

Per persona, the script does everything GitHub's Manifest flow allows to
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

## System actor: Themis

Themis is the merge actor of the autonomous loop (#64). It is the one
trusted writer of the loop's state: the loop ledger, the escalation
marker, the consensus ledger. It is also the identity that merges a pull
request once consensus is reached. Themis is a system actor. It has no
prompt, no harness and no goals, and it is absent from INTENT.md's cast.
The six personas are unchanged.

Its private key lives in a GitHub Environment named `themis`, whose
deployment-branch policy admits `main` and nothing else. The reason is
narrow. A same-repo pull request runs the workflow file from its own
branch, and that run can read repository secrets. An environment secret
restricted to `main` is the one GitHub mechanism such a run cannot
reach. This is spec decision D23 and precondition P1.

The Actions workflows mint Themis tokens from that Environment with
[`actions/create-github-app-token`](https://github.com/actions/create-github-app-token).
No repository secret and no organization secret may carry the names
`THEMIS_APP_ID` or `THEMIS_APP_PRIVATE_KEY`. A secret at either of those
scopes would be visible to a pull-request run and would defeat P1.

Operator steps:

1. `python3 scripts/auth/create_all_apps.py --only themis`. The full run
   also reaches Themis, after the six personas.
2. Click **Create GitHub App** on the pre-filled form. The script grabs
   the code from the redirect, or you paste it in.
3. Install the App on this repository only.
4. The script provisions the Environment `themis`, its `main` branch
   policy, and the two secrets `THEMIS_APP_ID` and
   `THEMIS_APP_PRIVATE_KEY`. This needs repository admin, so run it as
   yourself with `gh` authenticated as the repo owner. If a step is
   refused, the script prints the exact `gh` command for you to run.
5. `python3 scripts/auth/create_all_apps.py --check` shows every row
   complete.

Provisioning is idempotent. Re-running it confirms what is already there
and creates only what is missing.

## Naming: why `-app`, not `-bot`

Every App name is `<owner>-<suffix>-app` (e.g. `evekhm-athena-app`,
`evekhm-themis-app`). App slugs and GitHub usernames share one
namespace, so an App can't take a name an existing user account already
holds. `-app` sidesteps any such collision and is applied uniformly to
all seven Apps.

## Forking this repo

Nothing here is hardcoded to `evekhm`. `_github_app.py:get_repo_info()`
derives `(owner, repo)` from `git remote get-url origin`, so running
`create_all_apps.py` in a fork registers Apps named
`<fork-owner>-<suffix>-app` and installs them on the fork — no script
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

## Workstation setup: installing private keys in `~/.keys/`

When running interactive sessions or local automation (such as `work.sh`,
Odyssey, Daedalus, or Athena), the local workstation must be able to mint
installation tokens directly.

### Why local private keys are critical

1. **Persona attribution and provenance:** Every commit, PR, review, and issue
   mutation must be authoritatively attributed to its persona's GitHub App
   identity (e.g. `evekhm-odyssey-app[bot]`), not to the human operator's
   personal account. Commits and comments without persona App tokens fail
   provenance checks.
2. **Reviewer consensus integrity:** Autonomous reviewers (Argus and Atlas)
   must authenticate with distinct App identities. Without separate private
   keys, local sessions would fall back to ambient operator PATs, which
   invalidates consensus because both reviews would appear from the same user.
3. **Local/CI parity:** GitHub Actions workflows use repository secrets to mint
   App tokens. Storing matching `.pem` files in `~/.keys/` allows local
   harness sessions to operate with the exact same identity boundaries as CI.

### Step-by-step setup

1. Create the key directory under your home folder (never inside the repository):
   ```bash
   mkdir -p ~/.keys
   chmod 700 ~/.keys
   ```
2. Save the GitHub App private key `.pem` files into `~/.keys/` using the naming
   format `<slug>.<date>.private-key.pem` with permissions `600`:
   ```bash
   chmod 600 ~/.keys/*.private-key.pem
   ```
   The `<slug>` corresponds to the persona App name without `[bot]`:
   - `~/.keys/evekhm-athena-app.2026-09-11.private-key.pem`
   - `~/.keys/evekhm-daedalus-app.2026-09-11.private-key.pem`
   - `~/.keys/evekhm-odyssey-app.2026-09-11.private-key.pem`
   - `~/.keys/evekhm-argus-app.2026-09-11.private-key.pem`
   - `~/.keys/evekhm-atlas-app.2026-09-11.private-key.pem`
   - `~/.keys/evekhm-cassandra-app.2026-09-11.private-key.pem`
   - `~/.keys/evekhm-themis-app.2026-09-11.private-key.pem`
3. Verify all registrations, keys, and installations:
   ```bash
   python3 scripts/auth/create_all_apps.py --check
   ```
   Every row should report `yes` across `app`, `key`, and `install`.
4. Test minting an installation token:
   ```bash
   python3 scripts/auth/mint_app_token.py odyssey --quiet && echo "Minting successful"
   ```

## Files

- `app_manifests.yaml` — reviewable source data per entry: name suffix,
  description, permissions, and, for a system actor, its `kind`,
  `environment` and `secrets`. Editing an entry only affects Apps
  created *after* the edit.
- `_github_app.py` — shared JWT/auth helpers, not a CLI.
- `create_github_app.py` — register one App via the Manifest flow.
- `create_all_apps.py` — the wrapper described above. It registers all
  seven Apps, provisions the system actor's Environment and secrets, and
  carries `--check` and `--only`.
- `discover_installations.py` — find a persona App's `installation_id`.
  System actors skip this step.
- `mint_app_token.py` — mint a working installation token.
