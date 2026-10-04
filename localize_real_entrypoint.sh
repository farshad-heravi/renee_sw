#!/bin/bash
set -e
cd /renee
source install/setup.bash
# Real-robot localization against the map built by slam-real, analogous to
# how slam_real_entrypoint.sh relates to slam_entrypoint.sh: separate from
# localization_entrypoint.sh (Gazebo-sim `localize-sim` service, untouched)
# since the data source, params file, and clock (use_sim_time) all differ.
# Rover model for RViz's RobotModel display (the bridge relays no
# robot_description); navigation-real reuses this RViz window.
ros2 launch renee_bringup_utils real_robot_model.launch.py &
# Drop front-laser returns that hit the robot's own chassis before
# slam_toolbox sees them (scan_topic: /robot/front_laser/scan_filtered);
# unfiltered, they get mapped as specks along the driven path — see
# renee_bringup_utils/scan_footprint_filter.py.
scan_footprint_filter --ros-args -r __node:=front_scan_footprint_filter \
    -r scan_in:=/robot/front_laser/scan -r scan_out:=/robot/front_laser/scan_filtered &
ros2 run rviz2 rviz2 -d $RENEE_SRC_PATH/configs/slam_real.rviz &
# slam_toolbox localizes (robot_map -> robot_odom) but its live, re-rendered
# map goes to /slam_map; map_server serves the fixed maps/${REAL_MAP}.yaml on
# /map for Nav2's static layer (same launch as the Gazebo-sim `localize-sim`,
# see localization_sim.launch.py). REAL_MAP selects both the map yaml/pgm and
# the slam_toolbox posegraph, so they must come from the same save.
REAL_MAP=${REAL_MAP:-real_robot_environment_v4}
echo "[localize_real] REAL_MAP=$REAL_MAP"
ros2 launch renee_bringup_utils localization_sim.launch.py use_sim_time:=false \
    slam_params_file:=$RENEE_SRC_PATH/configs/mapper_params_localization_real.yaml \
    map:=$RENEE_SRC_PATH/maps/$REAL_MAP.yaml \
    map_file_name:=$RENEE_SRC_PATH/maps/$REAL_MAP
