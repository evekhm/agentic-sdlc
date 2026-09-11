#!/usr/bin/env python3
"""Contract test suite for commands compiler and cross-harness targets (#416).

Validates Decisions D1-D14 and Acceptance Tests AT-416-1 through AT-416-13 from
intent/416-commands-work-idea-bug/spec.md.

At the build rung (Daedalus), before Odyssey implements the compiler, canonical
sources, and target emissions, running this contract suite reports clean
failures on all unimplemented contracts and exits with code 1 (failures > 0,
errors == 0). During the implement rung (Odyssey), once all components are
implemented, all contract assertions pass green and this suite exits with code 0.

Usage:
  python3 scripts/ci/tests/sync_commands_test.py
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent


class SyncCommandsContractTest(unittest.TestCase):
    """Contract assertions covering Decisions D1 through D14 and AT-416-1 through AT-416-13."""

    def test_d1_d14_at_416_1_canonical_sources_exist(self):
        """[D1, D14, AT-416-1] Canonical command sources in commands/ exist with valid YAML frontmatter."""
        commands_dir = REPO_ROOT / "commands"
        if not commands_dir.is_dir():
            self.fail("D1 / AT-416-1: Canonical commands directory 'commands/' does not exist")

        expected_sources = ["work.md", "idea.md", "bug.md"]
        for name in expected_sources:
            src_file = commands_dir / name
            if not src_file.is_file():
                self.fail(f"D1 / AT-416-1: Canonical command source '{src_file}' does not exist")

            content = src_file.read_text(encoding="utf-8")
            if not content.startswith("---\n"):
                self.fail(f"D1 / AT-416-1: '{src_file}' missing opening frontmatter delimiter '---'")

            parts = content.split("---\n", 2)
            if len(parts) < 3:
                self.fail(f"D1 / AT-416-1: '{src_file}' malformed frontmatter (fewer than 2 delimiters)")

            # Verify description is present and non-empty
            frontmatter_text = parts[1]
            body_text = parts[2]
            if not re.search(r"^description:\s*.+\S", frontmatter_text, re.MULTILINE):
                self.fail(f"D1 / AT-416-1: '{src_file}' missing non-empty description in frontmatter")
            if not body_text.strip():
                self.fail(f"D1 / AT-416-1: '{src_file}' command body is empty")

    def test_d2_at_416_2_claude_targets_byte_identity(self):
        """[D2, AT-416-2] Emitted .claude/commands/ targets match baseline on main byte-for-byte with no marker."""
        compiler = REPO_ROOT / "scripts" / "sync_commands.py"
        if not compiler.is_file():
            self.fail("D2 / AT-416-2: Compiler script 'scripts/sync_commands.py' does not exist")

        # Compile in a temporary root to test hermetically without dirtying repo (R1-9)
        with tempfile.TemporaryDirectory() as tmpdir:
            tmproot = Path(tmpdir)
            shutil.copytree(REPO_ROOT / "commands", tmproot / "commands")
            proc = subprocess.run(
                [sys.executable, str(compiler), "--root", str(tmproot)],
                capture_output=True,
                text=True,
            )
            if proc.returncode != 0:
                self.fail(f"D2 / AT-416-2: scripts/sync_commands.py execution failed: {proc.stderr}")

            # Byte-identity against main baseline (R1-2)
            for cmd in ["work.md", "idea.md", "bug.md"]:
                target_path = tmproot / ".claude" / "commands" / cmd
                if not target_path.is_file():
                    self.fail(f"D2 / AT-416-2: Target '{target_path}' was not emitted")

                baseline_proc = subprocess.run(
                    ["git", "show", f"origin/main:.claude/commands/{cmd}"],
                    cwd=str(REPO_ROOT),
                    capture_output=True,
                    text=True,
                )
                if baseline_proc.returncode != 0:
                    self.fail(f"D2 / AT-416-2: Could not read baseline .claude/commands/{cmd} from origin/main")
                baseline_text = baseline_proc.stdout
                emitted_text = target_path.read_text(encoding="utf-8")
                if emitted_text != baseline_text:
                    self.fail(f"D2 / AT-416-2: Emitted .claude/commands/{cmd} has drifted from baseline on origin/main")

                # Verify no GENERATED marker in Claude frontmatter
                parts = emitted_text.split("---\n", 2)
                if len(parts) >= 2 and "GENERATED" in parts[1]:
                    self.fail(f"D2 / AT-416-2: .claude/commands/{cmd} frontmatter contains forbidden GENERATED marker comment")

        # Also verify committed targets match baseline on origin/main
        for cmd in ["work.md", "idea.md", "bug.md"]:
            committed_target = REPO_ROOT / ".claude" / "commands" / cmd
            if not committed_target.is_file():
                self.fail(f"D2 / AT-416-2: Committed target '{committed_target}' does not exist")
            baseline_proc = subprocess.run(
                ["git", "show", f"origin/main:.claude/commands/{cmd}"],
                cwd=str(REPO_ROOT),
                capture_output=True,
                text=True,
            )
            if baseline_proc.returncode == 0:
                if committed_target.read_text(encoding="utf-8") != baseline_proc.stdout:
                    self.fail(f"D2 / AT-416-2: Committed .claude/commands/{cmd} differs from origin/main baseline")

    def test_d3_d5_at_416_4_antigravity_work_skill_hardening(self):
        """[D3, D5, AT-416-4] .agents/skills/work/SKILL.md defines hardened execution semantics (amending #43 D16)."""
        work_skill = REPO_ROOT / ".agents" / "skills" / "work" / "SKILL.md"
        if not work_skill.is_file():
            self.fail("D3, D5 / AT-416-4: Antigravity skill '.agents/skills/work/SKILL.md' does not exist")

        content = work_skill.read_text(encoding="utf-8")
        # 1. Argument shape
        if "<number> [--as <persona>]" not in content:
            self.fail("D5 / AT-416-4: work/SKILL.md missing argument shape '<number> [--as <persona>]'")
        # 2. Shell metacharacters list
        for char in [";", "&", "|", "`", "$"]:
            if char not in content:
                self.fail(f"D5 / AT-416-4: work/SKILL.md missing forbidden metacharacter '{char}' in validation instructions")
        # 3. Invocation command
        if "HEADLESS=1 scripts/ops/work.sh" not in content:
            self.fail("D5 / AT-416-4: work/SKILL.md missing 'HEADLESS=1 scripts/ops/work.sh' invocation command")
        if "run_command" not in content:
            self.fail("D5 / AT-416-4: work/SKILL.md missing 'run_command' instruction")

    def test_d4_at_416_3_antigravity_skills_structure(self):
        """[D4, AT-416-3] .agents/skills/<name>/SKILL.md carry valid frontmatter and GENERATED provenance marker."""
        skills_dir = REPO_ROOT / ".agents" / "skills"
        if not skills_dir.is_dir():
            self.fail("D4 / AT-416-3: Antigravity skills directory '.agents/skills' does not exist")

        expected_marker = "# GENERATED by scripts/sync_commands.py — edit commands/, not this file"
        for name in ["work", "idea", "bug"]:
            skill_file = skills_dir / name / "SKILL.md"
            if not skill_file.is_file():
                self.fail(f"D4 / AT-416-3: Antigravity skill '{skill_file}' does not exist")

            lines = skill_file.read_text(encoding="utf-8").splitlines()
            if not lines or lines[0] != "---":
                self.fail(f"D4 / AT-416-3: '{skill_file}' does not start with '---' at byte 0")
            if len(lines) < 2 or lines[1] != expected_marker:
                self.fail(f"D4 / AT-416-3: '{skill_file}' line 2 must be exact marker '{expected_marker}'")

            content = skill_file.read_text(encoding="utf-8")
            parts = content.split("---\n", 2)
            if len(parts) < 3:
                self.fail(f"D4 / AT-416-3: '{skill_file}' malformed frontmatter delimiters")
            frontmatter = parts[1]
            if f"name: {name}" not in frontmatter:
                self.fail(f"D4 / AT-416-3: '{skill_file}' frontmatter missing 'name: {name}'")
            if not re.search(r"^description:\s*.+\S", frontmatter, re.MULTILINE):
                self.fail(f"D4 / AT-416-3: '{skill_file}' frontmatter missing non-empty description")

    def test_d6_at_416_5_antigravity_prompt_skills_and_allowed_tools(self):
        """[D6, AT-416-5] Prompt commands preserve intake search and filing, and omit allowed-tools."""
        skills_dir = REPO_ROOT / ".agents" / "skills"
        for name in ["idea", "bug"]:
            skill_file = skills_dir / name / "SKILL.md"
            if not skill_file.is_file():
                self.fail(f"D6 / AT-416-5: Prompt skill '{skill_file}' does not exist")

            content = skill_file.read_text(encoding="utf-8")
            if "tracker_search.sh" not in content:
                self.fail(f"D6 / AT-416-5: '{skill_file}' missing 'tracker_search.sh' intake instruction")
            if "intake.sh" not in content:
                self.fail(f"D6 / AT-416-5: '{skill_file}' missing 'intake.sh' intake instruction")
            if "$ARGUMENTS" not in content:
                self.fail(f"D6 / AT-416-5: '{skill_file}' missing '$ARGUMENTS' parameter usage instruction")

        # Verify allowed-tools is omitted across all Antigravity skills
        for name in ["work", "idea", "bug"]:
            skill_file = skills_dir / name / "SKILL.md"
            if skill_file.is_file():
                parts = skill_file.read_text(encoding="utf-8").split("---\n", 2)
                if len(parts) >= 2 and "allowed-tools:" in parts[1]:
                    self.fail(f"D6 / AT-416-5: '{skill_file}' frontmatter contains allowed-tools (must be omitted on Antigravity)")

    def test_d7_at_416_6_compiler_cli_and_drift_detection(self):
        """[D7, AT-416-6] scripts/sync_commands.py supports --check, --root, --out and detects drift."""
        compiler = REPO_ROOT / "scripts" / "sync_commands.py"
        if not compiler.is_file():
            self.fail("D7 / AT-416-6: 'scripts/sync_commands.py' does not exist")

        with tempfile.TemporaryDirectory() as tmpdir:
            tmproot = Path(tmpdir)
            shutil.copytree(REPO_ROOT / "commands", tmproot / "commands")
            shutil.copytree(REPO_ROOT / ".claude", tmproot / ".claude")
            shutil.copytree(REPO_ROOT / ".agents", tmproot / ".agents")

            # --check on clean tree (R1-9: hermetic temp tree instead of live repo)
            proc_check = subprocess.run(
                [sys.executable, str(compiler), "--check", "--root", str(tmproot)],
                capture_output=True,
                text=True,
            )
            if proc_check.returncode != 0:
                self.fail(f"D7 / AT-416-6: 'scripts/sync_commands.py --check' failed on clean tree: {proc_check.stderr}")

            # Simulate drift in target file
            mutated_target = tmproot / ".claude" / "commands" / "work.md"
            mutated_target.write_text(mutated_target.read_text(encoding="utf-8") + "\n# DRIFT", encoding="utf-8")

            proc_drift = subprocess.run(
                [sys.executable, str(compiler), "--check", "--root", str(tmproot)],
                capture_output=True,
                text=True,
            )
            if proc_drift.returncode == 0:
                self.fail("D7 / AT-416-6: 'scripts/sync_commands.py --check' succeeded despite modified target file")
            if "drift" not in proc_drift.stderr.lower() and "drift" not in proc_drift.stdout.lower():
                self.fail("D7 / AT-416-6: 'scripts/sync_commands.py --check' did not output drift summary")

            # Verify --out flag emits to custom directory
            custom_out = tmproot / "custom_out"
            proc_out = subprocess.run(
                [sys.executable, str(compiler), "--root", str(tmproot), "--out", str(custom_out)],
                capture_output=True,
                text=True,
            )
            if proc_out.returncode != 0:
                self.fail(f"D7 / AT-416-6: scripts/sync_commands.py with --out failed: {proc_out.stderr}")
            if not (custom_out / ".claude" / "commands" / "work.md").is_file():
                self.fail("D7 / AT-416-6: scripts/sync_commands.py did not emit targets to --out directory")

    def test_d8_at_416_8_sanitizer_refuses_forbidden_patterns(self):
        """[D8, AT-416-8] Sanitizer refuses sources containing forbidden patterns (parity with sync_agents.py)."""
        compiler = REPO_ROOT / "scripts" / "sync_commands.py"
        if not compiler.is_file():
            self.fail("D8 / AT-416-8: 'scripts/sync_commands.py' does not exist")

        # Dynamically assemble leak tokens to prevent triggering repository sanitize_check.sh (R1-4)
        _h = "ho" + "me"
        _u = "Us" + "ers"
        test_cases = [
            ("absolute home path", f"/{_h}/someone/secret"),
            ("Users directory path", f"/{_u}/someone/secret"),
            ("home-variable path", "$" + _h.upper() + "/.secret_config"),
            ("home-relative dotfile path", "~" + "/." + "ssh/id_rsa"),
            ("GitHub token", "gh" + "p_" + ("A" * 20)),
            ("GitHub fine-grained token", "github_" + "pat_" + ("B" * 20)),
            ("AWS access key ID", "AK" + "IA" + ("0123456789ABCDEF")),
            ("API secret key", "s" + "k-" + ("1234567890abcdef12345678")),
            ("Slack token", "xo" + "xb-" + ("1234567890-abcdef")),
            ("private key block", "-----" + "BEGIN RSA PRIVATE KEY-----"),
            ("inline credential value", "pass" + "word: " + "superSecretValue12345"),
        ]

        for label, pattern_val in test_cases:
            with tempfile.TemporaryDirectory() as tmpdir:
                tmproot = Path(tmpdir)
                cmds = tmproot / "commands"
                cmds.mkdir(parents=True)
                (cmds / "leaky.md").write_text(
                    f"---\ndescription: Leaky test command\n---\nLeak value: {pattern_val}\n",
                    encoding="utf-8",
                )
                proc = subprocess.run(
                    [sys.executable, str(compiler), "--root", str(tmproot), "--out", str(tmproot / "out")],
                    capture_output=True,
                    text=True,
                )
                if proc.returncode == 0:
                    self.fail(f"D8 / AT-416-8: Compiler succeeded unexpectedly on source containing {label}")
                if "REFUSING TO WRITE" not in proc.stderr and "REFUSING TO WRITE" not in proc.stdout:
                    self.fail(f"D8 / AT-416-8: Compiler did not output 'REFUSING TO WRITE' for {label}")

    def test_d9_d14_at_416_7_at_416_13_pruning_and_wrap_allowlist(self):
        """[D9, D14, AT-416-7, AT-416-13] Pruning removes unmanaged targets while allowlisting wrap.md."""
        compiler = REPO_ROOT / "scripts" / "sync_commands.py"
        if not compiler.is_file():
            self.fail("D9, D14 / AT-416-7: 'scripts/sync_commands.py' does not exist")

        with tempfile.TemporaryDirectory() as tmpdir:
            tmproot = Path(tmpdir)
            shutil.copytree(REPO_ROOT / "commands", tmproot / "commands")
            claude_cmds = tmproot / ".claude" / "commands"
            claude_cmds.mkdir(parents=True)

            # 1. Build first to populate managed targets (R1-3, AT-R1-3)
            proc_build = subprocess.run(
                [sys.executable, str(compiler), "--root", str(tmproot)],
                capture_output=True,
                text=True,
            )
            if proc_build.returncode != 0:
                self.fail(f"D9 / AT-416-13: Compiler build failed in test tree: {proc_build.stderr}")

            # 2. wrap.md allowlist check on clean tree
            wrap_file = claude_cmds / "wrap.md"
            wrap_file.write_text("---\ndescription: wrap allowlist test\n---\n", encoding="utf-8")

            # Running check must not fail due to wrap.md on an otherwise clean tree
            proc_check = subprocess.run(
                [sys.executable, str(compiler), "--check", "--root", str(tmproot)],
                capture_output=True,
                text=True,
            )
            if proc_check.returncode != 0:
                self.fail(f"D9 / AT-416-13: Compiler --check failed with allowlisted wrap.md present: {proc_check.stderr}")

            # Recompile and ensure wrap.md is not pruned
            proc_rebuild = subprocess.run(
                [sys.executable, str(compiler), "--root", str(tmproot)],
                capture_output=True,
                text=True,
            )
            if proc_rebuild.returncode != 0:
                self.fail(f"D9 / AT-416-13: Compiler rebuild failed: {proc_rebuild.stderr}")
            if not wrap_file.is_file():
                self.fail("D9 / AT-416-13: Compiler pruned allowlisted '.claude/commands/wrap.md'")

            # 3. Extraneous orphan file check
            orphan_file = claude_cmds / "orphan.md"
            orphan_file.write_text("---\ndescription: orphan test\n---\n", encoding="utf-8")

            proc_orphan_check = subprocess.run(
                [sys.executable, str(compiler), "--check", "--root", str(tmproot)],
                capture_output=True,
                text=True,
            )
            if proc_orphan_check.returncode == 0:
                self.fail("D9 / AT-416-7: Compiler --check did not flag unmanaged 'orphan.md' as drift")

            # Build should prune orphan.md
            subprocess.run([sys.executable, str(compiler), "--root", str(tmproot)], capture_output=True)
            if orphan_file.is_file():
                self.fail("D9 / AT-416-7: Compiler failed to prune extraneous 'orphan.md'")

    def test_d10_at_416_9_compiler_roundtrip_includes_commands_gate(self):
        """[D10, AT-416-9] scripts/ci/compiler_roundtrip.sh includes ref-free commands roundtrip step."""
        roundtrip_script = REPO_ROOT / "scripts" / "ci" / "compiler_roundtrip.sh"
        if not roundtrip_script.is_file():
            self.fail("D10 / AT-416-9: 'scripts/ci/compiler_roundtrip.sh' does not exist")

        content = roundtrip_script.read_text(encoding="utf-8")
        if "sync_commands.py" not in content:
            self.fail("D10 / AT-416-9: compiler_roundtrip.sh does not invoke 'sync_commands.py'")
        if not re.search(r'\bsync_commands\.py["\']?\s+--check', content) and "$COMPILER_COMMANDS" not in content:
            self.fail("D10 / AT-416-9: compiler_roundtrip.sh missing commands drift verification step")

    def test_d11_at_416_10_spec_check_includes_commands_path(self):
        """[D11, AT-416-10] scripts/ci/spec_check.sh includes commands/* under behavior-bearing paths."""
        spec_check_script = REPO_ROOT / "scripts" / "ci" / "spec_check.sh"
        if not spec_check_script.is_file():
            self.fail("D11 / AT-416-10: 'scripts/ci/spec_check.sh' does not exist")

        content = spec_check_script.read_text(encoding="utf-8")
        # Check that commands/* is added to behavior-bearing case match
        if "commands/*" not in content:
            self.fail("D11 / AT-416-10: 'scripts/ci/spec_check.sh' missing 'commands/*' in behavior-bearing paths case match")

    def test_d11_d13_at_416_12_living_spec_and_documentation_parity(self):
        """[D11, D13, AT-416-12] docs/SPEC.md contains commands.compiler and AGENTS/CLAUDE/GEMINI document it."""
        spec_doc = REPO_ROOT / "docs" / "SPEC.md"
        if not spec_doc.is_file():
            self.fail("D11 / AT-416-12: 'docs/SPEC.md' does not exist")

        spec_content = spec_doc.read_text(encoding="utf-8")
        if "### commands.compiler" not in spec_content:
            self.fail("D11 / AT-416-12: 'docs/SPEC.md' missing section '### commands.compiler'")

        for needle in ["commands/<name>.md", ".agents/skills/", "sync_commands.py"]:
            if needle not in spec_content:
                self.fail(f"D11 / AT-416-12: 'docs/SPEC.md' missing required term '{needle}' under commands.compiler")

        for doc_name in ["AGENTS.md", "CLAUDE.md", "GEMINI.md"]:
            doc_file = REPO_ROOT / doc_name
            if not doc_file.is_file():
                self.fail(f"D13 / AT-416-12: '{doc_name}' does not exist")
            if "sync_commands.py" not in doc_file.read_text(encoding="utf-8"):
                self.fail(f"D13 / AT-416-12: '{doc_name}' missing reference to 'sync_commands.py'")

    def test_d12_d13_amendment_note_for_issue_43_d16(self):
        """[D5, D12, D13] intent/43-harness-agnostic-launch/spec.md records amendment note for D16."""
        spec_43 = REPO_ROOT / "intent" / "43-harness-agnostic-launch" / "spec.md"
        if not spec_43.is_file():
            self.fail("D5, D12, D13: 'intent/43-harness-agnostic-launch/spec.md' does not exist")

        content = spec_43.read_text(encoding="utf-8")
        if "416" not in content or "amended" not in content.lower():
            self.fail("D5, D12, D13: intent/43-harness-agnostic-launch/spec.md missing amendment note for D16 (Issue #416)")


if __name__ == "__main__":
    unittest.main(verbosity=2)
