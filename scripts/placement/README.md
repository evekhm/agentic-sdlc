# The placement registry (#25, D16 / D17)

This is not documentation *about* the adapters. It is the contract they
are checked against: `scripts/ops/tests/placement_test.sh` reads the
rules below off every `scripts/placement/*/run.sh`, and
`scripts/ops/execution.py --check` fails a binding that names a
directory which is not here.

## The contract

- **The directory name IS the value legal in `config/execution.yaml`.**
  There is no enum of placements anywhere in the tree; `placement:
  vm-local` is legal because `scripts/placement/vm-local/` exists, and
  for no other reason.
- **Every adapter is `scripts/placement/<name>/run.sh`**, called as

  ```
  run.sh <number> --as <persona>
  ```

  and taking nothing else. A number and an actor is the whole input,
  because a flag naming a stage, a folder, a branch or an artifact
  would let a run work a rung the labels say is not current (#36, D7).
- **Its final line is**

  ```
  exec "$REPO_ROOT/scripts/ops/work.sh" "$n" --as "$persona"
  ```

  and nothing else dispatches. No adapter composes a prompt, names a
  stage, folder, branch, artifact or model (D16). The portable unit of
  execution is that one line; an adapter is the environment it runs in,
  never a second dispatcher.
- **`DRY_RUN=1` passes through unchanged.** That is how an adapter is
  validated without writing: the reads and the refusals run exactly as
  a live run's would, and nothing reaches GitHub (#36, D8).
- **Exit codes are `work.sh`'s, unchanged**: `0` launched or printed,
  `2` a stated refusal (the number was not worked, by design), `1`
  unusable input or an environment that cannot start the run. An
  adapter adds no code of its own; a preflight failure of its own is a
  `1`.
- **A credential moves by NAME.** An adapter may assert that the
  environment variable a persona's `authority.token` names is set; it
  never prints it, writes it to a file, or puts it in an argument
  (trusted-posting, rule 2). The token the launched session posts with
  is minted by `work.sh` at launch (`ops.identity`), not by the
  adapter.
- **`UNSET_CREDENTIAL_IS_SKIP=1` downgrades a missing credential from a
  `1` to a `2`**, and nothing else. A caller sets it when the run is
  optional in that environment — the canonical case is a trigger
  workflow merged before a human has loaded the Apps' private keys
  (#7), where the strict `1` puts a red check on every pull request in
  the repository for a condition that is "not configured yet". The
  refusal is still a stated one: the adapter prints a line NAMING the
  variable it looked for and dispatches nothing, so the skip can be
  read off the log and the run summary. Unset — the default — a
  missing credential remains a `1`. It is not a general "keep going"
  flag: it covers exactly the missing-credential branch, and the
  variable is never consulted anywhere else.

## v1 adapters

| Directory | Runs where | Credential |
|---|---|---|
| `vm-local` | the presenter's machine | the key `scripts/auth/mint_app_token.py` already finds — the environment variable `authority.token` names, else the operator's local key directory |
| `gh-actions` | a GitHub-hosted runner | the Actions secret whose name is the persona's `authority.token`, set into the job's environment by `.github/workflows/unattended.yml` |

## Reserved names

Documented, no adapter yet. Reserving a name spells the name and does
nothing more: **a binding naming one fails `execution.py --check` with a
named error until its directory is merged** (D17). Reserving must not
become a way to ship a binding that cannot run.

- **`cloud-run-worker`** — a queue-consuming background fleet: reviewers
  and builders behind a subscription, no public ingress, scaled by depth.
- **`cloud-run-instance`** — an always-on singleton loop, the shape a
  continuous watcher needs.
- **`agent-engine`** — a managed agent platform; intake's later target
  (D12), the first move once the adapter exists.

## Adding one

Create `scripts/placement/<name>/run.sh` obeying the contract above, add
a row to the table, and change the persona's `placement` value. That is
the whole move, and it is one line in `config/execution.yaml` plus the
adapter (D18).
