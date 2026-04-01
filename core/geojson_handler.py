"""
GeoJSON Handler for Indoor Navigation
Handles loading GeoJSON data and building navigation graphs
"""

import json
import numpy as np
import networkx as nx
from config import GraphConfig

# Global variables for navigation data
geojson_data = None
navigation_graph = nx.Graph()
poi_mapping = {}
office_pois = {}

def load_geojson(geojson_str):
    """Load GeoJSON data from string"""
    global geojson_data
    geojson_data = json.loads(geojson_str)
    build_navigation_graph()

def build_navigation_graph():
    """Build a navigation graph from GeoJSON data"""
    global navigation_graph, poi_mapping, office_pois

    # Clear existing graph
    navigation_graph.clear()

    # Extract room offices as landmarks
    office_pois = [
        feature for feature in geojson_data['features']
        if feature['geometry']['type'] == 'Point' and feature.get('properties') 
            and feature['properties'].get('category') != 'node'
    ]

    #print(f"Office_Pois: {office_pois}")

    # Extract POIs (nodes)
    for feature in geojson_data['features']:
        if feature['geometry']['type'] == 'Point':
            coords = feature['geometry']['coordinates']
            node_id = feature['properties']['id']
            node_name = feature.get('properties', {}).get('name')

            if not node_name:  
                node_name = f"node_{node_id}"
                #print(f"node_name: {node_name}")

            # Add node to graph
            navigation_graph.add_node(node_id,
                                      coordinates=(coords[0], coords[1]),
                                      name=node_name)

            # Add to POI mapping
            poi_mapping[node_name] = (coords[0], coords[1])
    #print(f"POI_Mapping: {poi_mapping}")

    # Extract paths (edges)
    for feature in geojson_data['features']:
        if feature['properties']['type'] == 'path':
            if feature['geometry']['type'] == 'MultiLineString':
                path_coords = feature['geometry']['coordinates'][0]  # Get first linestring

                # Connect each segment in the path
                for i in range(len(path_coords) - 1):
                    # Find closest nodes to the start and end of this segment
                    start_point = (path_coords[i][0], path_coords[i][1])
                    end_point = (path_coords[i+1][0], path_coords[i+1][1])

                    start_node = find_closest_node(start_point)
                    end_node = find_closest_node(end_point)

                    if start_node and end_node and start_node != end_node:
                        # Calculate Euclidean distance between nodes
                        dist = np.sqrt((start_point[0] - end_point[0])**2 +
                                      (start_point[1] - end_point[1])**2)

                        # Add edge to graph with weight equal to distance
                        navigation_graph.add_edge(start_node, end_node, weight=dist)

def find_closest_node(point):
    """Find the closest node in the graph to the given point"""
    min_dist = float('inf')
    closest_node = None

    for node, attrs in navigation_graph.nodes(data=True):
        node_coords = attrs['coordinates']
        dist = np.sqrt((point[0] - node_coords[0])**2 + (point[1] - node_coords[1])**2)

        # Use a small threshold to match exact points
        if dist < GraphConfig.NODE_DISTANCE_THRESHOLD:
            return node

        if dist < min_dist:
            min_dist = dist
            closest_node = node

    # Only return nodes that are reasonably close (to avoid connecting unrelated points)
    if min_dist < GraphConfig.EDGE_DISTANCE_THRESHOLD:
        return closest_node
    return None

def get_point_from_name(name):
    """Get coordinates for a named POI"""
    name_lower = name.lower()
    for poi_name, coords in poi_mapping.items():
        if poi_name.lower() == name_lower:
            return coords
    return None

def get_poi_name_from_coordinates(coordinates):
    """Find the name of a POI based on coordinates"""
    from scipy.spatial import distance
    
    for node, attrs in navigation_graph.nodes(data=True):
        node_coords = attrs['coordinates']
        if distance.euclidean(coordinates, node_coords) < 0.1:  # Small threshold
            return attrs['name']
    return "a waypoint"

def get_geojson_data():
    """Get the loaded GeoJSON data"""
    return geojson_data

def get_navigation_graph():
    """Get the navigation graph"""
    return navigation_graph

def get_poi_mapping():
    """Get the POI mapping"""
    return poi_mapping

def get_office_pois():
    """Get the office POIs"""
    return office_pois