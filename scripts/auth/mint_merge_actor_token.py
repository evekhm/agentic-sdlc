#!/usr/bin/env python3
import json
import os
import sys
import time
import urllib.error
import urllib.request
import jwt

def main():
    app_id = os.environ.get("MERGE_ACTOR_APP_ID")
    private_key = os.environ.get("MERGE_ACTOR_APP_PRIVATE_KEY")
    repo = os.environ.get("GITHUB_REPOSITORY")
    if not app_id or not private_key or not repo:
        sys.exit(1)
        
    now = int(time.time())
    payload = {"iat": now - 60, "exp": now + (10 * 60), "iss": app_id}
    encoded_jwt = jwt.encode(payload, private_key, algorithm="RS256")
    
    # Get installation id for repo
    url = f"https://api.github.com/repos/{repo}/installation"
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {encoded_jwt}",
        "Accept": "application/vnd.github+json"
    })
    try:
        with urllib.request.urlopen(req) as resp:
            inst_id = json.load(resp)["id"]
    except urllib.error.HTTPError as error:
        sys.exit(f"Failed to get installation ID: {error.read().decode()}")
        
    # Get token
    url = f"https://api.github.com/app/installations/{inst_id}/access_tokens"
    req = urllib.request.Request(url, method="POST", headers={
        "Authorization": f"Bearer {encoded_jwt}",
        "Accept": "application/vnd.github+json"
    })
    try:
        with urllib.request.urlopen(req) as resp:
            token = json.load(resp)["token"]
    except urllib.error.HTTPError as error:
        sys.exit(f"Failed to get token: {error.read().decode()}")
        
    print(token)

if __name__ == "__main__":
    main()
