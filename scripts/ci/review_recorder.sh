#!/usr/bin/env bash
# scripts/ci/review_recorder.sh - Consensus ledger recorder (#267)
#
# Usage: scripts/ci/review_recorder.sh <pr-number>
#
# Derives and maintains the consensus ledger comment and pull request labels
# from structured review verdicts posted by Argus and Atlas.

set -euo pipefail

PR="${1:-}"
if [ -z "$PR" ]; then
  echo "Usage: $0 <pr-number>" >&2
  exit 1
fi

# Guard 1 (D1): Skip execution entirely when sender is Themis App
if [ "${GITHUB_EVENT_SENDER_LOGIN:-}" = "evekhm-themis-app[bot]" ]; then
  exit 0
fi

# Resolve repository
REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
  REPO="$(git config --get remote.origin.url | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#' || true)"
fi
REPO="${REPO:-evekhm/agentic-sdlc}"
export GITHUB_REPOSITORY="$REPO"

# Token setup
export GH_TOKEN="${THEMIS_TOKEN:-${GITHUB_TOKEN:-}}"

# Query pull request info
PR_JSON="$(gh pr view "$PR" --json number,labels,closingIssuesReferences,body,headRefOid,commits 2>/dev/null || true)"
if [ -z "$PR_JSON" ]; then
  echo "Failed to retrieve pull request #$PR" >&2
  exit 1
fi

# Guard 2 (D11, #291): Circuit breaker on hold
# Check PR itself
if echo "$PR_JSON" | jq -e '.labels[]? | select(.name == "hold")' >/dev/null 2>&1; then
  echo "hold present on #$PR, recorder writes nothing"
  exit 0
fi

# Check closing issues
CLOSING_ISSUES="$(echo "$PR_JSON" | jq -r '(.closingIssuesReferences[]?.number // empty)')"
BODY_CLOSING="$(echo "$PR_JSON" | jq -r '.body // ""' | grep -oEi '(closes|fixes|resolves) #[0-9]+' | grep -oE '[0-9]+' || true)"
ALL_CLOSING="$(printf '%s\n%s\n' "$CLOSING_ISSUES" "$BODY_CLOSING" | sort -u | grep -E '^[0-9]+$' || true)"

for iss in $ALL_CLOSING; do
  iss_json="$(gh issue view "$iss" --json labels 2>/dev/null || true)"
  if echo "$iss_json" | jq -e '.labels[]? | select(.name == "hold")' >/dev/null 2>&1; then
    echo "hold present on #$iss, recorder writes nothing"
    exit 0
  fi
done

# Run the python engine to derive ledger state and actions
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

python3 - "$PR" "$REPO" "$PR_JSON" "$TMPDIR" <<'PYEOF'
import sys
import json
import re
import subprocess

pr = sys.argv[1]
repo = sys.argv[2]
pr_json_str = sys.argv[3]
tmpdir = sys.argv[4]

pr_data = json.loads(pr_json_str)
pr_head = pr_data.get("headRefOid", "")
valid_commits = set()
for c in pr_data.get("commits", []):
    if isinstance(c, dict) and "sha" in c:
        valid_commits.add(c["sha"])

# If valid_commits is empty, query commits API
if not valid_commits:
    try:
        res = subprocess.run(["gh", "api", f"repos/{repo}/pulls/{pr}/commits"], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            c_data = json.loads(res.stdout)
            for c in c_data:
                if isinstance(c, dict) and "sha" in c:
                    valid_commits.add(c["sha"])
    except Exception:
        pass

if not pr_head and valid_commits:
    pr_head = list(valid_commits)[-1]

# Fetch comments
comments = []
try:
    res = subprocess.run(["gh", "api", f"repos/{repo}/issues/{pr}/comments"], capture_output=True, text=True)
    if res.returncode == 0 and res.stdout.strip():
        comments = json.loads(res.stdout)
        if not isinstance(comments, list):
            comments = [comments]
except Exception as e:
    print(f"Error fetching comments: {e}", file=sys.stderr)

# Identify existing Themis consensus ledger comment
existing_comment_id = None
existing_body = None
prev_argus_head = None
prev_atlas_head = None
initial_existing_row_ids = set()
rows = {}  # fid -> {severity, status, peer}
audit_notes = []

for c in comments:
    body = c.get("body", "")
    if f"<!-- consensus-ledger:{pr} -->" in body or "<!-- consensus-ledger:" in body:
        existing_comment_id = c.get("id")
        existing_body = body
        break

if existing_body:
    for line in existing_body.splitlines():
        line = line.strip()
        m_head = re.match(r'^<!-- reviewed-head:(argus|atlas):([0-9a-f]{40}) -->$', line)
        if m_head:
            if m_head.group(1) == "argus":
                prev_argus_head = m_head.group(2)
            elif m_head.group(1) == "atlas":
                prev_atlas_head = m_head.group(2)
        m_row = re.match(r'^<!-- ledger-row:([A-Za-z0-9@-]+):([A-Za-z0-9]+):([A-Za-z0-9]+):([A-Za-z0-9]+) -->$', line)
        if m_row:
            fid, sev, st, pr_val = m_row.groups()
            rows[fid] = {"severity": sev, "status": st, "peer": pr_val}
            initial_existing_row_ids.add(fid)

accepted_heads = {}
last_accepted_heads = {}
if prev_argus_head:
    accepted_heads["argus"] = prev_argus_head
    last_accepted_heads["argus"] = prev_argus_head
if prev_atlas_head:
    accepted_heads["atlas"] = prev_atlas_head
    last_accepted_heads["atlas"] = prev_atlas_head

max_round = 1

# Process comments in chronological order
for c in comments:
    body = c.get("body", "")
    user_obj = c.get("user", {})
    author_login = user_obj.get("login", "")
    author_assoc = c.get("author_association", "")
    user_type = user_obj.get("type", "")

    # Check for maintainer retier directives
    retier_matches = list(re.finditer(r'@(?:argus|atlas)\s+retier\s+([A-Za-z0-9@-]+)\s+([a-zA-Z0-9]+)', body))
    for rm in retier_matches:
        rfid = rm.group(1)
        rsev = rm.group(2)
        is_authorized = (author_assoc in ("OWNER", "MEMBER", "COLLABORATOR") and user_type != "Bot")
        if is_authorized:
            if rfid in rows:
                rows[rfid]["severity"] = rsev
                audit_notes.append(f"[retiered to {rsev} by @{author_login}]")
        else:
            audit_notes.append(f"[refused: retier by @{author_login}: unauthorized]")

    # Check for structured review verdict block
    v_match = re.search(r'<!-- review-verdict:(argus|atlas):(clean|findings) -->(.*?)<!-- review-verdict-end -->', body, re.DOTALL)
    if not v_match:
        continue

    reviewer = v_match.group(1)
    verdict = v_match.group(2)
    block = v_match.group(0)

    # Validate author login
    expected_login = f"evekhm-{reviewer}-app[bot]"
    if author_login != expected_login:
        audit_notes.append(f"[refused: verdict block author {author_login} does not match {expected_login}]")
        continue

    # Extract reviewed-head
    h_match = re.search(r'<!-- reviewed-head:([0-9a-f]{40}) -->', block)
    if not h_match:
        audit_notes.append(f"[refused: verdict block from @{reviewer}: missing reviewed-head marker]")
        continue
    reviewed_head = h_match.group(1)

    # Validate commit in PR history
    if reviewed_head not in valid_commits:
        print(f"refused: verdict block from @{reviewer}: commit {reviewed_head} not in pull request history", file=sys.stderr)
        audit_notes.append(f"[refused: verdict block from @{reviewer}: commit {reviewed_head} not in pull request history]")
        continue

    # Extract run-id
    r_match = re.search(r'<!-- run-id:([0-9]+) -->', block)
    if not r_match:
        audit_notes.append(f"[refused: verdict block from @{reviewer}: missing run-id marker]")
        continue
    run_id = r_match.group(1)

    # Provenance check via GitHub Actions API
    run_info = {}
    try:
        run_res = subprocess.run(["gh", "api", f"repos/{repo}/actions/runs/{run_id}"], capture_output=True, text=True)
        if run_res.returncode == 0 and run_res.stdout.strip():
            run_info = json.loads(run_res.stdout)
    except Exception as e:
        print(f"Error querying run {run_id}: {e}", file=sys.stderr)

    run_head_sha = run_info.get("head_sha", "")
    run_path = run_info.get("path", "")
    run_repo = run_info.get("head_repository", {}).get("full_name", "")
    run_event = run_info.get("event", "")
    run_status = run_info.get("status", "")
    run_concl = run_info.get("conclusion")
    if run_concl is None or run_concl == "null":
        run_concl = None

    # Check 4 provenance predicates
    if run_head_sha != reviewed_head:
        audit_notes.append(f"[refused: run {run_id} head_sha mismatch: expected {reviewed_head}, got {run_head_sha}]")
        continue
    if run_path != ".github/workflows/unattended.yml":
        audit_notes.append(f"[refused: run {run_id} workflow path mismatch: expected .github/workflows/unattended.yml, got {run_path}]")
        continue
    if run_repo != repo:
        audit_notes.append(f"[refused: run {run_id} repository mismatch: expected {repo}, got {run_repo}]")
        continue
    if run_event not in ("pull_request", "workflow_dispatch"):
        audit_notes.append(f"[refused: run {run_id} event mismatch: event must be pull_request or workflow_dispatch, got {run_event}]")
        continue

    # Terminal conclusion failure or cancelled causes withdrawal
    if run_status == "completed" and run_concl in ("failure", "cancelled"):
        audit_notes.append(f"[run {run_id} ended {run_concl}; verdict withdrawn]")
        if reviewer in last_accepted_heads:
            accepted_heads[reviewer] = last_accepted_heads[reviewer]
        else:
            accepted_heads.pop(reviewer, None)
        continue

    # Provenance passed! Accept verdict block
    accepted_heads[reviewer] = reviewed_head
    last_accepted_heads[reviewer] = reviewed_head

    # Extract round
    round_match = re.search(r'<!-- round:([0-9]+) -->', block)
    block_round = int(round_match.group(1)) if round_match else 1
    max_round = max(max_round, block_round)

    # Extract sibling failure scenarios
    failure_scenarios = set(re.findall(r'<!-- failure-scenario:([A-Za-z0-9@-]+) -->', block))

    # Parse finding lines
    finding_matches = re.finditer(r'<!-- finding:([A-Za-z0-9@-]+):([A-Za-z0-9]+):([A-Za-z0-9]+):([A-Za-z0-9]+) -->', block)
    for fm in finding_matches:
        fid = fm.group(1)
        fsev = fm.group(2)
        fst = fm.group(3)
        fpr = fm.group(4)

        # Validate severity enum
        if fsev not in ("security", "high", "normal", "suggestion"):
            print(f"finding {fid}: severity {fsev} is not one of security|high|normal|suggestion")
            audit_notes.append(f"[refused: {fid}: invalid severity {fsev}]")
            continue

        # Determine finding round
        m_r = re.match(r'^(?:AT-)?R([0-9]+)-', fid)
        if m_r:
            finding_round = int(m_r.group(1))
        else:
            finding_round = block_round

        # Check high failure scenario marker
        if fsev == "high" and finding_round == block_round and fpr != "dispute" and fst != "withdrawn":
            if fid not in failure_scenarios:
                fsev = "normal"
                audit_notes.append("[demoted from high: missing failure_scenario marker]")

        is_new = (fid not in initial_existing_row_ids and fid not in rows)

        if is_new:
            if finding_round in (2, 3):
                if fsev == "suggestion":
                    fsev = "normal"
                    fpr = "none"
            elif finding_round >= 4:
                if fsev != "security":
                    fsev = "normal"

        # Determine discovering reviewer
        if fid.startswith("AT-"):
            discoverer = "atlas"
        else:
            discoverer = "argus"

        if fsev == "security":
            if fid not in rows:
                rows[fid] = {"severity": fsev, "status": fst, "peer": "pending"}
            else:
                if reviewer == discoverer:
                    rows[fid]["status"] = fst
                else:
                    if fpr == "agree":
                        if fst == "fixed" or rows[fid]["status"] == "fixed":
                            rows[fid]["status"] = "fixed"
                            rows[fid]["peer"] = "agree"
                        elif rows[fid]["status"] == "open":
                            rows[fid]["peer"] = "agree"
                    elif fpr == "dispute":
                        rows[fid]["peer"] = "dispute"
        else:
            if fid not in rows:
                rows[fid] = {"severity": fsev, "status": fst, "peer": fpr if fpr == "dispute" else "none"}
            else:
                if reviewer == discoverer:
                    rows[fid]["status"] = fst
                if fpr == "dispute":
                    rows[fid]["peer"] = "dispute"

# Build new consensus ledger comment body
lines = [
    f"### Findings ledger for #{pr}",
    f"<!-- consensus-ledger:{pr} -->",
    "<!-- assigned:argus,atlas -->"
]
if "argus" in accepted_heads:
    lines.append(f"<!-- reviewed-head:argus:{accepted_heads['argus']} -->")
if "atlas" in accepted_heads:
    lines.append(f"<!-- reviewed-head:atlas:{accepted_heads['atlas']} -->")
for fid in sorted(rows.keys()):
    r = rows[fid]
    lines.append(f"<!-- ledger-row:{fid}:{r['severity']}:{r['status']}:{r['peer']} -->")
lines.append("<!-- consensus-ledger-end -->")
lines.append("")

if rows:
    lines.append("| Finding ID | Severity | Status | Peer |")
    lines.append("| --- | --- | --- | --- |")
    for fid in sorted(rows.keys()):
        r = rows[fid]
        lines.append(f"| {fid} | {r['severity']} | {r['status']} | {r['peer']} |")
else:
    lines.append("_No findings recorded._")

# Deduplicate audit notes
unique_notes = []
seen_notes = set()
for n in audit_notes:
    if n not in seen_notes:
        seen_notes.add(n)
        unique_notes.append(n)

if unique_notes:
    lines.append("")
    lines.append("#### Notes")
    for n in unique_notes:
        lines.append(f"- {n}")

new_body = "\n".join(lines).rstrip("\r\n")

# Determine comment write action (POST, PATCH, or NONE)
comment_action = "NONE"
if existing_comment_id:
    if existing_body.rstrip("\r\n") != new_body:
        comment_action = "PATCH"
else:
    comment_action = "POST"

# Calculate derived labels
desired_labels = set()

# argus:findings & argus:suggestions
open_blocking = any(r["status"] == "open" and r["severity"] in ("security", "high") for r in rows.values())
open_non_blocking = any(r["status"] == "open" and r["severity"] in ("normal", "suggestion") for r in rows.values())

if open_blocking:
    desired_labels.add("argus:findings")
if open_non_blocking:
    desired_labels.add("argus:suggestions")

# Consensus axis
has_dispute = any(r["severity"] in ("security", "high") and r["peer"] == "dispute" for r in rows.values())
if has_dispute:
    desired_labels.add("consensus:disputed")
else:
    security_pending = any(r["severity"] == "security" and r["peer"] == "pending" for r in rows.values())
    if security_pending:
        desired_labels.add("consensus:pending")
    else:
        if accepted_heads or rows:
            desired_labels.add("consensus:agreed")

# Round labels
if max_round >= 3:
    desired_labels.add("review:3")
elif max_round == 2:
    desired_labels.add("review:2")
elif max_round == 1:
    desired_labels.add("review:1")

# review:verifying & review:merge-ready
argus_head = accepted_heads.get("argus")
reviewed_head_matches = (argus_head is not None and argus_head == pr_head)

if open_blocking and not reviewed_head_matches:
    desired_labels.add("review:verifying")

if not open_blocking and ("consensus:agreed" in desired_labels) and reviewed_head_matches and not has_dispute:
    desired_labels.add("review:merge-ready")

# Fetch current labels on PR
current_labels = set()
for l in pr_data.get("labels", []):
    if isinstance(l, dict) and "name" in l:
        current_labels.add(l["name"])

managed_labels = {
    "argus:findings", "argus:suggestions",
    "consensus:agreed", "consensus:pending", "consensus:disputed",
    "review:merge-ready", "review:verifying",
    "review:1", "review:2", "review:3"
}

to_add = sorted([l for l in desired_labels if l not in current_labels])
to_remove = sorted([l for l in managed_labels if l in current_labels and l not in desired_labels])

# Write action plan to files in tmpdir
with open(f"{tmpdir}/new_body.md", "w") as f:
    f.write(new_body + "\n")

action_plan = {
    "comment_action": comment_action,
    "existing_comment_id": existing_comment_id,
    "to_add": to_add,
    "to_remove": to_remove
}
with open(f"{tmpdir}/action_plan.json", "w") as f:
    json.dump(action_plan, f)
PYEOF

# Read action plan
PLAN_JSON="$TMPDIR/action_plan.json"
COMMENT_ACTION="$(jq -r '.comment_action' "$PLAN_JSON")"
COMMENT_ID="$(jq -r '.existing_comment_id // empty' "$PLAN_JSON")"
TO_ADD="$(jq -r '.to_add | join(",")' "$PLAN_JSON")"
TO_REMOVE="$(jq -r '.to_remove | join(",")' "$PLAN_JSON")"

if [ "${DRY_RUN:-0}" != "1" ]; then
  # Execute comment write if needed
  if [ "$COMMENT_ACTION" = "POST" ]; then
    gh api -X POST "repos/$REPO/issues/$PR/comments" -F "body=@$TMPDIR/new_body.md"
  elif [ "$COMMENT_ACTION" = "PATCH" ] && [ -n "$COMMENT_ID" ]; then
    gh api -X PATCH "repos/$REPO/issues/comments/$COMMENT_ID" -F "body=@$TMPDIR/new_body.md"
  fi

  # Execute label updates if needed
  EDIT_ARGS=()
  [ -n "$TO_ADD" ] && EDIT_ARGS+=(--add-label "$TO_ADD")
  [ -n "$TO_REMOVE" ] && EDIT_ARGS+=(--remove-label "$TO_REMOVE")
  if [ "${#EDIT_ARGS[@]}" -gt 0 ]; then
    gh issue edit "$PR" "${EDIT_ARGS[@]}"
  fi
fi

exit 0
