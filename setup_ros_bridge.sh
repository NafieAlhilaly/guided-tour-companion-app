#!/bin/bash

echo "================================================"
echo "ROS2 Gazebo Image Bridge Setup Script"
echo "================================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if ROS2 is sourced
if [ -z "$ROS_DISTRO" ]; then
    echo -e "${YELLOW}Warning: ROS2 environment not sourced${NC}"
    echo "Please source your ROS2 installation first:"
    echo "  source /opt/ros/<distro>/setup.bash"
    echo ""
    echo "Common distributions: humble, iron, jazzy"
    exit 1
fi

echo -e "${GREEN}✓ ROS2 detected: $ROS_DISTRO${NC}"
echo ""

# Install Python dependencies
echo "Installing Python dependencies..."
pip3 install opencv-python opencv-contrib-python --user

# Check if cv_bridge is available
echo ""
echo "Checking for cv_bridge..."
python3 -c "from cv_bridge import CvBridge" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ cv_bridge is available${NC}"
else
    echo -e "${YELLOW}Warning: cv_bridge not found${NC}"
    echo "Installing cv_bridge..."
    sudo apt-get update
    sudo apt-get install -y ros-${ROS_DISTRO}-cv-bridge python3-opencv
fi

# Make the bridge script executable
chmod +x ros2_image_bridge.py

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "To start the complete system, run these commands in separate terminals:"
echo ""
echo "Terminal 1 - Start Gazebo simulation:"
echo "  gz sim <your_world>.sdf"
echo ""
echo "Terminal 2 - Bridge Gazebo to ROS2:"
echo '  GZ_IMAGE_TOPIC="/world/forest/model/x500_depth_0/link/camera_link/sensor/IMX214/image"'
echo '  ros2 run ros_gz_bridge parameter_bridge $GZ_IMAGE_TOPIC@sensor_msgs/msg/Image@gz.msgs.Image'
echo ""
echo "Terminal 3 - Start HTTP bridge server:"
echo "  ./ros2_image_bridge.py"
echo ""
echo "Then open your Flutter app and connect to:"
echo "  Host: localhost"
echo "  Port: 8080"
echo "  Topic: /camera/image_raw"
echo ""
