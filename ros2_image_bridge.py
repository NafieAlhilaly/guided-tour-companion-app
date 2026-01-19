#!/usr/bin/env python3
"""
ROS2 to HTTP Image Bridge Server
Subscribes to ROS2 image topics and serves them via HTTP for Flutter app
"""

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Image
from cv_bridge import CvBridge
import cv2
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import io

class ImageBridgeNode(Node):
    def __init__(self):
        super().__init__('image_bridge_node')
        self.bridge = CvBridge()
        self.latest_image = None
        self.image_lock = threading.Lock()
        self.subscriptions = {}
        
        # Default subscription to the Gazebo camera topic
        self.create_image_subscription(
            '/camera/image_raw'
        )
        
        self.get_logger().info('Image Bridge Node initialized')

    def create_image_subscription(self, topic):
        """Create a subscription to an image topic"""
        if topic not in self.subscriptions:
            self.subscriptions[topic] = self.create_subscription(
                Image,
                topic,
                lambda msg: self.image_callback(msg, topic),
                10
            )
            self.get_logger().info(f'Subscribed to {topic}')

    def image_callback(self, msg, topic):
        """Callback for image messages"""
        try:
            # Convert ROS image to OpenCV format
            cv_image = self.bridge.imgmsg_to_cv2(msg, desired_encoding='bgr8')
            
            # Store the latest image
            with self.image_lock:
                self.latest_image = cv_image
                
        except Exception as e:
            self.get_logger().error(f'Error processing image: {str(e)}')

    def get_latest_image_jpeg(self):
        """Get the latest image as JPEG bytes"""
        with self.image_lock:
            if self.latest_image is not None:
                # Encode image as JPEG
                _, buffer = cv2.imencode('.jpg', self.latest_image, [cv2.IMWRITE_JPEG_QUALITY, 85])
                return buffer.tobytes()
        return None


class ImageHTTPHandler(BaseHTTPRequestHandler):
    """HTTP handler for serving images"""
    
    ros_node = None  # Will be set to the ROS node instance
    
    def do_GET(self):
        """Handle GET requests"""
        parsed_path = urlparse(self.path)
        
        # Enable CORS for Flutter web
        self.send_cors_headers()
        
        if parsed_path.path == '/ros_image':
            # Get topic from query parameters
            query_params = parse_qs(parsed_path.query)
            topic = query_params.get('topic', ['/camera/image_raw'])[0]
            
            # Create subscription if it doesn't exist
            if topic not in self.ros_node.subscriptions:
                self.ros_node.create_image_subscription(topic)
            
            # Get latest image
            jpeg_data = self.ros_node.get_latest_image_jpeg()
            
            if jpeg_data:
                self.send_response(200)
                self.send_header('Content-Type', 'image/jpeg')
                self.send_header('Content-Length', str(len(jpeg_data)))
                self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
                self.end_headers()
                self.wfile.write(jpeg_data)
            else:
                self.send_error(404, 'No image available yet')
                
        elif parsed_path.path == '/status':
            # Status endpoint
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            status = f"Bridge active. Subscribed to {len(self.ros_node.subscriptions)} topics"
            self.wfile.write(status.encode())
        else:
            self.send_error(404, 'Endpoint not found')
    
    def do_OPTIONS(self):
        """Handle OPTIONS requests for CORS preflight"""
        self.send_cors_headers()
        self.send_response(200)
        self.end_headers()
    
    def send_cors_headers(self):
        """Send CORS headers"""
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
    
    def log_message(self, format, *args):
        """Suppress default HTTP logging"""
        pass


def run_http_server(ros_node, port=8080):
    """Run the HTTP server"""
    ImageHTTPHandler.ros_node = ros_node
    server = HTTPServer(('0.0.0.0', port), ImageHTTPHandler)
    print(f'HTTP Server running on http://0.0.0.0:{port}')
    print(f'Image endpoint: http://localhost:{port}/ros_image')
    print(f'Status endpoint: http://localhost:{port}/status')
    server.serve_forever()


def main():
    print('Starting ROS2 to HTTP Image Bridge...')
    
    # Initialize ROS2
    rclpy.init()
    
    # Create the image bridge node
    image_node = ImageBridgeNode()
    
    # Start HTTP server in a separate thread
    http_thread = threading.Thread(
        target=run_http_server,
        args=(image_node, 8080),
        daemon=True
    )
    http_thread.start()
    
    # Spin the ROS node
    try:
        rclpy.spin(image_node)
    except KeyboardInterrupt:
        print('\nShutting down...')
    finally:
        image_node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
