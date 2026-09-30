#!/usr/bin/env bash
# Syncs the renee_perception package between this laptop and the Jetson
# (ssh alias "jetson", jump-hosted through the Vogui main board -- see
# vogui_ros1_ros2_bridge/docs/jetson_internet_access.md).
#
# Default (push): source code laptop -> Jetson (excludes data/, venv,
# caches) -- this is how code changes actually get tested, since the ZED
# camera is physically attached to the Jetson.
# --pull: captured data/ Jetson -> laptop instead (wraps the manual rsync
# command already documented in renee_perception/README.md). Pull never
# deletes local files: data/ has plenty of local-only datasets that were
# never on the Jetson, so --delete there would be destructive.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$SCRIPT_DIR/renee_perception"
JETSON_HOST="jetson"
JETSON_DIR="renee_ws/src/renee_perception"

DIRECTION="push"
DRY_RUN=0
DELETE=1

usage() {
  echo "Usage: $0 [--pull] [--dry-run] [--no-delete]"
  echo "  (default) push: sync source (excludes data/, venv, caches) laptop -> jetson"
  echo "  --pull: sync data/ jetson -> laptop instead (captured datasets, never deletes)"
  echo "  --dry-run: show what would change without copying anything"
  echo "  --no-delete: push only -- don't remove files on the jetson that don't exist locally"
  exit 1
}

for arg in "$@"; do
  case "$arg" in
    --pull) DIRECTION="pull" ;;
    --dry-run) DRY_RUN=1 ;;
    --no-delete) DELETE=0 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $arg" >&2; usage ;;
  esac
done

if ! command -v rsync >/dev/null 2>&1; then
  echo "ERROR: rsync is not installed." >&2
  exit 1
fi

if ! ssh -o BatchMode=yes -o ConnectTimeout=6 "$JETSON_HOST" true 2>/dev/null; then
  echo "ERROR: cannot reach '$JETSON_HOST' over ssh." >&2
  exit 1
fi

RSYNC_FLAGS=(-avz --progress)
[[ "$DRY_RUN" -eq 1 ]] && RSYNC_FLAGS+=(-n)

if [[ "$DIRECTION" == "push" ]]; then
  [[ "$DELETE" -eq 1 ]] && RSYNC_FLAGS+=(--delete)
  echo "== Pushing renee_perception source: laptop -> $JETSON_HOST =="
  [[ "$DRY_RUN" -eq 1 ]] && echo "(dry run -- nothing will actually be copied)"
  rsync "${RSYNC_FLAGS[@]}" \
    --exclude 'data/' --exclude 'venv/' --exclude '.venv/' --exclude '*.whl' \
    --exclude '__pycache__/' --exclude '*.pyc' --exclude '*.egg-info/' \
    --exclude '.pytest_cache/' --exclude '.vscode/' --exclude '.idea/' --exclude '.git/' \
    "$LOCAL_DIR/" "$JETSON_HOST:~/$JETSON_DIR/"
else
  echo "== Pulling renee_perception data: $JETSON_HOST -> laptop =="
  [[ "$DRY_RUN" -eq 1 ]] && echo "(dry run -- nothing will actually be copied)"
  rsync "${RSYNC_FLAGS[@]}" \
    "$JETSON_HOST:~/$JETSON_DIR/data/" "$LOCAL_DIR/data/"
fi

echo "Done."
