"""
NavigationSession for Indoor Navigation
Manages individual navigation sessions from source to destination
"""

import numpy as np
import networkx as nx
from scipy.spatial import distance
from .navigation import RouteTracker
from .geojson_handler import get_navigation_graph, get_point_from_name

class NavigationSession:
    def __init__(self, source_name, destination_name, use_clock_directions=False, use_landmarks_directions=False):
        # Get source and destination coordinates from names
        self.source_name = source_name
        self.destination_name = destination_name

        self.source = get_point_from_name(source_name)
        self.destination = get_point_from_name(destination_name)
        self.use_clock_directions = use_clock_directions
        self.use_landmarks_directions = use_landmarks_directions

        if not self.source or not self.destination:
            raise ValueError("Invalid source or destination name")

        self.path = []  # List of path nodes [(x1, y1), (x2, y2), ...]
        self.current_position = self.source
        self.generate_path()

        # Initialize the RouteTracker with our path
        self.route_tracker = RouteTracker(self.path)
        self.route_tracker.session = self
        
        # Pass the direction preference to the route tracker
        self.route_tracker.use_clock_directions = self.use_clock_directions
        self.route_tracker.use_landmarks_directions = self.use_landmarks_directions

    def find_nearest_graph_node(self, point):
        """Find the nearest node in the navigation graph to the given point"""
        min_dist = float('inf')
        closest_node = None
        
        navigation_graph = get_navigation_graph()

        for node, attrs in navigation_graph.nodes(data=True):
            node_coords = attrs['coordinates']
            dist = np.sqrt((point[0] - node_coords[0])**2 + (point[1] - node_coords[1])**2)

            if dist < min_dist:
                min_dist = dist
                closest_node = node

        return closest_node, min_dist

    def generate_path(self):
        """
        Generate a path from source to destination using the navigation graph.
        """
        navigation_graph = get_navigation_graph()
        
        # Find nearest nodes in the graph to our source and destination
        source_node, _ = self.find_nearest_graph_node(self.source)
        dest_node, _ = self.find_nearest_graph_node(self.destination)

        if source_node is None or dest_node is None:
            # Fallback to direct path if no graph nodes are close
            self.path = [self.source, self.destination]
            return

        try:
            # Use Dijkstra's algorithm to find shortest path
            path_nodes = nx.shortest_path(navigation_graph, source=source_node,
                                        target=dest_node, weight='weight')

            # Convert node IDs to coordinates
            self.path = [navigation_graph.nodes[node]['coordinates'] for node in path_nodes]

            # Add actual source and destination if they're different from the nearest nodes
            if distance.euclidean(self.source, self.path[0]) > 0.001:
                self.path.insert(0, self.source)

            if distance.euclidean(self.destination, self.path[-1]) > 0.001:
                self.path.append(self.destination)

        except nx.NetworkXNoPath:
            # No path found in graph, use direct path
            self.path = [self.source, self.destination]

    def detect_deviation(self, reported_position, reported_bearing=None, reported_magnetic_strength=None, 
                        reported_qr_status=False, reported_qr_id=None):
        """
        Uses the RouteTracker to detect deviations and get recovery instructions
        """
        # Update user position in the RouteTracker
        result = self.route_tracker.update_position(reported_position, reported_bearing, 
                                                   reported_magnetic_strength, reported_qr_status, 
                                                   reported_qr_id)

        # Update current position
        if result is not None:
            return result
        else:
            return None