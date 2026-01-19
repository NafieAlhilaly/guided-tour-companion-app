# Video Stream Setup Guide

This guide explains how to set up the complete video streaming pipeline from Gazebo to your Flutter app.

## Architecture

```
Gazebo Simulation → ros_gz_bridge → ROS2 Topic → HTTP Bridge Server → Flutter App
```

## Prerequisites

1. ROS2 installed (Humble, Iron, or Jazzy)
2. Gazebo Harmonic or Garden
3. ros_gz_bridge package
4. Python 3 with the following packages:
   - rclpy
   - sensor_msgs
   - cv_bridge
   - opencv-python

## Setup Steps

### 1. Install Dependencies

Run the setup script:
```bash
./setup_ros_bridge.sh
```

Or manually install:
```bash
# Install OpenCV for Python
pip3 install opencv-python opencv-contrib-python

# Install cv_bridge
sudo apt-get install ros-${ROS_DISTRO}-cv-bridge python3-opencv
```

### 2. Start the System

You need **3 separate terminals**:

#### Terminal 1: Start Gazebo Simulation
```bash
# Source your ROS2 workspace if needed
source /opt/ros/${ROS_DISTRO}/setup.bash

# Launch your Gazebo world
gz sim forest.sdf  # Replace with your world file
```

#### Terminal 2: Bridge Gazebo to ROS2
```bash
# Source ROS2
source /opt/ros/${ROS_DISTRO}/setup.bash

# Set the Gazebo image topic
export GZ_IMAGE_TOPIC="/world/forest/model/x500_depth_0/link/camera_link/sensor/IMX214/image"

# Run the bridge
ros2 run ros_gz_bridge parameter_bridge \
  $GZ_IMAGE_TOPIC@sensor_msgs/msg/Image@gz.msgs.Image
```

This creates a ROS2 topic at `/camera/image_raw` that receives images from Gazebo.

#### Terminal 3: Start HTTP Bridge Server
```bash
# Source ROS2
source /opt/ros/${ROS_DISTRO}/setup.bash

# Run the bridge server
cd /home/nafea/projects/companion-app/flutter_application_1
./ros2_image_bridge.py
```

The HTTP server will start on `http://localhost:8080`

### 3. Connect Flutter App

1. Run your Flutter app:
   ```bash
   flutter run
   ```

2. Log in via MQTT

3. Click the "Video Stream" button

4. Use these settings:
   - **Host**: `localhost` (or your computer's IP if running on a device)
   - **Port**: `8080`
   - **Topic**: `/camera/image_raw`

5. Click "Start Stream"

## Troubleshooting

### No image appears in Flutter app

1. **Check if the bridge server is running:**
   ```bash
   curl http://localhost:8080/status
   ```
   Should return: "Bridge active. Subscribed to X topics"

2. **Check if ROS2 topic has data:**
   ```bash
   ros2 topic echo /camera/image_raw --once
   ```

3. **Verify Gazebo topic:**
   ```bash
   gz topic -l | grep image
   ```

### "Connection refused" error

- Make sure the HTTP bridge server (Terminal 3) is running
- Check firewall settings if connecting from another device
- Use your computer's IP address instead of `localhost` when connecting from a physical device

### "No image available yet" message

- Verify that Gazebo is publishing images: `gz topic -e -t <your_topic>`
- Check that ros_gz_bridge is running and bridging correctly
- Confirm the ROS2 topic is receiving data: `ros2 topic hz /camera/image_raw`

### Poor performance or lag

- Reduce image quality in `ros2_image_bridge.py` (change JPEG quality parameter)
- Increase the polling interval in Flutter (change `Duration(milliseconds: 100)` to a higher value)
- Use a faster network connection

## Advanced Configuration

### Change HTTP Port

Edit `ros2_image_bridge.py` and modify the port in the `main()` function:
```python
http_thread = threading.Thread(
    target=run_http_server,
    args=(image_node, 9090),  # Change port here
    daemon=True
)
```

### Subscribe to Multiple Topics

The bridge automatically handles multiple topics. Just change the topic parameter in the Flutter app to subscribe to different cameras.

### Adjust Image Quality

In `ros2_image_bridge.py`, find this line:
```python
_, buffer = cv2.imencode('.jpg', self.latest_image, [cv2.IMWRITE_JPEG_QUALITY, 85])
```

Change `85` to:
- Higher (90-100) for better quality but larger size
- Lower (50-70) for lower quality but faster streaming

## Testing Without Gazebo

To test the system with a test pattern:

```bash
# Install image_tools
sudo apt-get install ros-${ROS_DISTRO}-image-tools

# Publish a test image
ros2 run image_tools cam2image --ros-args -p frequency:=10.0
```

Then connect your Flutter app to the `/image` topic.

## Notes

- The HTTP bridge serves images on-demand (not a continuous stream)
- Each Flutter app request fetches the latest image
- Multiple Flutter apps can connect simultaneously
- CORS is enabled for web deployments
