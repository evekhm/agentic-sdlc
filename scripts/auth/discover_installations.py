#!/usr/bin/env python3
"""List a GitHub App's installations, to find its installation_id.

Run once per App, right after creating it and installing it on a
repo, to get the number that goes into that persona's
authority.installation_id in personas/<persona>.yaml:

    scripts/auth/discover_installations.py athena
"""

import argparse
import json
import sys
import urllib.error
import urllib.request

from _github_app import load_authority, load_private_key, mint_jwt


def list_installations(signed_jwt: str) -> list[dict]:
    request = urllib.request.Request(
        "https://api.github.com/app/installations",
        headers={
            "Authorization": f"Bearer {signed_jwt}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(request) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        sys.exit(f"GitHub rejected the request ({error.code}): {error.read().decode()}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("persona", help="persona name, e.g. athena")
    args = parser.parse_args()

    authority = load_authority(args.persona, require_installation=False)
    private_key = load_private_key(authority["token"], authority["identity"])
    signed_jwt = mint_jwt(authority, private_key)

    installations = list_installations(signed_jwt)
    if not installations:
        sys.exit("no installations found — install the App on a repo first")
    for install in installations:
        account = install["account"]["login"]
        selection = install["repository_selection"]
        print(f"installation_id={install['id']}  account={account}  repos={selection}")


if __name__ == "__main__":
    main()
