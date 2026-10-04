#!/bin/bash
set -e
cd /renee
source install/setup.bash
# Real-robot Nav2 bring-up, analogous to navigation_entrypoint.sh (Gazebo-sim
# `navigate-sim` service). Two overrides beyond use_sim:=false, both required
# for the vogui_ros1_ros2_bridge path (see nav2_task.launch.py comments):
# - controller_config/behavior_config: the _real.yaml variants, which set
#   enable_stamped_cmd_vel: false and use_sim_time: false in their nested
#   local_costmap/behavior_server blocks.
# - cmd_vel_topic:=move_base/cmd_vel: the only cmd_vel topic the bridge
#   relays into the robot's twist_mux.
# Plus a collision_monitor between Nav2 and move_base/cmd_vel (the rover's own
# safety lasers/PLC are not active — see collision_monitor_real.yaml).
# COLLISION_MODE picks the lasers it uses: both (default) | front | rear | none;
# switch at runtime with `ros2 run renee_rbvogui_navigation collision_mode <mode>`.
# Rear laser feeds the local costmap too (RPP can reverse); drop its
# chassis self-hits the same way localize_real does for the front laser.
scan_footprint_filter --ros-args -r __node:=rear_scan_footprint_filter \
    -r scan_in:=/robot/rear_laser/scan -r scan_out:=/robot/rear_laser/scan_filtered &
ros2 launch renee_rbvogui_navigation navigation.launch.py use_sim:=false robot_id:=robot \
    controller_config:=$RENEE_SRC_PATH/renee_rbvogui_navigation/config/controller_server_real.yaml \
    planner_config:=$RENEE_SRC_PATH/renee_rbvogui_navigation/config/planner_server_real.yaml \
    bt_nav_to_pose_xml:=$RENEE_SRC_PATH/renee_rbvogui_navigation/config/behavior_trees/navigate_to_pose_real.xml \
    behavior_config:=$RENEE_SRC_PATH/renee_rbvogui_navigation/config/behavior_server_real.yaml \
    cmd_vel_topic:=move_base/cmd_vel \
    use_collision_monitor:=true \
    collision_monitor_config:=$RENEE_SRC_PATH/renee_rbvogui_navigation/config/collision_monitor_real.yaml \
    collision_mode:=${COLLISION_MODE:-both}
