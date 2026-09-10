#!/usr/bin/env python3
"""The ONE parser of config/execution.yaml (#25, D2, D17).

    scripts/ops/execution.py --check
    scripts/ops/execution.py --subscribers <event>
    scripts/ops/execution.py --binding <persona>
    scripts/ops/execution.py --loop <key>

No adapter, workflow or shell script re-reads the YAML: a second reader
is a second schema, and the two drift silently. This deliberately does
NOT live in scripts/sync_agents.py — the compiler is harness-only and
carries no deployment-target knowledge (#25 comment 2026-09-02; D18),
and teaching it placement would break the separation D18 prices at one
line. `pyyaml` only, the compiler's whole dependency budget (#5, D10).
(D20 supersedes D12: loop limits are parsed here alongside bindings.)

--check is the gate (a fourth job in .github/workflows/ci-gates.yml):

  * the top level is a mapping whose only key is `personas:`;
  * every persona key names a personas/<name>.yaml whose kind is
    `persona`;
  * `trigger` is one of repo-event, scheduled, manual;
  * `events` is present and non-empty exactly when trigger is
    repo-event;
  * `max_cost_usd` is a positive number;
  * any other key in a binding is an error — an unread key is a
    commitment nobody honours;
  * every `placement` resolves to scripts/placement/<name>/run.sh
    (D17), and a name with no adapter directory fails with the error
    that names both;
  * when any binding is repo-event, .github/workflows/unattended.yml
    exists and its `on:` block lists every event any binding
    subscribes to. GitHub requires a static trigger list, so that
    duplication cannot be removed — this check turns it from a second
    source of truth into a derivation that cannot go stale.

Exit 0 and one PASS line means the file was read and every rule held.
Any finding prints `execution.yaml: <sentence>` and exits 1.
"""

import argparse
import sys
from pathlib import Path
from typing import NoReturn

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
EXECUTION_YAML = REPO_ROOT / "config" / "execution.yaml"
PERSONAS_DIR = REPO_ROOT / "personas"
PLACEMENT_DIR = REPO_ROOT / "scripts" / "placement"
UNATTENDED_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "unattended.yml"

TRIGGERS = ("repo-event", "scheduled", "manual", "ladder")
BINDING_KEYS = {"trigger", "events", "placement", "max_cost_usd", "assigned_when"}


def fail(message: str) -> NoReturn:
    """Every finding leaves through here, and nothing returns from it.

    NoReturn rather than None is load-bearing for a reader as well as a
    type checker: `load()` calls this instead of raising, so a checker
    told the call can return flags every value guarded by it as
    possibly unbound (#25, Argus R1-6 / Atlas AT-1).
    """
    sys.exit(f"execution.yaml: {message}")


def load() -> dict:
    """The parsed config mapping, or a named exit."""
    if not EXECUTION_YAML.is_file():
        fail(f"{EXECUTION_YAML.relative_to(REPO_ROOT)} does not exist")
    try:
        data = yaml.safe_load(EXECUTION_YAML.read_text())
    except yaml.YAMLError as error:
        fail(f"is not parseable YAML: {error}")
    if not isinstance(data, dict):
        fail("is not a mapping")
    unknown = sorted(set(data) - {"personas", "loop"})
    if unknown:
        fail(f"has unknown top-level key(s) {', '.join(unknown)}; only 'personas' and 'loop' are read")
    bindings = data.get("personas")
    if not isinstance(bindings, dict) or not bindings:
        fail("has no non-empty 'personas' mapping")
    for name, binding in bindings.items():
        if not isinstance(binding, dict):
            fail(f"persona '{name}' has no binding mapping")
    return data


def is_persona_source(name: str) -> bool:
    source = PERSONAS_DIR / f"{name}.yaml"
    if not source.is_file():
        return False
    try:
        data = yaml.safe_load(source.read_text())
    except yaml.YAMLError:
        return False
    return isinstance(data, dict) and data.get("kind") == "persona"


def get_known_status_labels() -> set:
    lifecycle_path = PERSONAS_DIR / "lifecycle.json"
    if lifecycle_path.is_file():
        try:
            import json
            data = json.loads(lifecycle_path.read_text())
            labels = {stage["label"] for stage in data.get("stages", []) if "label" in stage}
            if labels:
                return labels
        except Exception:
            pass
    return {"status:planning", "status:spec", "status:build", "status:implementing", "status:in-review"}


def path_matches_pattern(path_str: str, pattern: str) -> bool:
    import fnmatch
    from pathlib import PurePath
    if fnmatch.fnmatch(path_str, pattern):
        return True
    try:
        if PurePath(path_str).match(pattern):
            return True
    except Exception:
        pass
    return False


def matches_any_path_pattern(path_str: str, patterns: list) -> bool:
    for pat in patterns:
        if path_matches_pattern(path_str, pat):
            return True
    return False


def collect_paths(paths_args: list | None, paths_file: str | None) -> list:
    result: list = []
    if paths_args:
        result.extend(paths_args)
    if paths_file:
        pf = Path(paths_file)
        if pf.is_file():
            for line in pf.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    result.append(line)
    return result


def adapter_of(placement: str) -> Path:
    return PLACEMENT_DIR / placement / "run.sh"


def workflow_events() -> set:
    """Every event name under the workflow's `on:` block."""
    try:
        # `on:` is the YAML 1.1 boolean True once parsed; both spellings
        # are looked up so a quoted key reads the same way.
        data = yaml.safe_load(UNATTENDED_WORKFLOW.read_text())
    except (OSError, yaml.YAMLError) as error:
        fail(f"{UNATTENDED_WORKFLOW.relative_to(REPO_ROOT)} is not readable YAML: {error}")
    triggers = None
    if isinstance(data, dict):
        for key in (True, "on", "On", "ON"):
            if key in data:
                triggers = data[key]
                break
    if isinstance(triggers, dict):
        return set(triggers)
    if isinstance(triggers, list):
        return set(triggers)
    if isinstance(triggers, str):
        return {triggers}
    fail(f"{UNATTENDED_WORKFLOW.relative_to(REPO_ROOT)} has no readable 'on:' block")
    return set()  # unreachable; keeps the return type honest


def check(config: dict) -> None:
    bindings = config.get("personas", {})
    loop = config.get("loop")
    if loop is None:
        fail("config has no loop block; D20 requires one (#64)")
    if not isinstance(loop, dict):
        fail("loop block is not a mapping")
    unknown = sorted(set(loop) - {"autonomous_merge", "max_rung_dispatches_per_issue", "max_cost_usd_per_issue", "max_concurrent_first_hops"})
    if unknown:
        fail(f"loop block has unknown key(s) {', '.join(unknown)}")
    if not isinstance(loop.get("autonomous_merge"), bool):
        fail("loop.autonomous_merge must be a boolean")
    mrd = loop.get("max_rung_dispatches_per_issue")
    if isinstance(mrd, bool) or not isinstance(mrd, int) or mrd <= 0:
        fail("loop.max_rung_dispatches_per_issue must be positive integer")
    mcu = loop.get("max_cost_usd_per_issue")
    if isinstance(mcu, bool) or not isinstance(mcu, (int, float)) or mcu <= 0:
        fail("loop.max_cost_usd_per_issue must be a positive number")
    mcfh = loop.get("max_concurrent_first_hops")
    if mcfh is not None:
        if isinstance(mcfh, bool) or not isinstance(mcfh, int) or mcfh <= 0:
            fail("loop.max_concurrent_first_hops must be positive integer")


    subscribed = set()
    for name in sorted(bindings):
        binding = bindings[name]
        if not is_persona_source(name):
            fail(
                f"persona '{name}' has no personas/{name}.yaml of kind: persona; "
                "a binding for a persona that does not exist can never run"
            )
        unknown = sorted(set(binding) - BINDING_KEYS)
        if unknown:
            fail(
                f"persona '{name}' has unknown key(s) {', '.join(unknown)}; "
                f"the binding keys are {', '.join(sorted(BINDING_KEYS))}"
            )

        trigger = binding.get("trigger")
        if trigger not in TRIGGERS:
            fail(
                f"persona '{name}' has trigger {trigger!r}, which is not one of "
                f"{', '.join(TRIGGERS)}"
            )

        events = binding.get("events")
        if trigger == "repo-event":
            if not isinstance(events, list) or not events:
                fail(
                    f"persona '{name}' is trigger: repo-event and must carry a non-empty "
                    "'events' list naming the GitHub events it wakes on"
                )
            for event in events:
                if not isinstance(event, str) or not event:
                    fail(f"persona '{name}' has a non-string event in its 'events' list")
            subscribed.update(events)
        elif events is not None:
            fail(
                f"persona '{name}' is trigger: {trigger} and carries 'events'; "
                "only repo-event subscribes to an event"
            )

        assigned_when = binding.get("assigned_when")
        if assigned_when is not None:
            if trigger != "repo-event" or "pull_request" not in (events or []):
                fail(
                    f"ERROR: assigned_when allowed only for pull_request repo-events; "
                    f"persona '{name}' has trigger '{trigger}' and events {events}"
                )
            if not isinstance(assigned_when, dict):
                fail(f"ERROR: persona '{name}' assigned_when must be a mapping")
            allowed_aw_keys = {"status_labels", "paths", "labels", "open_ledger_tiers"}
            unknown_aw = sorted(set(assigned_when) - allowed_aw_keys)
            if unknown_aw:
                fail(f"ERROR: unknown key in assigned_when: {', '.join(unknown_aw)}")
            if "status_labels" in assigned_when:
                sl = assigned_when["status_labels"]
                if not isinstance(sl, list):
                    fail("ERROR: status_labels in assigned_when must be a list")
                known_labels = get_known_status_labels()
                for label in sl:
                    if label not in known_labels:
                        fail(f"ERROR: unknown status label: {label}")
            if "open_ledger_tiers" in assigned_when:
                olt = assigned_when["open_ledger_tiers"]
                if not isinstance(olt, list):
                    fail("ERROR: open_ledger_tiers in assigned_when must be a list")
                allowed_tiers = {"security", "high", "normal", "suggestion"}
                for tier in olt:
                    if tier not in allowed_tiers:
                        fail(f"ERROR: unknown severity tier: {tier}")
            if "paths" in assigned_when:
                paths_list = assigned_when["paths"]
                if not isinstance(paths_list, list):
                    fail("ERROR: paths in assigned_when must be a list")
                for p in paths_list:
                    if not isinstance(p, str) or not p:
                        fail(f"ERROR: invalid path pattern in assigned_when: {p!r}")
            if "labels" in assigned_when:
                labels_list = assigned_when["labels"]
                if not isinstance(labels_list, list):
                    fail("ERROR: labels in assigned_when must be a list")
                for l in labels_list:
                    if not isinstance(l, str) or not l:
                        fail(f"ERROR: invalid label in assigned_when: {l!r}")

        # Declared, not enforced (Argus R1-4): this gate checks the
        # number is sane and the adapter prints it, so the budget is
        # stated once and legible in the run log. Nothing meters spend
        # against it yet — D8's enforcement half needs a spend reading
        # the harness does not expose. `budget`, not `cap`, so the name
        # does not promise what the code does not do.
        budget = binding.get("max_cost_usd")
        if isinstance(budget, bool) or not isinstance(budget, (int, float)) or budget <= 0:
            fail(f"persona '{name}' has max_cost_usd {budget!r}, which is not a positive number")

        placement = binding.get("placement")
        if not isinstance(placement, str) or not placement:
            fail(f"persona '{name}' names no placement")
        if not adapter_of(placement).is_file():
            # D17's named error, verbatim: reserving a name must not
            # become a way to ship a binding that cannot run.
            fail(
                f"persona '{name}' names placement '{placement}', which has no adapter "
                f"directory scripts/placement/{placement}/"
            )

    if subscribed:
        if not UNATTENDED_WORKFLOW.is_file():
            fail(
                "a repo-event binding needs .github/workflows/unattended.yml to capture "
                f"the event; it does not exist (events subscribed: {', '.join(sorted(subscribed))})"
            )
        captured = workflow_events()
        missing = sorted(subscribed - captured)
        if missing:
            fail(
                f".github/workflows/unattended.yml does not trigger on "
                f"{', '.join(missing)}, which a repo-event binding subscribes to; "
                "the workflow's on: block must list every subscribed event"
            )

    print(
        f"PASS: execution gate green ({len(bindings)} binding(s), "
        f"{len(subscribed)} subscribed event(s), every placement resolves to an adapter)."
    )


def subscribers(
    config: dict,
    event: str,
    status_label: str | None = None,
    paths: list | None = None,
    labels: list | None = None,
    open_ledger: list | None = None,
    action: str | None = None,
    draft: bool = False,
) -> None:
    """`<persona>\t<placement>` per repo-event binding carrying `event`.

    The dispatcher's whole input. Sorted, so a workflow's step order is
    a property of the config and not of a dict's iteration order.
    """
    if draft:
        return

    paths = paths or []
    labels = labels or []
    open_ledger = open_ledger or []
    known_labels = get_known_status_labels()

    bindings = config.get("personas", {})
    for name in sorted(bindings):
        binding = bindings[name]
        if binding.get("trigger") != "repo-event":
            continue
        events = binding.get("events") or []
        if event not in events:
            continue

        assigned_when = binding.get("assigned_when")
        if assigned_when is None:
            # Unconditional subscriber (e.g. atlas)
            print(f"{name}\t{binding.get('placement')}")
            continue

        # Conditional subscriber (e.g. argus)
        # 1. Missing or unresolvable status label fails closed to dual assignment (AT-11)
        if not status_label or status_label not in known_labels:
            print(f"{name}\t{binding.get('placement')}")
            continue

        # 2. Status label matches assigned_when.status_labels (AT-4)
        aw_status_labels = assigned_when.get("status_labels", [])
        if status_label in aw_status_labels:
            print(f"{name}\t{binding.get('placement')}")
            continue

        # 3. Path matches any assigned_when.paths pattern (AT-5)
        aw_paths = assigned_when.get("paths", [])
        if any(matches_any_path_pattern(p, aw_paths) for p in paths):
            print(f"{name}\t{binding.get('placement')}")
            continue

        # 4. Label matches assigned_when.labels (AT-6)
        aw_labels = assigned_when.get("labels", [])
        if any(l in aw_labels for l in labels):
            print(f"{name}\t{binding.get('placement')}")
            continue

        # 5. Open ledger tier matches assigned_when.open_ledger_tiers (AT-7)
        aw_tiers = assigned_when.get("open_ledger_tiers", [])
        if any(t in aw_tiers for t in open_ledger):
            print(f"{name}\t{binding.get('placement')}")
            continue


def check_grant(pr: str | None, rung: str | None, existing_grants: list | None = None) -> None:
    if not pr or not rung:
        fail("--check-grant requires --pr and --rung")
    existing: list = []
    if existing_grants:
        for item in existing_grants:
            for part in item.replace(",", " ").split():
                existing.append(part.strip())
    if rung in existing:
        sys.exit(
            f"Refused: PR #{pr} already received a deep-review grant on the '{rung}' rung. "
            f"Policy allows at most one deep-review grant per PR per rung (REVIEW.md, #265). "
            f"Escalating to human."
        )


def diff_rules(
    config: dict,
    lines: int | None = None,
    files: int | None = None,
    paths: list | None = None,
) -> None:
    paths = paths or []
    # DEEP-2: Lines > 400 or Files > 12
    if lines is not None and lines > 400:
        print("deep-review")
        return
    if (files is not None and files > 12) or len(paths) > 12:
        print("deep-review")
        return

    # DEEP-1: Trust-bearing paths
    tb_patterns = [
        ".github/workflows/**",
        "scripts/auth/**",
        "scripts/ops/**",
        "scripts/ci/**",
        "scripts/sync_agents.py",
        "scripts/setup/**",
        "personas/**",
        "config/**",
        "REVIEW.md",
        "AGENTS.md",
    ]
    argus_aw = config.get("personas", {}).get("argus", {}).get("assigned_when", {})
    if isinstance(argus_aw, dict) and "paths" in argus_aw and isinstance(argus_aw["paths"], list):
        tb_patterns = argus_aw["paths"]

    if any(matches_any_path_pattern(p, tb_patterns) for p in paths):
        print("deep-review")
        return


def binding_line(config: dict, persona: str) -> None:
    """`trigger placement max_cost_usd`, for an adapter's report line."""
    bindings = config.get("personas", {})
    binding = bindings.get(persona)
    if binding is None:
        fail(f"persona '{persona}' has no execution binding")
    print(f"{binding.get('trigger')} {binding.get('placement')} {binding.get('max_cost_usd')}")


def loop_value(config: dict, key: str) -> None:
    loop = config.get("loop")
    if loop is None:
        fail("config has no loop block")
    if key not in loop:
        fail(f"loop block has no key '{key}'")
    val = loop[key]
    if isinstance(val, bool):
        print("true" if val else "false")
    else:
        print(val)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="validate the file; the CI gate")
    mode.add_argument("--subscribers", metavar="EVENT", help="repo-event bindings for EVENT")
    mode.add_argument("--binding", metavar="PERSONA", help="one persona's binding, one line")
    mode.add_argument("--loop", metavar="KEY", help="print a value from the loop block")
    mode.add_argument("--check-grant", action="store_true", help="validate deep-review grant cap")
    mode.add_argument("--diff-rules", action="store_true", help="evaluate diff thresholds and trust-bearing paths")

    # Options for --subscribers and --diff-rules
    parser.add_argument("--status-label", help="status:* label on the PR or linked issue")
    parser.add_argument("--paths", nargs="*", default=[], help="paths touched")
    parser.add_argument("--paths-file", help="file containing touched paths")
    parser.add_argument("--labels", nargs="*", default=[], help="labels present on the PR")
    parser.add_argument("--open-ledger", nargs="*", default=[], help="open ledger severity tiers")
    parser.add_argument("--action", help="workflow pull_request action")
    parser.add_argument("--draft", action="store_true", help="PR is a draft")

    # Options for --check-grant
    parser.add_argument("--pr", help="pull request number for grant check")
    parser.add_argument("--rung", help="current lifecycle rung for grant check")
    parser.add_argument("--existing-grants", nargs="*", default=[], help="rungs where grant was already given")

    # Options for --diff-rules
    parser.add_argument("--lines", type=int, help="lines changed")
    parser.add_argument("--files", type=int, help="files changed")

    args = parser.parse_args()

    config = load()
    if args.check:
        check(config)
    elif args.subscribers:
        all_paths = collect_paths(args.paths, args.paths_file)
        subscribers(
            config,
            args.subscribers,
            status_label=args.status_label,
            paths=all_paths,
            labels=args.labels,
            open_ledger=args.open_ledger,
            action=args.action,
            draft=args.draft,
        )
    elif args.check_grant:
        check_grant(pr=args.pr, rung=args.rung, existing_grants=args.existing_grants)
    elif args.diff_rules:
        all_paths = collect_paths(args.paths, args.paths_file)
        diff_rules(config, lines=args.lines, files=args.files, paths=all_paths)
    elif args.loop:
        loop_value(config, args.loop)
    else:
        binding_line(config, args.binding)


if __name__ == "__main__":
    main()
