#!/usr/bin/env bash
# Grabs the Vogui+ block (wheel odom, AMCL pose, IMU, full /tf and /tf_static)
# for one camera pose within a scan station of the D435i dataset, plus an
# auto-filled notes.txt with a pose snapshot from robot_map->robot_base_footprint.
# Each station has 2 camera poses (per the scan plan), so run this twice per
# station — same station_id, pose_id 1 then 2 — with the rover settled and
# q unchanged across both.
#
# Writes straight to CSV/YAML (no ros2_bag record/play): the container image
# has no rosbag2 ('ros2 bag' is not a valid subcommand here), so each topic
# is echoed live for the capture window instead of going through a bag.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Same root record_data.py uses by default (REPO_ROOT/data inside
# renee_perception), so vogui/ and realsense/ end up under the same dataset
# tree with nothing to move afterwards.
DEFAULT_OUTDIR="$SCRIPT_DIR/renee_perception/data/dataset"

STATION="${1:-}"
POSE="${2:-}"
DURATION="${3:-8}"
OUTDIR="${4:-$DEFAULT_OUTDIR}"

if [[ -z "$STATION" || -z "$POSE" ]]; then
  echo "Usage: $0 <station_id> <pose_id> [duration_seconds=8] [outdir=$DEFAULT_OUTDIR]"
  echo "  pose_id: 1 or 2 (each station has 2 camera poses)"
  exit 1
fi

STATION_DIR="$OUTDIR/station_${STATION}/pose_${POSE}/vogui"
CSV_DIR="$STATION_DIR/csv"

if [[ -e "$STATION_DIR" ]]; then
  echo "$STATION_DIR already exists — delete it or use a different station_id/pose_id." >&2
  exit 1
fi
mkdir -p "$CSV_DIR"

if ! command -v ros2 >/dev/null 2>&1; then
  echo "ERROR: 'ros2' is not on this shell's PATH (did you run this with sudo? that wipes the environment)." >&2
  echo "Nothing was recorded. Run without sudo, from a shell with ROS2 already sourced." >&2
  exit 1
fi

echo "== Station $STATION / pose $POSE =="
echo "Recording ${DURATION}s to: $CSV_DIR"
read -rp "Rover settled, q unchanged, camera at pose $POSE? Press Enter to start recording... "

timeout "${DURATION}s" ros2 topic echo /robot/robotnik_base_control/odom --csv > "$CSV_DIR/odom.csv" &
PIDS=($!)
timeout "${DURATION}s" ros2 topic echo /robot/amcl_pose --csv > "$CSV_DIR/amcl.csv" &
PIDS+=($!)
timeout "${DURATION}s" ros2 topic echo /robot/imu/data --csv > "$CSV_DIR/imu.csv" &
PIDS+=($!)
timeout "${DURATION}s" ros2 topic echo /tf > "$CSV_DIR/tf.yaml" &
PIDS+=($!)
timeout "${DURATION}s" ros2 topic echo /tf_static > "$CSV_DIR/tf_static.yaml" &
PIDS+=($!)
timeout "${DURATION}s" ros2 topic echo /joint_states --csv > "$CSV_DIR/joint_states.csv" &
PIDS+=($!)

wait "${PIDS[@]}" 2>/dev/null || true
echo "Recording finished."

for f in odom.csv amcl.csv imu.csv tf.yaml tf_static.yaml joint_states.csv; do
  size=$(stat -c%s "$CSV_DIR/$f" 2>/dev/null || echo 0)
  if [[ "$size" -eq 0 ]]; then
    echo "WARNING: $f is empty (0 bytes) — that topic published nothing during the capture." >&2
  fi
done

# `ros2 topic echo --csv` writes its header before receiving any messages.  A
# header-only file is therefore non-empty but contains no usable joint state;
# this is the 67-byte failure mode seen in previous sessions.
JOINT_FILE="$CSV_DIR/joint_states.csv"
JOINT_SIZE=$(stat -c%s "$JOINT_FILE" 2>/dev/null || echo 0)
JOINT_LINES=$(awk 'NF { count++ } END { print count + 0 }' "$JOINT_FILE" 2>/dev/null || echo 0)
if [[ "$JOINT_LINES" -le 1 ]]; then
  echo "ERROR: joint_states.csv has only its CSV header; /joint_states published no samples." >&2
  echo "       Fix the joint-state publisher and repeat this capture." >&2
elif [[ "$JOINT_SIZE" -lt 1024 ]]; then
  echo "WARNING: joint_states.csv is only ${JOINT_SIZE} bytes; verify that it contains the full arm state." >&2
else
  echo "joint_states.csv check passed: ${JOINT_LINES} non-empty lines, ${JOINT_SIZE} bytes."
fi

# Best-effort pose snapshot for the manual notes.
POSE_SNAPSHOT=$(timeout 3s ros2 run tf2_ros tf2_echo robot_map robot_base_footprint 2>/dev/null \
  | grep -A5 "^At time" | tail -n 6 || true)

NOTES_FILE="$STATION_DIR/notes.txt"
{
  echo "Station: $STATION"
  echo "Camera pose: $POSE"
  echo "Capture timestamp: $(date -Iseconds)"
  echo ""
  echo "Approximate pose (robot_map -> robot_base_footprint), automatic snapshot:"
  if [[ -n "$POSE_SNAPSHOT" ]]; then
    echo "$POSE_SNAPSHOT"
  else
    echo "  (could not read robot_map->robot_base_footprint at capture time)"
  fi
  echo ""
  echo "--- Fill in by hand ---"
  echo "Approximate position/heading (if different from the snapshot): "
  echo "Rover fully settled before capture (yes/no): "
  echo "Floor condition (smooth/dirty/reflective/jointed): "
  echo "Campetella axes stayed fixed for the entire sweep (yes/no): "
  echo "Axis configuration (choose one):"
  echo "  All axes at end stops — directions X: ___  Y: ___  Z: ___"
  echo "  Controller readout [mm] — X: ___  Y: ___  Z: ___"
  echo "  Controller sign convention: "
  echo "If camera is arm-mounted:"
  echo "  UR5 joints logged live in joint_states.csv (check it isn't empty)"
  echo "  Hand-eye transform source (calibrated / CAD): CAD as of this session — confirm"
  echo "Additional notes: "
} > "$NOTES_FILE"
echo "Notes created at: $NOTES_FILE (fill in the manual fields)"

echo "Done with station $STATION / pose $POSE. CSV/YAML in: $CSV_DIR"
