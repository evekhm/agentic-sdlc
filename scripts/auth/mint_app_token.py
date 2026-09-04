#!/usr/bin/env python3
"""Mint a short-lived GitHub App installation token for one persona.

Reads client_id/installation_id/token-secret-name from
personas/<persona>.yaml's authority block, signs a JWT with the App's
private key (via _github_app.py), exchanges it for a ~1-hour
installation token, and prints ONLY the token to stdout. The token
then works exactly like a PAT for that persona's identity:

    export GH_TOKEN=$(scripts/auth/mint_app_token.py odyssey)
    gh pr comment 42 --body "..." --repo evekhm/agentic-sdlc

The private key is never stored in the repo. It is read from, in
order: the environment variable named by the persona's `token` field
(the GitHub Actions case — though in Actions prefer the
`actions/create-github-app-token` action instead of this script), or
the dated .pem file GitHub generated for that App under ~/.keys/
(the interactive-session / other-machine case).

installation_id unknown? Run discover_installations.py first.

--require-repo is the preflight every unattended run performs first
(#25, D4). An App being *registered* is not an App being *installed
here*: an installation token mints successfully whether or not the
installation's repository selection includes this repository, so
without the check the failure surfaces at the first write, after the
model has already been paid for. It lives inside the minting path on
purpose — a check that lives in the only credential path cannot be
forgotten by an adapter. --quiet performs everything and prints
nothing, so an adapter preflights without a token ever reaching a
shell variable.
"""

import argparse
import json
import sys
import urllib.error
import urllib.request

from _github_app import get_repo_info, load_authority, load_private_key, mint_jwt


def exchange_for_installation_token(installation_id: int, signed_jwt: str) -> str:
    url = f"https://api.github.com/app/installations/{installation_id}/access_tokens"
    request = urllib.request.Request(
        url,
        method="POST",
        headers={
            "Authorization": f"Bearer {signed_jwt}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(request) as response:
            body = json.load(response)
    except urllib.error.HTTPError as error:
        sys.exit(f"GitHub rejected the token exchange ({error.code}): {error.read().decode()}")
    return body["token"]


def installation_covers_repo(installation_token: str, owner: str, repo: str) -> bool:
    """Is <owner>/<repo> in this installation's repository selection?

    PAGINATED, and the pagination is load-bearing: the API returns 30
    repositories per page and an installation on dozens of repositories
    answers its first page without this one. A truncated first page is
    exactly the misread already on #25's thread (correction comment,
    2026-09-02), read as "the App is not installed here" when it was.
    """
    wanted = f"{owner}/{repo}".lower()
    page = 1
    seen = 0
    while True:
        url = (
            "https://api.github.com/installation/repositories"
            f"?per_page=100&page={page}"
        )
        request = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {installation_token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        try:
            with urllib.request.urlopen(request) as response:
                body = json.load(response)
        except urllib.error.HTTPError as error:
            sys.exit(
                "GitHub rejected the installation-repositories read "
                f"({error.code}): {error.read().decode()}"
            )
        repositories = body.get("repositories") or []
        for entry in repositories:
            if (entry.get("full_name") or "").lower() == wanted:
                return True
        seen += len(repositories)
        total = body.get("total_count")
        if not repositories or (isinstance(total, int) and seen >= total):
            return False
        page += 1


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("persona", help="persona name, e.g. odyssey")
    parser.add_argument(
        "--require-repo",
        action="store_true",
        help="assert this App's installation covers this checkout's repository (#25, D4)",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="do everything and print nothing — an adapter's preflight",
    )
    args = parser.parse_args()

    authority = load_authority(args.persona, require_installation=True)
    private_key = load_private_key(authority["token"], authority["identity"])
    signed_jwt = mint_jwt(authority, private_key)
    installation_token = exchange_for_installation_token(authority["installation_id"], signed_jwt)

    if args.require_repo:
        owner, repo = get_repo_info()
        if not installation_covers_repo(installation_token, owner, repo):
            app = authority["identity"].removesuffix("[bot]")
            sys.exit(
                f"{args.persona}: the {app} installation does not cover {owner}/{repo}"
            )

    if args.quiet:
        return
    print(installation_token)


if __name__ == "__main__":
    main()
