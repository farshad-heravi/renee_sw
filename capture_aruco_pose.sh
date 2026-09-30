#!/usr/bin/env bash
# Grabs the arm/robot state (joint_states, full /tf and /tf_static, wheel odom,
# AMCL pose) for one arm pose of a hand-eye (ArUco) calibration sequence.
# Vogui+ stays put for the whole sequence — only the UR5 arm moves, driven
# through MoveIt — so each capture is one calibration sample: the joint
# angles (for FK to the camera frame) plus a pose snapshot to confirm the
# base really didn't drift between poses.
#
# Also triggers the ZED/ArUco image capture on the Jetson (the camera is
# physically attached there, not to this laptop) over ssh, pulling the
# result back into the same pose folder.
#
# Run once per arm pose, same capture_id across the whole sequence's poses
# (1, 2, 3, ...), after MoveIt has settled into the new pose and before
# moving to the next.
#
# TODO: fully automate the sequence -- drive the arm through a pre-generated
# list of MoveIt poses and call this capture for each one automatically,
# instead of the current manual "move arm, run script, repeat" loop. Not
# doing this yet.
#
# Requires:
# - ROS2 already sourced in this shell (not sudo).
# - An ssh alias "jetson" that reaches the Jetson (jump host through the
#   Vogui main board — see vogui_ros1_ros2_bridge/docs/jetson_internet_access.md)
#   with tools/zed_aruco_detect.py present under ~/renee_ws/src/renee_perception there.
#
# Writes straight to CSV/YAML (no ros2_bag record/play): the container image
# has no rosbag2 ('ros2 bag' is not a valid subcommand here), so each topic
# is echoed live for the capture window instead of going through a bag.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_OUTDIR="$SCRIPT_DIR/renee_perception/data/aruco_calibration"

JETSON_HOST="jetson"
JETSON_REPO_DIR="renee_ws/src/renee_perception"  # relative to the jetson user's $HOME
CAMERA_TIMEOUT="${CAMERA_TIMEOUT:-15}"   # seconds to wait for a stable ArUco detection

POSE="${1:-}"
DURATION="${2:-5}"
OUTDIR="${3:-$DEFAULT_OUTDIR}"
MARKER_ID="${4:-}"          # optional: restrict detection to one marker ID
MARKER_SIZE="${5:-0.060}"   # metres, must match the physical marker's outer black square

if [[ -z "$POSE" ]]; then
  echo "Usage: $0 <pose_id> [duration_seconds=5] [outdir=$DEFAULT_OUTDIR] [marker_id] [marker_size_m=0.060]"
  echo "  pose_id: sequence number of this arm pose (1, 2, 3, ...)"
  echo "  Also runs tools/zed_aruco_detect.py --save-once on the Jetson (ssh host '$JETSON_HOST')"
  echo "  and pulls the resulting left.png/annotated.png/pose.json back into pose_<N>/camera/."
  exit 1
fi

POSE_DIR="$OUTDIR/pose_${POSE}"
CSV_DIR="$POSE_DIR/csv"
CAMERA_DIR="$POSE_DIR/camera"

if [[ -e "$POSE_DIR" ]]; then
  echo "$POSE_DIR already exists — delete it or use a different pose_id." >&2
  exit 1
fi
mkdir -p "$CSV_DIR"

if ! command -v ros2 >/dev/null 2>&1; then
  echo "ERROR: 'ros2' is not on this shell's PATH (did you run this with sudo? that wipes the environment)." >&2
  echo "Nothing was recorded. Run without sudo, from a shell with ROS2 already sourced." >&2
  exit 1
fi

CAMERA_OK=1
if ! ssh -o BatchMode=yes -o ConnectTimeout=6 "$JETSON_HOST" true 2>/dev/null; then
  echo "WARNING: cannot reach '$JETSON_HOST' over ssh — camera capture will be skipped, robot state still recorded." >&2
  CAMERA_OK=0
fi

echo "== ArUco calibration pose $POSE =="
echo "Recording ${DURATION}s to: $CSV_DIR"
read -rp "Vogui static, arm settled at pose $POSE via MoveIt? Press Enter to start recording... "

REMOTE_DIR="${JETSON_REPO_DIR}/aruco_captures/pose_${POSE}"

if [[ "$CAMERA_OK" -eq 1 ]]; then
  if ! ssh "$JETSON_HOST" "mkdir -p ~/$REMOTE_DIR"; then
    echo "WARNING: could not create the remote capture dir on '$JETSON_HOST' — camera capture will be skipped, robot state still recorded." >&2
    CAMERA_OK=0
  fi
fi

if [[ "$CAMERA_OK" -eq 1 ]]; then
  CAMERA_CMD="cd ~/$JETSON_REPO_DIR && python3 tools/zed_aruco_detect.py --headless --save-once --output ~/$REMOTE_DIR --size $MARKER_SIZE --timeout $CAMERA_TIMEOUT"
  if [[ -n "$MARKER_ID" ]]; then
    CAMERA_CMD="$CAMERA_CMD --id $MARKER_ID"
  fi
  ssh "$JETSON_HOST" "$CAMERA_CMD" > "$POSE_DIR/jetson_capture.log" 2>&1 &
  CAMERA_PID=$!
fi

timeout "${DURATION}s" ros2 topic echo /joint_states --csv > "$CSV_DIR/joint_states.csv" &
PIDS=($!)
timeout "${DURATION}s" ros2 topic echo /tf > "$CSV_DIR/tf.yaml" &
PIDS+=($!)
timeout "${DURATION}s" ros2 topic echo /tf_static > "$CSV_DIR/tf_static.yaml" &
PIDS+=($!)
timeout "${DURATION}s" ros2 topic echo /robot/robotnik_base_control/odom --csv > "$CSV_DIR/odom.csv" &
PIDS+=($!)
timeout "${DURATION}s" ros2 topic echo /robot/amcl_pose --csv > "$CSV_DIR/amcl.csv" &
PIDS+=($!)

wait "${PIDS[@]}" 2>/dev/null || true
echo "ROS recording finished."

CAMERA_CAPTURED=0
if [[ "$CAMERA_OK" -eq 1 ]]; then
  echo "Waiting for the Jetson's ArUco capture to finish (up to ${CAMERA_TIMEOUT}s)..."
  if wait "$CAMERA_PID"; then
    mkdir -p "$CAMERA_DIR"
    if scp -rq "$JETSON_HOST:~/$REMOTE_DIR/." "$CAMERA_DIR/" 2>>"$POSE_DIR/jetson_capture.log"; then
      echo "Camera capture pulled to: $CAMERA_DIR"
      CAMERA_CAPTURED=1
    else
      echo "WARNING: Jetson capture succeeded but pulling the files back failed — check $POSE_DIR/jetson_capture.log" >&2
    fi
  else
    echo "WARNING: Jetson ArUco capture failed or timed out — check $POSE_DIR/jetson_capture.log" >&2
    echo "         (common causes: marker not visible, pose too close to head-on causing repeated flips)" >&2
  fi
fi

for f in joint_states.csv tf.yaml tf_static.yaml odom.csv amcl.csv; do
  size=$(stat -c%s "$CSV_DIR/$f" 2>/dev/null || echo 0)
  if [[ "$size" -eq 0 ]]; then
    echo "WARNING: $f is empty (0 bytes) — that topic published nothing during the capture." >&2
  fi
done

# `ros2 topic echo --csv` writes its header before receiving any messages.  A
# header-only file is therefore non-empty but contains no usable joint state;
# this is the 67-byte failure mode seen in previous sessions (capture_station.sh).
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

# Best-effort pose snapshot of the base, to confirm Vogui didn't drift
# between arm poses in the sequence.
POSE_SNAPSHOT=$(timeout 3s ros2 run tf2_ros tf2_echo robot_map robot_base_footprint 2>/dev/null \
  | grep -A5 "^At time" | tail -n 6 || true)

NOTES_FILE="$POSE_DIR/notes.txt"
{
  echo "ArUco calibration — arm pose: $POSE"
  echo "Capture timestamp: $(date -Iseconds)"
  echo ""
  echo "Base pose (robot_map -> robot_base_footprint), automatic snapshot:"
  if [[ -n "$POSE_SNAPSHOT" ]]; then
    echo "$POSE_SNAPSHOT"
  else
    echo "  (could not read robot_map->robot_base_footprint at capture time)"
  fi
  echo ""
  echo "Camera capture (Jetson, zed_aruco_detect.py --save-once):"
  if [[ "$CAMERA_CAPTURED" -eq 1 ]]; then
    echo "  Pulled to: $CAMERA_DIR (left.png, annotated.png, pose.json)"
  else
    echo "  NOT captured automatically this run — check $POSE_DIR/jetson_capture.log, or run"
    echo "  tools/zed_aruco_detect.py manually on the Jetson for this pose."
  fi
  echo ""
  echo "--- Fill in by hand ---"
  echo "Vogui base stayed static for the whole sequence (yes/no): "
  echo "Arm moved via MoveIt to this pose (yes/no): "
  echo "ArUco board fully visible in the corresponding image capture (yes/no): "
  echo "ArUco board static / fixed in the scene (yes/no): "
  echo "UR5 joints logged live in joint_states.csv (check it isn't empty)"
  echo "Hand-eye transform source (calibrated / CAD): CAD as of this session — confirm"
  echo "Additional notes: "
} > "$NOTES_FILE"
echo "Notes created at: $NOTES_FILE (fill in the manual fields)"

echo "Done with pose $POSE. CSV/YAML in: $CSV_DIR"
