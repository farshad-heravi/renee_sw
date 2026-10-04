#!/bin/bash
set -e
cd /renee
source install/setup.bash
# UR_HEADLESS_MODE=true: pendant in Remote mode, the driver sends the control
# script itself. false: start External Control on the pendant (Local mode).
# UR_ROBOT_IP: the arm's LAN address. UR_REVERSE_IP: this host's address on
# that same LAN (the External Control URCap on the pendant must point at it).
# Standalone arm: no rover TF/localization is running, so give MoveIt a fixed
# robot_map (identity) and the rover's fixed footprint->base->chassis offsets
# (rbvogui URDF) that the arm TF hangs from. Set UR_STATIC_MAP_TF=false when the
# rover stack (bridge-real/localize-real) is also up: it already owns these frames.
if [ "${UR_STATIC_MAP_TF:-true}" = "true" ]; then
    ros2 run tf2_ros static_transform_publisher --frame-id robot_map --child-frame-id robot_base_footprint &
    ros2 run tf2_ros static_transform_publisher --z 0.1165 --frame-id robot_base_footprint --child-frame-id robot_base_link &
    ros2 run tf2_ros static_transform_publisher --x -0.012 --z 0.1775 --frame-id robot_base_link --child-frame-id robot_chassis_link &
fi
ros2 launch renee_rbvogui_plus_moveit_config start_moveit_real.launch.py \
    robot_ip:=${UR_ROBOT_IP:-192.168.0.101} \
    reverse_ip:=${UR_REVERSE_IP:-192.168.0.150} \
    kinematics_params_file:=${UR_KINEMATICS_FILE:-/renee/ur5e_calibration.yaml} \
    headless_mode:=${UR_HEADLESS_MODE:-true} \
    end_effector:=${UR_END_EFFECTOR:-none} \
    use_rviz:=${UR_USE_RVIZ:-true}
