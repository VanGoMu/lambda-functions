#!/usr/bin/env bash
# Generic invoke script, reusable for any function under lambdas/<name>/.
# Invokes the deployed function with a JSON payload and prints the response.
#
# Usage: ./invoke.sh <lambda-dir> [--key value ...]
#   <lambda-dir>             Path to the function's directory (e.g. lambdas/hello-world)
#   --region <name>          AWS region                (default: eu-west-1)
#   --function-name <name>   Lambda function name        (default: <lambda-dir> basename)
#   --payload <path>         Path to a JSON payload file  (default: <lambda-dir>/event.json)
#
# Per-function defaults can also be set in <lambda-dir>/config.env — see
# scripts/README.md. Precedence: --flag > config.env > script default.
set -euo pipefail

# ─── Defaults ─────────────────────────────────────────────────────────────────
AWS_REGION="eu-west-1"
FUNCTION_NAME=""
PAYLOAD=""

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[$(date +%T)] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() { command -v "$1" &>/dev/null || die "'$1' is not installed."; }

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

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
    --payload)       PAYLOAD="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) die "Unknown argument: $1 (see --help)" ;;
  esac
done

FUNCTION_NAME="${FUNCTION_NAME:-$(basename "$LAMBDA_DIR")}"
PAYLOAD="${PAYLOAD:-$LAMBDA_DIR/event.json}"

# ─── Pre-flight checks ────────────────────────────────────────────────────────
require_cmd aws

[[ -f "$PAYLOAD" ]] || die "Payload file '$PAYLOAD' not found."

aws lambda get-function \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME" &>/dev/null \
  || die "Function '$FUNCTION_NAME' does not exist. Deploy it first with scripts/deploy.sh."

# ─── Invoke ───────────────────────────────────────────────────────────────────
OUT="$(mktemp)"
log "Invoking '$FUNCTION_NAME' with payload '$PAYLOAD'..."
aws lambda invoke \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME" \
  --cli-binary-format raw-in-base64-out \
  --payload "file://${PAYLOAD}" \
  "$OUT" >/dev/null

echo ""
echo "Response:"
cat "$OUT"
echo ""
rm -f "$OUT"
