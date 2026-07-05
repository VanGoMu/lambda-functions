#!/usr/bin/env bash
# Generic deploy script, reusable for any function under lambdas/<name>/.
# Creates the IAM execution role (if missing) and the Lambda function
# (creates it on first run, updates code + config on later runs).
# To undo everything this script creates, run ./undeploy.sh <lambda-dir>
#
# Usage: ./deploy.sh <lambda-dir> [--key value ...]
#   <lambda-dir>             Path to the function's directory (e.g. lambdas/hello-world)
#   --region <name>          AWS region                              (default: eu-west-1)
#   --function-name <name>   Lambda function name                    (default: <lambda-dir> basename)
#   --runtime <name>         Lambda runtime                           (default: python3.13)
#   --architecture <name>    arm64 | x86_64                           (default: arm64)
#   --handler <name>         file.method                              (default: lambda_function.lambda_handler)
#   --memory-size <MB>       Memory in MB (128-10240)                 (default: 128)
#   --timeout <seconds>      Max execution time (max 900)             (default: 10)
#   --role-name <name>       IAM execution role name                  (default: <function-name>-role)
#   --env-vars <"K=V,K2=V2"> Lambda environment variables               (default: none)
#
# Per-function defaults can also be set in <lambda-dir>/config.env — see
# scripts/README.md. Precedence: --flag > config.env > script default.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Defaults ─────────────────────────────────────────────────────────────────
AWS_REGION="eu-west-1"
FUNCTION_NAME=""
RUNTIME="python3.13"
ARCHITECTURE="arm64"          # arm64 (cheaper) | x86_64
HANDLER="lambda_function.lambda_handler"
MEMORY_SIZE="128"
TIMEOUT="10"
ROLE_NAME=""
LAMBDA_ENV_VARS=""

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[$(date +%T)] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() { command -v "$1" &>/dev/null || die "'$1' is not installed."; }

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

function_exists() {
  aws lambda get-function \
    --region "$AWS_REGION" \
    --function-name "$FUNCTION_NAME" &>/dev/null
}

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
    --runtime)       RUNTIME="$2"; shift 2 ;;
    --architecture)  ARCHITECTURE="$2"; shift 2 ;;
    --handler)       HANDLER="$2"; shift 2 ;;
    --memory-size)   MEMORY_SIZE="$2"; shift 2 ;;
    --timeout)       TIMEOUT="$2"; shift 2 ;;
    --role-name)     ROLE_NAME="$2"; shift 2 ;;
    --env-vars)      LAMBDA_ENV_VARS="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) die "Unknown argument: $1 (see --help)" ;;
  esac
done

FUNCTION_NAME="${FUNCTION_NAME:-$(basename "$LAMBDA_DIR")}"
ROLE_NAME="${ROLE_NAME:-${FUNCTION_NAME}-role}"

HANDLER_FILE="${HANDLER%%.*}.py"
[[ -f "$LAMBDA_DIR/$HANDLER_FILE" ]] || die "Handler file '$LAMBDA_DIR/$HANDLER_FILE' not found (expected from --handler '$HANDLER')."

# ─── Pre-flight checks ────────────────────────────────────────────────────────
require_cmd aws
require_cmd zip

aws sts get-caller-identity --region "$AWS_REGION" &>/dev/null \
  || die "AWS credentials not configured or invalid."

# ─── IAM: execution role (every function needs one to write to CloudWatch Logs) ──
log "Checking execution role '$ROLE_NAME'..."
if ! aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
  log "Not found — creating it (first deploy of this function)."
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  log "Waiting for IAM propagation (10s)..."
  sleep 10
else
  log "Execution role already exists."
fi

ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text)

# ─── Package the code ─────────────────────────────────────────────────────────
log "Packaging '$LAMBDA_DIR'..."
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

shopt -s dotglob nullglob
for f in "$LAMBDA_DIR"/*; do
  base="$(basename "$f")"
  case "$base" in
    config.env|README.md|event.json|requirements.txt|__pycache__|*.pyc) continue ;;
  esac
  cp -r "$f" "$BUILD_DIR/"
done
shopt -u dotglob nullglob

if [[ -f "$LAMBDA_DIR/requirements.txt" ]]; then
  require_cmd pip3
  log "Installing dependencies from requirements.txt..."
  pip3 install -q -r "$LAMBDA_DIR/requirements.txt" --target "$BUILD_DIR" --upgrade
fi

ZIP_PATH="$(mktemp -u --suffix=.zip)"
(cd "$BUILD_DIR" && zip -qr "$ZIP_PATH" .)
log "Packaged at $ZIP_PATH"

ENV_ARG=()
[[ -n "$LAMBDA_ENV_VARS" ]] && ENV_ARG=(--environment "Variables={${LAMBDA_ENV_VARS}}")

# ─── Function: create if new, update code + config if it already exists ──────
if function_exists; then
  log "Function '$FUNCTION_NAME' already exists — updating code..."
  aws lambda update-function-code \
    --region "$AWS_REGION" \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://${ZIP_PATH}" >/dev/null

  aws lambda wait function-updated \
    --region "$AWS_REGION" \
    --function-name "$FUNCTION_NAME"

  log "Updating configuration..."
  aws lambda update-function-configuration \
    --region "$AWS_REGION" \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --handler "$HANDLER" \
    --memory-size "$MEMORY_SIZE" \
    --timeout "$TIMEOUT" \
    "${ENV_ARG[@]}" >/dev/null
else
  log "Creating function '$FUNCTION_NAME'..."
  aws lambda create-function \
    --region "$AWS_REGION" \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --architectures "$ARCHITECTURE" \
    --handler "$HANDLER" \
    --role "$ROLE_ARN" \
    --memory-size "$MEMORY_SIZE" \
    --timeout "$TIMEOUT" \
    "${ENV_ARG[@]}" \
    --zip-file "fileb://${ZIP_PATH}" >/dev/null
fi

rm -f "$ZIP_PATH"

log "Waiting for function to become active..."
aws lambda wait function-active-v2 \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME"

FUNCTION_ARN=$(aws lambda get-function \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME" \
  --query "Configuration.FunctionArn" --output text)

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo " Function deployed successfully"
echo "========================================"
echo "  Source       : $LAMBDA_DIR"
echo "  Name         : $FUNCTION_NAME"
echo "  Runtime      : $RUNTIME ($ARCHITECTURE)"
echo "  Memory       : ${MEMORY_SIZE} MB"
echo "  Timeout      : ${TIMEOUT}s"
echo "  Region       : $AWS_REGION"
echo "  Role         : $ROLE_ARN"
echo "  ARN          : $FUNCTION_ARN"
echo ""
echo "  Invoke : ${SCRIPT_DIR}/invoke.sh $LAMBDA_DIR --region $AWS_REGION"
echo "  Logs   : aws logs tail /aws/lambda/${FUNCTION_NAME} --follow --region ${AWS_REGION}"
echo "  Undo   : ${SCRIPT_DIR}/undeploy.sh $LAMBDA_DIR --region $AWS_REGION (add --with-role to also remove the IAM role)"
echo "========================================"
