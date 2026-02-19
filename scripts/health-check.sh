#!/usr/bin/env bash
# health-check.sh
# Usage: ./health-check.sh <folder-path>

set -euo pipefail

# ─── Colours ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Colour

OK()   { echo -e "${GREEN}  [✔]${NC} $*"; }
FAIL() { echo -e "${RED}  [✘]${NC} $*"; }
INFO() { echo -e "${CYAN}  [i]${NC} $*"; }
WARN() { echo -e "${YELLOW}  [!]${NC} $*"; }

die() {
  FAIL "$*"
  exit 1
}

# ─── Argument validation ─────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  die "No folder path provided.\n  Usage: $0 <folder-path>"
fi

FOLDER="$1"

echo ""
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "${CYAN}  Artifact Validation Script             ${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"
INFO "Target folder : $FOLDER"
echo ""

# ─── 1. Folder existence ─────────────────────────────────────────────────────
if [[ ! -d "$FOLDER" ]]; then
  die "Folder does not exist: '$FOLDER'"
fi
OK "Folder exists"

# ─── 2. Locate the .jar file ──────────────────────────────────────────────────
JAR_FILES=("$FOLDER"/*.jar)

if [[ ! -e "${JAR_FILES[0]}" ]]; then
  die "No .jar file found in '$FOLDER'"
fi

if [[ ${#JAR_FILES[@]} -gt 1 ]]; then
  WARN "Multiple .jar files found; using the first one: ${JAR_FILES[0]}"
fi

JAR="${JAR_FILES[0]}"
OK ".jar file found  : $(basename "$JAR")"

# ─── 3. version.txt exists and is non-empty ───────────────────────────────────
VERSION_FILE="$FOLDER/version.txt"

if [[ ! -f "$VERSION_FILE" ]]; then
  die "version.txt not found in '$FOLDER'"
fi

if [[ ! -s "$VERSION_FILE" ]]; then
  die "version.txt exists but is empty"
fi

VERSION=$(cat "$VERSION_FILE")
OK "version.txt     : $VERSION"

# ─── 4. .jar size > 1 MB ──────────────────────────────────────────────────────
MIN_SIZE_BYTES=$((1 * 1024 * 1024))   # 1 MB

# macOS uses -f %z; Linux uses -c %s — handle both
if stat --version &>/dev/null 2>&1; then
  JAR_SIZE=$(stat -c %s "$JAR")       # GNU/Linux
else
  JAR_SIZE=$(stat -f %z "$JAR")       # macOS/BSD
fi

JAR_SIZE_MB=$(echo "scale=2; $JAR_SIZE / 1048576" | bc)

if [[ "$JAR_SIZE" -le "$MIN_SIZE_BYTES" ]]; then
  die ".jar file is too small (${JAR_SIZE_MB} MB). Expected > 1 MB. Possible corrupt or truncated upload."
fi
OK ".jar size       : ${JAR_SIZE_MB} MB  (> 1 MB threshold)"

# ─── 5. (Bonus) Smoke-test: start the jar and watch for startup log ───────────
echo ""
INFO "Starting smoke test (timeout: 60s) ..."

LOG_FILE=$(mktemp /tmp/petclinic-smoke-XXXXXX.log)
STARTUP_MARKER="Started PetClinicApplication"
TIMEOUT_SECS=60
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    INFO "Stopping application (PID $APP_PID) ..."
    kill "$APP_PID" 2>/dev/null
    wait "$APP_PID" 2>/dev/null || true
    OK "Process terminated cleanly"
  fi
  rm -f "$LOG_FILE"
}
trap cleanup EXIT

# Launch the jar in the background; redirect all output to log file
java -jar "$JAR" --server.port=0 > "$LOG_FILE" 2>&1 &
APP_PID=$!
INFO "Application PID : $APP_PID  |  Log: $LOG_FILE"

# Poll for the startup marker every second
ELAPSED=0
STARTED=false

while [[ $ELAPSED -lt $TIMEOUT_SECS ]]; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    FAIL "Application process exited unexpectedly after ${ELAPSED}s"
    echo ""
    echo -e "${YELLOW}--- Last 20 lines of application log ---${NC}"
    tail -n 20 "$LOG_FILE" || true
    echo -e "${YELLOW}----------------------------------------${NC}"
    exit 1
  fi

  if grep -q "$STARTUP_MARKER" "$LOG_FILE" 2>/dev/null; then
    STARTED=true
    break
  fi

  sleep 1
  (( ELAPSED++ ))
done

if [[ "$STARTED" == "true" ]]; then
  OK "Application started successfully in ${ELAPSED}s  ('$STARTUP_MARKER' detected)"
else
  FAIL "Application did NOT produce '$STARTUP_MARKER' within ${TIMEOUT_SECS}s"
  echo ""
  echo -e "${YELLOW}--- Last 20 lines of application log ---${NC}"
  tail -n 20 "$LOG_FILE" || true
  echo -e "${YELLOW}----------------------------------------${NC}"
  exit 1
fi

# ─── All checks passed ────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  All validation checks passed ✔        ${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
exit 0
