#!/usr/bin/env bash
# Provisions model access for the HOSTED runner: Workload Identity
# Federation, a least-privilege service account, and the repository
# variables .github/workflows/unattended.yml reads — no cloud key at
# rest, which is the property scripts/placement/gh-actions/run.sh
# states and this script is the other half of.
#
# WHAT IT TOUCHES
#   GCP   aiplatform / iamcredentials / sts APIs, a WIF pool and a
#         GitHub OIDC provider, a predict-only custom role, a service
#         account bound to that one role, and the impersonation
#         binding scoped to THIS repository.
#   Repo  four Actions VARIABLES (never a secret — this script handles
#         no secret, and must stay that way): WIF_PROVIDER,
#         WIF_SERVICE_ACCOUNT, CLAUDE_VERTEX_PROJECT_ID,
#         ANTIGRAVITY_PROJECT_ID.
#
# It does NOT do the human-only steps: enabling the Claude models in
# Vertex Model Garden (one console click per project) and allowing the
# actions the workflow uses in the repository's Actions settings. Both
# are listed again in the closing summary.
#
# Nothing about bot accounts, personal access tokens or labels lives
# here: the persona identities are GitHub Apps whose private keys a
# human loads as Actions secrets, and the label taxonomy belongs to
# scripts/setup/bootstrap_tracker.sh.
#
# Adapted from the predecessor's scripts/setup/argus_setup.sh in
# agentic-experiments-lab; comments below cite the line numbers of the
# guards that were carried over, because each one encodes a state that
# describes successfully but does not work (soft-deleted, disabled,
# wrong issuer, DISABLED launch stage).
#
# Idempotent: a second run mutates nothing and says so per item.
set -euo pipefail

usage() {
  cat <<'EOF'
Provision WIF + repo variables for the unattended-personas workflow.

  bash scripts/setup/wif_setup.sh              # apply (default)
  bash scripts/setup/wif_setup.sh --check      # verify only, exit 1 if anything is missing
  bash scripts/setup/wif_setup.sh --dry-run    # print the mutations, run none

Environment:
  GCP_PROJECT             REQUIRED. Project that hosts the pool, provider, service
                          account and custom role, and where the Claude models are
                          enabled on Vertex AI.
  GITHUB_REPO             <owner>/<repo>. Default: `gh repo view --json nameWithOwner`.
  ANTIGRAVITY_PROJECT_ID  Billing project the agy CLI is told about under ADC auth.
                          Default: $GCP_PROJECT. NOTE: it does not decide which
                          models agy can see — the calling identity does (#167).
  POOL_ID                 Default: github-actions
  PROVIDER_ID             Default: github-provider
  SA_ID                   Default: unattended-personas
  ROLE_ID                 Default: unattendedVertexPredict
  GH_TOKEN                Honoured by gh as usual.

POOL_ID and PROVIDER_ID default to the same names the predecessor's
argus_setup.sh uses, so a GCP project it already provisioned is REUSED
rather than duplicated. SA_ID and ROLE_ID are overridable for the same
reason — point them at an existing pair (e.g. argus-reviewer /
argusVertexPredict) instead of creating a second one.

Prerequisites: gcloud (authenticated, owner/editor on GCP_PROJECT), gh,
jq. Writing repository variables needs ADMIN on the repository — the
project's operator bot has push only, so export an admin GH_TOKEN for
this script. Apply mode probes that capability with a set+delete round
trip before it creates a single GCP resource, and names it if missing.
EOF
}

# --- Arguments ----------------------------------------------------------------
MODE="apply"   # apply | check | dry-run
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)   MODE="check";   shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument '$1'." >&2; usage; exit 1 ;;
  esac
done

die() { echo "wif_setup: $*" >&2; exit 1; }

CHECK_FAILED=0
CREATED=()    # mutations actually performed (apply)
PLANNED=()    # mutations printed but not performed (dry-run)
ABSENT=()     # mutations that would be needed (check)
VERIFIED=()   # items read back and found correct

ok() { # <what>
  printf '    OK      %s\n' "$1"
  VERIFIED+=("$1")
}

# A mutation is described once and executed, printed, or counted —
# never duplicated per mode. This is the single gate every gcloud and
# gh write in this file passes through.
run_or_print() { # <what> <cmd...>
  local what="$1"; shift
  case "$MODE" in
    check)
      printf '    MISSING %s\n' "$what"
      ABSENT+=("$what")
      CHECK_FAILED=1
      ;;
    dry-run)
      printf '    DRY-RUN: '
      printf '%q ' "$@"
      printf '\n'
      PLANNED+=("$what")
      ;;
    apply)
      printf '    ==> %s\n' "$what"
      "$@" || die "failed: $what"
      CREATED+=("$what")
      ;;
  esac
}

# A resource that exists but is in a state that cannot work (disabled,
# soft-deleted, wrong issuer). In apply and dry-run modes that is fatal
# — creating more on top of it produces a broken deployment that looks
# provisioned. In check mode it is one reported line and the run
# continues, so a single pass reports every problem. Returns 1 in check
# mode so the caller can skip whatever depended on it.
fail_item() { # <headline> [remediation...]
  local head="$1"; shift
  if [ "$MODE" = "check" ]; then
    printf '    WRONG   %s\n' "$head"
    local line
    for line in "$@"; do printf '            %s\n' "$line"; done
    CHECK_FAILED=1
    return 1
  fi
  echo "ERROR: $head" >&2
  local line
  for line in "$@"; do echo "  $line" >&2; done
  exit 1
}

# --- Preconditions ------------------------------------------------------------
for t in gcloud gh jq; do
  command -v "$t" >/dev/null || die "'$t' is not installed."
done

GCLOUD_ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
case "$GCLOUD_ACCOUNT" in
  ""|"(unset)") die "gcloud has no active account — run 'gcloud auth login'." ;;
esac

gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run 'gh auth login' or export GH_TOKEN."

GITHUB_REPO="${GITHUB_REPO:-}"
if [ -z "$GITHUB_REPO" ]; then
  GITHUB_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  [ -n "$GITHUB_REPO" ] \
    || die "GITHUB_REPO is not set and 'gh repo view' could not resolve one — export GITHUB_REPO=<owner>/<repo>."
fi
case "$GITHUB_REPO" in
  */*) : ;;
  *) die "GITHUB_REPO must be <owner>/<repo>, got '$GITHUB_REPO'." ;;
esac
GITHUB_OWNER="${GITHUB_REPO%%/*}"

[ -n "${GCP_PROJECT:-}" ] || { echo "ERROR: \$GCP_PROJECT is not set." >&2; echo; usage; exit 1; }
ANTIGRAVITY_PROJECT_ID="${ANTIGRAVITY_PROJECT_ID:-$GCP_PROJECT}"
POOL_ID="${POOL_ID:-github-actions}"
PROVIDER_ID="${PROVIDER_ID:-github-provider}"
SA_ID="${SA_ID:-unattended-personas}"
ROLE_ID="${ROLE_ID:-unattendedVertexPredict}"

# The project NUMBER, not the id: both the provider resource name the
# workflow passes to google-github-actions/auth and the principalSet
# member are keyed on it (argus_setup.sh derives it from the provider's
# own `name`; resolving it up front works in --check and --dry-run too,
# where the provider may not exist yet).
PROJECT_NUMBER="$(gcloud projects describe "$GCP_PROJECT" --format="value(projectNumber)" 2>/dev/null || true)"
[ -n "$PROJECT_NUMBER" ] \
  || die "cannot access GCP project '$GCP_PROJECT' — check the project id and 'gcloud auth'."

SA_EMAIL="${SA_ID}@${GCP_PROJECT}.iam.gserviceaccount.com"
POOL_NAME="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}"
WIF_PROVIDER_FULL="${POOL_NAME}/providers/${PROVIDER_ID}"
PRINCIPAL_SET="principalSet://iam.googleapis.com/${POOL_NAME}/attribute.repository/${GITHUB_REPO}"
PREDICT_PERMISSION="aiplatform.endpoints.predict"

# Functional probe of the WRITE path (argus_setup.sh:82-84): a
# set+delete round trip on a throwaway name proves the capability this
# script needs before any GCP resource is created. Reads-only modes
# skip it — a probe is itself a mutation.
if [ "$MODE" = "apply" ]; then
  if ! { gh variable set WIF_SETUP_WRITE_PROBE --repo "$GITHUB_REPO" --body "probe" >/dev/null 2>&1 \
         && gh variable delete WIF_SETUP_WRITE_PROBE --repo "$GITHUB_REPO" >/dev/null 2>&1; }; then
    die "repository variables need admin on $GITHUB_REPO; run with an admin GH_TOKEN"
  fi
fi

echo "==> $MODE: $GITHUB_REPO against GCP project $GCP_PROJECT ($PROJECT_NUMBER)"

# --- 1. APIs ------------------------------------------------------------------
echo "==> Services"
ensure_apis() {
  local enabled svc
  if ! enabled="$(gcloud services list --enabled --project="$GCP_PROJECT" \
        --format="value(config.name)" 2>/dev/null)"; then
    fail_item "could not list enabled services on '$GCP_PROJECT' — gcloud failed (auth? transient?)" \
      "A failed read is not proof that the APIs are disabled." || return 1
  fi
  local -a to_enable=()
  for svc in aiplatform.googleapis.com iamcredentials.googleapis.com sts.googleapis.com; do
    if printf '%s\n' "$enabled" | grep -Fxq "$svc"; then
      ok "service $svc enabled"
    else
      to_enable+=("$svc")
    fi
  done
  if [ "${#to_enable[@]}" -gt 0 ]; then
    run_or_print "enable services: ${to_enable[*]}" \
      gcloud services enable "${to_enable[@]}" --project="$GCP_PROJECT" --quiet
  fi
}
ensure_apis || true

# --- 2. WIF pool --------------------------------------------------------------
# describe succeeds on soft-deleted pools too (readable for 30 days,
# state: DELETED) — only ACTIVE counts as "exists" (argus_setup.sh:132-155).
# `disabled` is an independent field: a disabled pool stays ACTIVE and
# cannot exchange tokens.
echo "==> WIF pool '$POOL_ID'"
# Each resource ends in one of three states, and everything downstream
# of it branches on that rather than on the mode:
#   present  it exists and is usable — dependent resources can be READ
#   pending  it does not exist and this run did not create it (check /
#            dry-run) — dependent resources cannot be read, so their
#            mutation is reported/printed without a read
#   broken   it exists in a state that cannot work — dependents are
#            skipped by name, because provisioning onto it is worse
#            than provisioning nothing
resource_created() { # state of a resource this run just created
  case "$MODE" in apply) echo "present" ;; *) echo "pending" ;; esac
}
POOL_STATUS="broken"
ensure_pool() {
  local state disabled_raw
  state="$(gcloud iam workload-identity-pools describe "$POOL_ID" \
    --project="$GCP_PROJECT" --location=global --format="value(state)" 2>/dev/null || echo "")"
  if [ "$state" = "ACTIVE" ]; then
    disabled_raw="$(gcloud iam workload-identity-pools describe "$POOL_ID" \
      --project="$GCP_PROJECT" --location=global --format="value(disabled)")" \
      || { fail_item "could not read the pool's disabled state — gcloud failed" || return 1; }
    case "$disabled_raw" in
      [Tt]rue)
        fail_item "WIF pool '$POOL_ID' exists but is DISABLED — token exchange will fail." \
          "Re-enable it:  gcloud iam workload-identity-pools update $POOL_ID --project=$GCP_PROJECT --location=global --no-disabled" \
          || return 1
        ;;
    esac
    ok "WIF pool '$POOL_ID' exists and is active — kept"
    POOL_STATUS="present"
  elif [ -n "$state" ]; then
    fail_item "WIF pool '$POOL_ID' exists but is $state (soft-deleted)." \
      "Restore it:  gcloud iam workload-identity-pools undelete $POOL_ID --project=$GCP_PROJECT --location=global" \
      "then re-run this script (a soft-deleted pool cannot be recreated until it purges)." \
      || return 1
  else
    run_or_print "create WIF pool '$POOL_ID'" \
      gcloud iam workload-identity-pools create "$POOL_ID" \
        --project="$GCP_PROJECT" --location=global \
        --display-name="GitHub Actions"
    POOL_STATUS="$(resource_created)"
  fi
}
ensure_pool || true

# --- 3. OIDC provider ---------------------------------------------------------
# The provider decides three things (argus_setup.sh:186-217): which IdP
# (issuer), whether the repo attribute the impersonation binding keys on
# is mapped at all, and who is trusted (the attribute condition).
echo "==> WIF provider '$PROVIDER_ID'"
ATTRIBUTE_MAPPING="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner"
EXPECTED_CONDITION="assertion.repository_owner == '${GITHUB_OWNER}'"
create_provider() {
  run_or_print "create WIF provider '$PROVIDER_ID' (scoped to owner '$GITHUB_OWNER')" \
    gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
      --project="$GCP_PROJECT" --location=global \
      --workload-identity-pool="$POOL_ID" \
      --display-name="GitHub" \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="$ATTRIBUTE_MAPPING" \
      --attribute-condition="$EXPECTED_CONDITION"
}
ensure_provider() {
  case "$POOL_STATUS" in
    broken)  printf '    SKIP    provider (the pool is not usable)\n'; return 1 ;;
    pending) create_provider; return 0 ;;   # nothing to read inside a pool that does not exist
  esac
  local state disabled_raw existing_condition existing_issuer existing_mapping
  describe_provider() { # <field>
    gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
      --project="$GCP_PROJECT" --location=global \
      --workload-identity-pool="$POOL_ID" --format="value($1)"
  }
  # CEL accepts either quote style and arbitrary whitespace, and gcloud
  # stores the condition exactly as supplied (argus_setup.sh:175).
  norm() { printf '%s' "$1" | tr -d '[:space:]' | tr '"' "'"; }

  state="$(describe_provider state 2>/dev/null || echo "")"
  if [ "$state" = "ACTIVE" ]; then
    disabled_raw="$(describe_provider disabled)" \
      || { fail_item "could not read the provider's disabled state — gcloud failed" || return 1; }
    case "$disabled_raw" in
      [Tt]rue)
        fail_item "WIF provider '$PROVIDER_ID' exists but is DISABLED — token exchange will fail." \
          "Re-enable it:  gcloud iam workload-identity-pools providers update-oidc $PROVIDER_ID --project=$GCP_PROJECT --location=global --workload-identity-pool=$POOL_ID --no-disabled" \
          || return 1
        ;;
    esac
    existing_issuer="$(describe_provider oidc.issuerUri)"
    existing_mapping="$(describe_provider attributeMapping)"
    existing_condition="$(describe_provider attributeCondition)"
    if [ "$existing_issuer" != "https://token.actions.githubusercontent.com" ]; then
      fail_item "WIF provider '$PROVIDER_ID' exists but its issuer is not GitHub Actions." \
        "found:    ${existing_issuer:-<none>}" \
        "expected: https://token.actions.githubusercontent.com" || return 1
    else
      ok "provider issuer is GitHub Actions"
    fi
    case "$(norm "$existing_mapping")" in
      *"attribute.repository=assertion.repository"*)
        ok "provider maps attribute.repository=assertion.repository"
        ;;
      *)
        fail_item "WIF provider '$PROVIDER_ID' does not map attribute.repository=assertion.repository, which the repo-scoped impersonation binding requires." \
          "found mapping: ${existing_mapping:-<none>}" || return 1
        ;;
    esac
    # COVERAGE, not equality: a shared project's provider legitimately
    # carries a widened condition such as
    #   assertion.repository_owner == 'a' || assertion.repository_owner == 'b'
    # which trusts this owner. The quotes are part of the needle, so
    # owner 'evekhm' does not match a condition naming 'evekhm-other'.
    case "$(norm "$existing_condition")" in
      *"'${GITHUB_OWNER}'"*)
        ok "provider condition covers owner '$GITHUB_OWNER': $existing_condition"
        ;;
      *)
        fail_item "WIF provider '$PROVIDER_ID' exists but its attribute condition does not cover owner '$GITHUB_OWNER'." \
          "found:               ${existing_condition:-<none>}" \
          "expected to contain: ${EXPECTED_CONDITION}" \
          "Widen the condition to include this owner, or run against a different GCP project." \
          || return 1
        ;;
    esac
  elif [ -n "$state" ]; then
    fail_item "WIF provider '$PROVIDER_ID' exists but is $state (soft-deleted)." \
      "Restore it:  gcloud iam workload-identity-pools providers undelete $PROVIDER_ID --project=$GCP_PROJECT --location=global --workload-identity-pool=$POOL_ID" \
      "then re-run this script." || return 1
  else
    create_provider
  fi
}
ensure_provider || true

# --- 4. Predict-only custom role ----------------------------------------------
# A deleted custom role is retained for 7 days and still describes
# successfully, and a DISABLED launch stage is ignored by IAM even
# though the role describes fine (argus_setup.sh:239-283).
echo "==> Custom role '$ROLE_ID'"
ROLE_STATUS="broken"
ensure_role() {
  local deleted stage perms extra
  deleted="$(gcloud iam roles describe "$ROLE_ID" --project="$GCP_PROJECT" \
    --format="value(deleted)" 2>/dev/null || echo "__absent__")"
  case "$deleted" in
    [Tt]rue)
      fail_item "custom role '$ROLE_ID' exists but is soft-deleted." \
        "Restore it:  gcloud iam roles undelete $ROLE_ID --project=$GCP_PROJECT" \
        "then re-run this script." || return 1
      ;;
    __absent__)
      run_or_print "create custom role '$ROLE_ID' ($PREDICT_PERMISSION only)" \
        gcloud iam roles create "$ROLE_ID" --project="$GCP_PROJECT" \
          --title="Unattended personas Vertex predict-only" \
          --description="rawPredict on publisher models; nothing else" \
          --permissions="$PREDICT_PERMISSION" --stage=GA --quiet
      ROLE_STATUS="$(resource_created)"
      return 0
      ;;
  esac
  stage="$(gcloud iam roles describe "$ROLE_ID" --project="$GCP_PROJECT" --format="value(stage)")" \
    || { fail_item "could not read the launch stage of role '$ROLE_ID' — gcloud failed" || return 1; }
  if [ "$stage" = "DISABLED" ]; then
    fail_item "custom role '$ROLE_ID' exists but its launch stage is DISABLED — IAM ignores it." \
      "Re-enable it:  gcloud iam roles update $ROLE_ID --project=$GCP_PROJECT --stage=GA" || return 1
  fi
  # Read first, then test: inside a pipeline under pipefail a gcloud
  # failure is indistinguishable from "permission absent" and produces
  # the wrong remediation (argus_setup.sh:266-270). gcloud has emitted
  # ';', ',' and whitespace as the separator over time — normalize all
  # three to newlines.
  perms="$(gcloud iam roles describe "$ROLE_ID" --project="$GCP_PROJECT" \
    --format="value(includedPermissions)")" \
    || { fail_item "could not read permissions of role '$ROLE_ID' — gcloud failed (auth? transient?)" || return 1; }
  if printf '%s' "$perms" | tr ';,[:space:]' '\n' | grep -qx "$PREDICT_PERMISSION"; then
    ok "custom role '$ROLE_ID' grants $PREDICT_PERMISSION (stage $stage) — kept"
    ROLE_STATUS="present"
  else
    fail_item "custom role '$ROLE_ID' exists but does not grant $PREDICT_PERMISSION." \
      "Add it:  gcloud iam roles update $ROLE_ID --project=$GCP_PROJECT --add-permissions=$PREDICT_PERMISSION" \
      || return 1
  fi
  # Extra permissions are the operator's call (an existing shared role
  # may legitimately grant more) but they are not least privilege, so
  # they are reported rather than silently accepted.
  extra="$(printf '%s' "$perms" | tr ';,[:space:]' '\n' | grep -v '^$' | grep -vx "$PREDICT_PERMISSION" || true)"
  if [ -n "$extra" ]; then
    echo "    WARNING role '$ROLE_ID' also grants, beyond predict:"
    printf '%s\n' "$extra" | while IFS= read -r p; do echo "            $p"; done
  fi
}
ensure_role || true

# --- 5. Service account -------------------------------------------------------
echo "==> Service account '$SA_EMAIL'"
SA_STATUS="broken"
ensure_sa() {
  local disabled
  disabled="$(gcloud iam service-accounts describe "$SA_EMAIL" --project="$GCP_PROJECT" \
    --format="value(disabled)" 2>/dev/null || echo "__absent__")"
  case "$disabled" in
    [Tt]rue)
      fail_item "service account '$SA_ID' exists but is DISABLED — token exchange will fail." \
        "Re-enable it:  gcloud iam service-accounts enable $SA_EMAIL --project=$GCP_PROJECT" || return 1
      ;;
    __absent__)
      run_or_print "create service account '$SA_ID'" \
        gcloud iam service-accounts create "$SA_ID" --project="$GCP_PROJECT" \
          --display-name="Unattended personas (Vertex-only, least privilege)"
      SA_STATUS="$(resource_created)"
      ;;
    *)
      ok "service account '$SA_ID' exists and is enabled — kept"
      SA_STATUS="present"
      ;;
  esac
}
ensure_sa || true

# --- 6. Project binding: SA -> predict-only role ------------------------------
echo "==> Project IAM binding"
ensure_project_binding() {
  local role_ref members
  role_ref="projects/${GCP_PROJECT}/roles/${ROLE_ID}"
  bind_role() {
    # add-iam-policy-binding is itself idempotent; the read below exists
    # only so a no-op run reports "kept" instead of re-writing the policy.
    run_or_print "bind $SA_ID to $role_ref" \
      gcloud projects add-iam-policy-binding "$GCP_PROJECT" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="$role_ref" --quiet
  }
  case "$SA_STATUS:$ROLE_STATUS" in
    broken:*) printf '    SKIP    project binding (the service account is not usable)\n'; return 1 ;;
    *:broken) printf '    SKIP    project binding (the custom role is not usable)\n'; return 1 ;;
    pending:*|*:pending) bind_role; return 0 ;;  # neither side exists to be read
  esac
  if ! members="$(gcloud projects get-iam-policy "$GCP_PROJECT" \
        --flatten="bindings[].members" \
        --filter="bindings.role=${role_ref} AND bindings.members=serviceAccount:${SA_EMAIL}" \
        --format="value(bindings.members)" 2>/dev/null)"; then
    fail_item "could not read the IAM policy of project '$GCP_PROJECT' — gcloud failed" || return 1
  fi
  if [ -n "$members" ]; then
    ok "$SA_ID holds $role_ref — kept"
  else
    bind_role
  fi
}
ensure_project_binding || true

# --- 7. Impersonation binding: this repo's OIDC tokens -> the SA --------------
echo "==> Workload identity impersonation binding"
ensure_sa_binding() {
  local policy hits
  bind_impersonation() {
    run_or_print "allow $GITHUB_REPO's OIDC tokens to impersonate $SA_ID" \
      gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
        --project="$GCP_PROJECT" \
        --role="roles/iam.workloadIdentityUser" \
        --member="$PRINCIPAL_SET" --quiet
  }
  case "$SA_STATUS" in
    broken)  printf '    SKIP    impersonation binding (the service account is not usable)\n'; return 1 ;;
    pending) bind_impersonation; return 0 ;;   # no policy to read on an absent account
  esac
  if ! policy="$(gcloud iam service-accounts get-iam-policy "$SA_EMAIL" \
        --project="$GCP_PROJECT" --format=json 2>/dev/null)"; then
    fail_item "could not read the IAM policy of service account '$SA_EMAIL' — gcloud failed" || return 1
  fi
  hits="$(printf '%s' "$policy" | jq -r --arg m "$PRINCIPAL_SET" '
    [ .bindings[]? | select(.role == "roles/iam.workloadIdentityUser")
      | .members[]? | select(. == $m) ] | length')" \
    || { fail_item "could not parse the service account IAM policy" || return 1; }
  if [ "$hits" != "0" ]; then
    ok "$GITHUB_REPO may impersonate $SA_ID — kept"
  else
    bind_impersonation
  fi
}
ensure_sa_binding || true

# --- 8. Cross-project warning for the agy billing project ---------------------
# The predecessor's docs/ARGUS_SETUP.md ("Quota-project note") is the
# only agy-specific IAM statement there is, and it is deliberately a
# NON-grant: the reviewer SA holds predict only, because the workflows
# call the model by publisher path and attribute usage to the resource
# project. A client that instead attributes usage via a quota project —
# quota_project_id inside the ADC credential file,
# GOOGLE_CLOUD_QUOTA_PROJECT, or an explicit x-goog-user-project header
# — fails with an error naming serviceusage.services.use, and the
# remedy is roles/serviceusage.serviceUsageConsumer granted THEN, not
# preemptively. ANTIGRAVITY_PROJECT_ID itself is just the project agy
# bills under AGY_ADC_AUTH=true; the docs attach no extra role to it.
# Nothing is granted here on either count.
if [ "$ANTIGRAVITY_PROJECT_ID" != "$GCP_PROJECT" ]; then
  echo "==> WARNING: ANTIGRAVITY_PROJECT_ID ($ANTIGRAVITY_PROJECT_ID) is not GCP_PROJECT ($GCP_PROJECT)."
  echo "    The predict-only binding exists on $GCP_PROJECT ONLY. If agy must reach models"
  echo "    billed to $ANTIGRAVITY_PROJECT_ID, grant $SA_EMAIL equivalent access there yourself."
  echo "    This script does not touch a second project."
fi

# --- 9. Repository variables --------------------------------------------------
echo "==> Repository variables on $GITHUB_REPO"
VARS_JSON=""
VARS_READABLE=1
if ! VARS_JSON="$(gh variable list --repo "$GITHUB_REPO" --json name,value 2>/dev/null)" \
   || [ -z "$VARS_JSON" ]; then
  # A failed list is not proof of absence (403 and a rate limit look
  # alike), so nothing is concluded from it. In check mode that is a
  # failure — a clean bill of health cannot be issued from a read that
  # did not happen. In apply and dry-run modes the sets below still run
  # (apply already proved write access with the probe), unconditionally,
  # because "set" is the safe direction when the current value is
  # unknown.
  VARS_READABLE=0
  VARS_JSON="[]"
  if [ "$MODE" = "check" ]; then
    printf '    WRONG   could not list Actions variables on %s — reading them needs an admin token.\n' "$GITHUB_REPO"
    printf '            Nothing was concluded about their values.\n'
    CHECK_FAILED=1
  else
    printf '    WARNING could not list Actions variables on %s — setting them without comparing.\n' "$GITHUB_REPO"
  fi
fi

var_value() { # <name> -> current value or empty
  printf '%s' "$VARS_JSON" | jq -r --arg n "$1" '.[] | select(.name == $n) | .value' 2>/dev/null || true
}

ensure_variable() { # <name> <value>
  local name="$1" value="$2" current
  current="$(var_value "$name")"
  if [ "$VARS_READABLE" = "1" ] && [ "$current" = "$value" ]; then
    ok "variable $name = $value — kept"
  else
    run_or_print "set variable $name = $value" \
      gh variable set "$name" --body "$value" --repo "$GITHUB_REPO"
  fi
}

ensure_variable WIF_PROVIDER "$WIF_PROVIDER_FULL"
ensure_variable WIF_SERVICE_ACCOUNT "$SA_EMAIL"
ensure_variable CLAUDE_VERTEX_PROJECT_ID "$GCP_PROJECT"
ensure_variable ANTIGRAVITY_PROJECT_ID "$ANTIGRAVITY_PROJECT_ID"

# --- agy's second credential (#167) ---------------------------------------------
#
# Everything above provisions ONE credential: workload identity
# federation to $SA_EMAIL. That is all claude-code needs, because it
# calls Vertex. It is not enough for agy, and no amount of IAM makes it
# enough.
#
# agy ships no built-in model list. It fetches its catalog at startup
# from cloudcode-pa.googleapis.com, and that catalog is served per
# ANTIGRAVITY ENTITLEMENT of the calling identity — not per project and
# not per role. A federated service account holds no such entitlement,
# so the fetch returns nothing and agy then rejects every --model value
# with "not recognized as a known model". Measured 2026-09-07 on a
# GitHub-hosted runner: WIF service account -> 0 models ("timed out
# waiting for available models"); the same runner shape with an
# `authorized_user` ADC credential -> 15 models and a successful Pro
# call. ANTIGRAVITY_PROJECT_ID made no difference either way, and
# granting roles/serviceusage.serviceUsageConsumer made no difference.
#
# This script therefore cannot create it — it needs an interactive
# Google login by an entitled account. This block only reports it.
if gh secret list --repo "$GITHUB_REPO" --json name --jq '.[].name' 2>/dev/null \
     | grep -qx ANTIGRAVITY_ADC_JSON; then
  ok "secret ANTIGRAVITY_ADC_JSON (agy's user-entitled credential)"
else
  ABSENT+=("secret ANTIGRAVITY_ADC_JSON — antigravity personas resolve no model without it")
  cat <<EOF

==> MISSING: the repository secret ANTIGRAVITY_ADC_JSON.
    Until it is set, every antigravity persona (config/deployments.yaml)
    dies in ~17s on a runner with "model ... is not recognized" (#167).
    claude-code personas are unaffected.

    Provision it with an account entitled to Antigravity — preferably a
    dedicated one and NOT a human's daily account, because the file holds
    a long-lived refresh token:

      gcloud auth application-default login
      adc="\$(gcloud info --format='value(config.paths.global_config_dir)')/application_default_credentials.json"
      gh secret set ANTIGRAVITY_ADC_JSON --repo "$GITHUB_REPO" < "\$adc"

    Check that the account actually sees a catalog BEFORE uploading:

      AGY_ADC_AUTH=true ANTIGRAVITY_PROJECT_ID=$ANTIGRAVITY_PROJECT_ID agy models

    An empty list there means the account is not entitled and the secret
    will not help.
EOF
fi

# --- Summary -------------------------------------------------------------------
echo
echo "==> Values the workflow reads:"
echo "    WIF_PROVIDER             = $WIF_PROVIDER_FULL"
echo "    WIF_SERVICE_ACCOUNT      = $SA_EMAIL"
echo "    CLAUDE_VERTEX_PROJECT_ID = $GCP_PROJECT"
echo "    ANTIGRAVITY_PROJECT_ID   = $ANTIGRAVITY_PROJECT_ID"
echo
echo "==> Verified (already present and correct): ${#VERIFIED[@]}"
for item in ${VERIFIED[@]+"${VERIFIED[@]}"}; do echo "    - $item"; done
case "$MODE" in
  apply)
    echo "==> Created / changed this run: ${#CREATED[@]}"
    for item in ${CREATED[@]+"${CREATED[@]}"}; do echo "    - $item"; done
    ;;
  dry-run)
    echo "==> Would create / change: ${#PLANNED[@]}"
    for item in ${PLANNED[@]+"${PLANNED[@]}"}; do echo "    - $item"; done
    ;;
  check)
    echo "==> Missing: ${#ABSENT[@]}"
    for item in ${ABSENT[@]+"${ABSENT[@]}"}; do echo "    - $item"; done
    ;;
esac

if [ "$MODE" = "check" ]; then
  if [ "$CHECK_FAILED" -ne 0 ]; then
    echo
    echo "==> CHECK FAILED — run without --check to provision the missing pieces." >&2
    exit 1
  fi
  echo
  echo "==> CHECK PASSED — everything this script provisions is present and correct."
  exit 0
fi

cat <<EOF

==> Still manual (no script can do these):
    1. Enable the Claude models you pin in Vertex Model Garden for $GCP_PROJECT
       (console: Vertex AI -> Model Garden, one click per model, per project).
       Until then every predict call fails with a permission or
       "model not found" error even though WIF is correct.
    2. Repository Settings -> Actions -> General: allow the actions the
       workflow uses — actions/checkout, actions/setup-python, actions/cache,
       google-github-actions/auth. If a banner says this is managed at the
       organization level, an org owner must allow them there.
EOF
