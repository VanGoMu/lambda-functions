#!/usr/bin/env bash
# Generic undeploy script, reusable for any function under lambdas/<name>/.
# Undoes everything ./deploy.sh created: deletes the Lambda function and,
# if --with-role is passed, the IAM execution role too.
#
# Usage: ./undeploy.sh <lambda-dir> [--key value ...] [--with-role]
#   <lambda-dir>             Path to the function's directory (e.g. lambdas/hello-world)
#   --region <name>          AWS region                          (default: eu-west-1)
#   --function-name <name>   Lambda function name                  (default: <lambda-dir> basename)
#   --role-name <name>       IAM execution role name                (default: <function-name>-role)
#   --with-role              Also delete the IAM execution role
#
# Per-function defaults can also be set in <lambda-dir>/config.env — see
# scripts/README.md. Precedence: --flag > config.env > script default.
set -euo pipefail

# ─── Defaults ─────────────────────────────────────────────────────────────────
AWS_REGION="eu-west-1"
FUNCTION_NAME=""
ROLE_NAME=""
WITH_ROLE=false

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[$(date +%T)] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() { command -v "$1" &>/dev/null || die "'$1' is not installed."; }

usage() { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# ─── Positional argument: lambda directory ────────────────────────────────────
[[ $# -gt 0 && "$1" != --* ]] || { usage; die "missing <lambda-dir> argument."; }
LAMBDA_DIR="$1"; shift
[[ -d "$LAMBDA_DIR" ]] || die "Directory '$LAMBDA_DIR' not found."

# ─── Per-function defaults (optional) ─────────────────────────────────────────
if [[ -f "$LAMBDA_DIR/config.env" ]]; then
  # shellcheck disable=SC1091
  source "$LAMBDA_DIR/config.env"
fi

# ─── Argument parsing (overrides config.env and script defaults) ─────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)        AWS_REGION="$2"; shift 2 ;;
    --function-name) FUNCTION_NAME="$2"; shift 2 ;;
    --role-name)     ROLE_NAME="$2"; shift 2 ;;
    --with-role)     WITH_ROLE=true; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) die "Unknown argument: $1 (see --help)" ;;
  esac
done

FUNCTION_NAME="${FUNCTION_NAME:-$(basename "$LAMBDA_DIR")}"
ROLE_NAME="${ROLE_NAME:-${FUNCTION_NAME}-role}"

# ─── Pre-flight checks ────────────────────────────────────────────────────────
require_cmd aws

aws sts get-caller-identity --region "$AWS_REGION" &>/dev/null \
  || die "AWS credentials not configured or invalid."

# ─── Delete the function ──────────────────────────────────────────────────────
if aws lambda get-function --region "$AWS_REGION" --function-name "$FUNCTION_NAME" &>/dev/null; then
  log "Deleting function '$FUNCTION_NAME'..."
  aws lambda delete-function \
    --region "$AWS_REGION" \
    --function-name "$FUNCTION_NAME"
  log "Function deleted."
else
  log "Function '$FUNCTION_NAME' does not exist — nothing to delete."
fi

# ─── Delete the IAM role (only if requested — it may be shared) ──────────────
if $WITH_ROLE; then
  if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    log "Detaching policies and deleting role '$ROLE_NAME'..."
    aws iam detach-role-policy \
      --role-name "$ROLE_NAME" \
      --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
    aws iam delete-role --role-name "$ROLE_NAME"
    log "Role deleted."
  else
    log "Role '$ROLE_NAME' does not exist — nothing to delete."
  fi
else
  log "Keeping IAM role '$ROLE_NAME' (pass --with-role to delete it too)."
fi

log "Done."
