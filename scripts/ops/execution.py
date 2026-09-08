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
BINDING_KEYS = {"trigger", "events", "placement", "max_cost_usd"}


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
    unknown = sorted(set(loop) - {"autonomous_merge", "max_rung_dispatches_per_issue", "max_cost_usd_per_issue"})
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


def subscribers(config: dict, event: str) -> None:
    """`<persona>\t<placement>` per repo-event binding carrying `event`.

    The dispatcher's whole input. Sorted, so a workflow's step order is
    a property of the config and not of a dict's iteration order.
    """
    bindings = config.get("personas", {})
    for name in sorted(bindings):
        binding = bindings[name]
        if binding.get("trigger") != "repo-event":
            continue
        events = binding.get("events") or []
        if event in events:
            print(f"{name}\t{binding.get('placement')}")


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
    args = parser.parse_args()

    config = load()
    if args.check:
        check(config)
    elif args.subscribers:
        subscribers(config, args.subscribers)
    elif args.loop:
        loop_value(config, args.loop)
    else:
        binding_line(config, args.binding)


if __name__ == "__main__":
    main()
