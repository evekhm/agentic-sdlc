#!/usr/bin/env python3
"""Consensus ledger engine for scripts/ci/review_recorder.sh (#267, #291).

Usage:
  python3 scripts/ci/review_recorder.py <pr-number> <repo> <pr-json> <workdir> <recorder-login>

Parses review comments from Argus and Atlas, enforces provenance,
severity enum checks, failure-scenario demotions, and the round funnel,
and writes action_plan.json and new_body.md into <workdir>.
"""

import json
import re
import subprocess
import sys


def main():
    if len(sys.argv) < 6:
        print(f"Usage: {sys.argv[0]} <pr> <repo> <pr-json> <workdir> <recorder-login>", file=sys.stderr)
        sys.exit(1)

    pr = sys.argv[1]
    repo = sys.argv[2]
    pr_json_str = sys.argv[3]
    workdir = sys.argv[4]
    recorder_login = sys.argv[5]

    pr_data = json.loads(pr_json_str)
    pr_head = pr_data.get("headRefOid", "")

    current_labels = set()
    for l in pr_data.get("labels", []):
        if isinstance(l, dict) and "name" in l:
            current_labels.add(l["name"])

    existing_round_from_labels = 0
    existing_round_label = None
    for l in current_labels:
        if l in ("review:1", "review:2", "review:3"):
            existing_round_label = l
            existing_round_from_labels = max(existing_round_from_labels, int(l.split(":")[1]))

    valid_commits = set()
    for c in pr_data.get("commits", []):
        if isinstance(c, dict):
            sha = c.get("oid") or c.get("sha")
            if sha:
                valid_commits.add(sha)

    # If valid_commits is empty, query commits API
    if not valid_commits:
        try:
            res = subprocess.run(["gh", "api", "--paginate", "--slurp", f"repos/{repo}/pulls/{pr}/commits"], capture_output=True, text=True)
            if res.returncode == 0 and res.stdout.strip():
                raw_c_data = json.loads(res.stdout)
                c_data = []
                if isinstance(raw_c_data, list):
                    for item in raw_c_data:
                        if isinstance(item, list):
                            c_data.extend(item)
                        else:
                            c_data.append(item)
                for c in c_data:
                    if isinstance(c, dict):
                        sha = c.get("sha") or c.get("oid")
                        if sha:
                            valid_commits.add(sha)
        except Exception:
            pass

    if not pr_head and valid_commits:
        pr_head = list(valid_commits)[-1]

    # Fetch comments
    comments = []
    try:
        res = subprocess.run(["gh", "api", "--paginate", "--slurp", f"repos/{repo}/issues/{pr}/comments"], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            raw_comments = json.loads(res.stdout)
            if isinstance(raw_comments, list):
                for item in raw_comments:
                    if isinstance(item, list):
                        comments.extend(item)
                    else:
                        comments.append(item)
            elif isinstance(raw_comments, dict):
                comments = [raw_comments]
    except Exception as e:
        print(f"Error fetching comments: {e}", file=sys.stderr)

    # Identify existing Themis consensus ledger comment
    existing_comment_id = None
    existing_body = None
    prev_argus_head = None
    prev_atlas_head = None
    prev_ledger_round = 0
    initial_existing_row_ids = set()
    rows = {}  # fid -> {severity, status, peer}
    audit_notes = []
    refused_verdicts = {}  # (reviewer, reviewed_head) -> reason_code

    def record_refusal(reviewer, reviewed_head, reason, code):
        msg = f"refused: verdict block from @{reviewer}: {reason}"
        print(msg, file=sys.stderr)
        audit_notes.append(f"[{msg}]")
        if reviewed_head and re.match(r'^[0-9a-f]{40}$', reviewed_head):
            refused_verdicts[(reviewer, reviewed_head)] = code

    for c in comments:
        body = c.get("body", "")
        c_user = c.get("user", {})
        c_login = c_user.get("login", "")
        c_id = c.get("id")
        target_ledger_marker = f"<!-- consensus-ledger:{pr} -->"
        if target_ledger_marker in body:
            if c_login == recorder_login:
                if existing_comment_id is None:
                    existing_comment_id = c_id
                    existing_body = body
                else:
                    audit_notes.append(f"[ignored: ledger marker in comment {c_id} by @{c_login}]")
            else:
                audit_notes.append(f"[ignored: ledger marker in comment {c_id} by @{c_login}]")

    if existing_body:
        for line in existing_body.splitlines():
            line = line.strip()
            m_head = re.match(r'^<!-- reviewed-head:(argus|atlas):([0-9a-f]{40}) -->$', line)
            if m_head:
                if m_head.group(1) == "argus":
                    prev_argus_head = m_head.group(2)
                elif m_head.group(1) == "atlas":
                    prev_atlas_head = m_head.group(2)
            m_round = re.match(r'^<!-- round:([0-9]+) -->$', line)
            if m_round:
                prev_ledger_round = max(prev_ledger_round, int(m_round.group(1)))
            m_row = re.match(r'^<!-- ledger-row:([A-Za-z0-9@-]+):([A-Za-z0-9]+):([A-Za-z0-9]+):([A-Za-z0-9]+) -->$', line)
            if m_row:
                fid, sev, st, pr_val = m_row.groups()
                rows[fid] = {"severity": sev, "status": st, "peer": pr_val}
                initial_existing_row_ids.add(fid)
            m_refused = re.match(r'^<!-- refused-verdict:(argus|atlas):([0-9a-f]{40}):([a-z0-9-]+) -->$', line)
            if m_refused:
                r_rev, r_sha, r_code = m_refused.groups()
                refused_verdicts[(r_rev, r_sha)] = r_code

    prev_ledger_heads = {}
    if prev_argus_head:
        prev_ledger_heads["argus"] = prev_argus_head
    if prev_atlas_head:
        prev_ledger_heads["atlas"] = prev_atlas_head

    accepted_heads = dict(prev_ledger_heads)
    last_accepted_heads = {}

    run_cache = {}
    accepted_blocks_by_comment = {}
    max_accepted_head_round = 0
    verdict_blocks_found = 0

    # Pass 1: validate verdict blocks, update accepted heads, and compute max accepted round at current head
    for c_idx, c in enumerate(comments):
        body = c.get("body", "")
        user_obj = c.get("user", {})
        author_login = user_obj.get("login", "")

        # Check for structured review verdict block (finditer for multiple blocks, Smoke N5)
        v_matches = list(re.finditer(r'<!-- review-verdict:(argus|atlas):(clean|findings) -->(.*?)<!-- review-verdict-end -->', body, re.DOTALL))
        if not v_matches and re.search(r'<!-- review-verdict:(argus|atlas):(clean|findings) -->', body):
            verdict_blocks_found += 1
        for v_match in v_matches:
            verdict_blocks_found += 1
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
                record_refusal(reviewer, None, "missing reviewed-head marker", "missing-reviewed-head")
                continue
            reviewed_head = h_match.group(1)

            # Validate commit in PR history
            if reviewed_head not in valid_commits:
                record_refusal(reviewer, reviewed_head, f"commit {reviewed_head} not in pull request history", "commit-not-in-history")
                continue

            # Extract run-id
            r_match = re.search(r'<!-- run-id:([0-9]+) -->', block)
            if not r_match:
                record_refusal(reviewer, reviewed_head, "missing run-id marker", "missing-run-id")
                continue
            run_id = r_match.group(1)

            # Provenance check via GitHub Actions API
            if run_id not in run_cache:
                run_info = {}
                try:
                    run_res = subprocess.run(["gh", "api", f"repos/{repo}/actions/runs/{run_id}"], capture_output=True, text=True)
                    if run_res.returncode == 0 and run_res.stdout.strip():
                        run_info = json.loads(run_res.stdout)
                except Exception as e:
                    print(f"Error querying run {run_id}: {e}", file=sys.stderr)
                run_cache[run_id] = run_info
            run_info = run_cache[run_id]

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
                record_refusal(reviewer, reviewed_head, f"run {run_id} head_sha mismatch: expected {reviewed_head}, got {run_head_sha}", "run-head-sha-mismatch")
                continue
            if run_path != ".github/workflows/unattended.yml":
                record_refusal(reviewer, reviewed_head, f"run {run_id} workflow path mismatch: expected .github/workflows/unattended.yml, got {run_path}", "run-workflow-path-mismatch")
                continue
            if run_repo != repo:
                record_refusal(reviewer, reviewed_head, f"run {run_id} repository mismatch: expected {repo}, got {run_repo}", "run-repo-mismatch")
                continue
            if run_event not in ("pull_request", "workflow_dispatch"):
                record_refusal(reviewer, reviewed_head, f"run {run_id} event mismatch: event must be pull_request or workflow_dispatch, got {run_event}", "run-event-mismatch")
                continue

            # Terminal conclusion failure or cancelled causes withdrawal
            if run_status == "completed" and run_concl in ("failure", "cancelled"):
                record_refusal(reviewer, reviewed_head, f"run {run_id} ended {run_concl}; verdict withdrawn", "run-terminal-failure")
                audit_notes.append(f"[run {run_id} ended {run_concl}; verdict withdrawn]")
                if reviewer in last_accepted_heads and last_accepted_heads[reviewer] != reviewed_head:
                    accepted_heads[reviewer] = last_accepted_heads[reviewer]
                elif reviewer in prev_ledger_heads and prev_ledger_heads[reviewer] != reviewed_head:
                    accepted_heads[reviewer] = prev_ledger_heads[reviewer]
                else:
                    accepted_heads.pop(reviewer, None)
                continue

            # Provenance passed! Accept verdict block
            accepted_heads[reviewer] = reviewed_head
            last_accepted_heads[reviewer] = reviewed_head
            refused_verdicts.pop((reviewer, reviewed_head), None)

            # Extract round
            round_match = re.search(r'<!-- round:([0-9]+) -->', block)
            block_round = int(round_match.group(1)) if round_match else 1
            if reviewed_head == pr_head:
                max_accepted_head_round = max(max_accepted_head_round, block_round)

            if c_idx not in accepted_blocks_by_comment:
                accepted_blocks_by_comment[c_idx] = []
            accepted_blocks_by_comment[c_idx].append((reviewer, verdict, block, reviewed_head, block_round))

    effective_round = max(max_accepted_head_round, existing_round_from_labels, prev_ledger_round)

    # Pass 2: apply maintainer retiers and process findings in accepted blocks
    # D4: finding ids settled by an authorized maintainer retier in this run
    retiered_fids = set()
    for c_idx, c in enumerate(comments):
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
                if rsev not in ("security", "high", "normal", "suggestion"):
                    audit_notes.append(f"[refused: retier by @{author_login}: invalid severity {rsev}]")
                elif rfid in rows:
                    rows[rfid]["severity"] = rsev
                    audit_notes.append(f"[retiered to {rsev} by @{author_login}]")
                    retiered_fids.add(rfid)
            else:
                audit_notes.append(f"[refused: retier by @{author_login}: unauthorized]")

        # Process accepted verdict blocks for this comment
        for reviewer, verdict, block, reviewed_head, block_round in accepted_blocks_by_comment.get(c_idx, []):
            # Extract sibling failure scenarios
            failure_scenarios = set(re.findall(r'<!-- failure-scenario:([A-Za-z0-9@-]+) -->', block))
            failure_scenarios_base = {fs.split('@', 1)[0] for fs in failure_scenarios}

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
                    finding_round = effective_round

                # Check high failure scenario marker (D5) keyed on block: any high finding without sibling marker is demoted
                if fsev == "high" and fpr != "dispute" and fst != "withdrawn":
                    base_fid = fid.split('@', 1)[0]
                    if base_fid not in failure_scenarios_base:
                        fsev = "normal"
                        audit_notes.append(f"[demoted from high: missing failure_scenario marker] on {fid}")
                        print(f"finding {fid}: demoted from high to normal: missing failure_scenario marker")

                is_new = (fid not in initial_existing_row_ids and fid not in rows)

                if is_new:
                    # Post-cap funnel (D6): past round 3, admit only security findings
                    if effective_round >= 4:
                        if fsev != "security":
                            fsev = "normal"
                    elif effective_round in (2, 3):
                        # In rounds 2-3, new observations land as normal (D6).
                        # Earlier findings carried forward (e.g. R1-5 in round 2 per plan.md:150 and test_label_sync) keep recorded tier.
                        if finding_round >= effective_round:
                            if fsev == "suggestion":
                                fsev = "normal"
                                fpr = "none"

                # Determine discovering reviewer
                if fid.startswith("AT-"):
                    discoverer = "atlas"
                else:
                    discoverer = "argus"

                # D1: remember the recorded severity before this pass touches the row (None = new row)
                old_sev = rows[fid]["severity"] if fid in rows else None

                if fsev == "security":
                    if fid not in rows:
                        init_st = fst
                        if reviewer != discoverer and fst == "fixed":
                            init_st = "open"
                            audit_notes.append(f"[peer {reviewer} reported fixed on {fid}; status stays open until the discovering reviewer verifies]")
                        init_peer = "pending"
                        if reviewer != discoverer and fpr in ("agree", "dispute"):
                            init_peer = fpr
                        rows[fid] = {"severity": fsev, "status": init_st, "peer": init_peer}
                    else:
                        if reviewer == discoverer:
                            if rows[fid]["status"] != "fixed" and fst == "fixed":
                                rows[fid]["status"] = "fixed"
                                rows[fid]["peer"] = "pending"
                            else:
                                rows[fid]["status"] = fst
                        else:
                            if fst == "fixed" and rows[fid]["status"] == "open":
                                audit_notes.append(f"[peer {reviewer} reported fixed on {fid}; status stays open until the discovering reviewer verifies]")
                            if fpr == "agree":
                                if rows[fid]["status"] in ("fixed", "open"):
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

                # D1/D2/D4: the discovering reviewer may move a recorded finding's severity
                if old_sev is not None and reviewer == discoverer and fid not in retiered_fids:
                    # D4: Security tier protection against unilateral footer downgrades
                    if old_sev == "security" and fsev != "security":
                        print(f"finding {fid}: footer severity change from security to {fsev} ignored; security rows require maintainer retier")
                    else:
                        new_sev = fsev
                        # D2: Post-cap funnel rules: in round 4+, upward transition to high demoted to normal
                        if effective_round >= 4 and old_sev in ("normal", "suggestion") and new_sev == "high":
                            new_sev = "normal"
                        if old_sev != new_sev:
                            rows[fid]["severity"] = new_sev
                            audit_notes.append(f"[severity updated to {new_sev} by @{reviewer} on {fid}]")
                            print(f"finding {fid}: severity updated from {old_sev} to {new_sev} by @{reviewer}")
                            # D4: Non-security elevation to security requires peer confirmation
                            if new_sev == "security":
                                rows[fid]["peer"] = "pending"
                elif old_sev is not None and reviewer == discoverer and fid in retiered_fids:
                    # P4: an authorized maintainer retier is terminal for this finding id
                    print(f"finding {fid}: footer severity {fsev} ignored; retiered to {rows[fid]['severity']} by maintainer")

    if verdict_blocks_found == 0 and existing_comment_id is None:
        print(f"no verdict blocks on #{pr}, recorder writes nothing")
        sys.exit(0)

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
    for (r_rev, r_head), r_code in sorted(refused_verdicts.items()):
        lines.append(f"<!-- refused-verdict:{r_rev}:{r_head}:{r_code} -->")
    lines.append("<!-- consensus-ledger-end -->")
    lines.append("")

    # Format markdown table
    lines.append("| Finding ID | Severity | Status | Peer | Description / Notes |")
    lines.append("|---|---|---|---|---|")
    if not rows:
        lines.append("|_No findings recorded._|||||")
    else:
        for fid in sorted(rows.keys()):
            r = rows[fid]
            lines.append(f"| `{fid}` | `{r['severity']}` | `{r['status']}` | `{r['peer']}` | |")

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

    managed_labels = {
        "argus:findings", "argus:suggestions",
        "consensus:agreed", "consensus:pending", "consensus:disputed",
        "review:merge-ready", "review:verifying",
        "review:1", "review:2", "review:3"
    }

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
    existing_round_label = None
    existing_round_val = 0
    for l in current_labels:
        if l in ("review:1", "review:2", "review:3"):
            existing_round_label = l
            existing_round_val = int(l.split(":")[1])
            break

    if effective_round > 0:
        target_round = min(effective_round, 3)
        if target_round >= existing_round_val:
            round_label = f"review:{target_round}"
            desired_labels.add(round_label)
        else:
            desired_labels.add(existing_round_label)
    elif existing_round_label:
        desired_labels.add(existing_round_label)

    # Head-pinned labels: review:verifying & review:merge-ready
    # A ledger with no head marker gets neither review:verifying nor review:merge-ready (D8, REVIEW.md:373)
    if accepted_heads:
        argus_head = accepted_heads.get("argus")
        atlas_head = accepted_heads.get("atlas")

        # review:verifying requires open blocking rows AND at least one reviewer's accepted head behind current head
        at_least_one_behind = any(h != pr_head for h in accepted_heads.values())
        if open_blocking and at_least_one_behind:
            desired_labels.add("review:verifying")

        # review:merge-ready requires BOTH reviewers' accepted heads at current head with zero open blocking rows,
        # with the Atlas carry-forward branch matching merge_gate.sh:293-305
        reviewers_ok_for_merge = False
        if not open_blocking and not has_dispute and ("consensus:agreed" in desired_labels):
            if argus_head == pr_head and atlas_head == pr_head:
                reviewers_ok_for_merge = True
            elif argus_head == pr_head and atlas_head is not None:
                # Atlas carry-forward (D7):
                # (i) a verdict exists (atlas_head is not None)
                # (ii) no AT-* row open
                at_open = any(fid.startswith("AT-") and r["status"] == "open" for fid, r in rows.items())
                # (iii) no security row open or fixed without both AGREEs
                sec_unagreed = any(r["severity"] == "security" and (r["status"] == "open" or r["peer"] != "agree") for r in rows.values())
                # (iv) no dispute and no human mention naming Atlas after its last comment
                atlas_comments = [c for c in comments if c.get("user", {}).get("login") == "evekhm-atlas-app[bot]"]
                atlas_last_time = max([c.get("created_at", "") for c in atlas_comments], default="")
                mentions_atlas = False
                for c in comments:
                    if c.get("user", {}).get("type") != "Bot" and c.get("created_at", "") > atlas_last_time:
                        if "atlas" in c.get("body", "").lower():
                            mentions_atlas = True
                            break
                # (v) no unconsumed deep-review grant
                deep_review = ("deep-review" in current_labels)

                if not at_open and not sec_unagreed and not mentions_atlas and not deep_review:
                    reviewers_ok_for_merge = True

            if reviewers_ok_for_merge:
                desired_labels.add("review:merge-ready")

    to_add = sorted([l for l in desired_labels if l not in current_labels])
    to_remove = sorted([l for l in managed_labels if l in current_labels and l not in desired_labels])

    # Write action plan to files in workdir
    with open(f"{workdir}/new_body.md", "w") as f:
        f.write(new_body + "\n")

    action_plan = {
        "comment_action": comment_action,
        "existing_comment_id": existing_comment_id,
        "to_add": to_add,
        "to_remove": to_remove
    }
    with open(f"{workdir}/action_plan.json", "w") as f:
        json.dump(action_plan, f)


if __name__ == "__main__":
    main()
