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
"""

import argparse
import json
import sys
import urllib.error
import urllib.request

from _github_app import load_authority, load_private_key, mint_jwt


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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("persona", help="persona name, e.g. odyssey")
    args = parser.parse_args()

    authority = load_authority(args.persona, require_installation=True)
    private_key = load_private_key(authority["token"], authority["identity"])
    signed_jwt = mint_jwt(authority, private_key)
    installation_token = exchange_for_installation_token(authority["installation_id"], signed_jwt)
    print(installation_token)


if __name__ == "__main__":
    main()
