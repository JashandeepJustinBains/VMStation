#!/usr/bin/env python3
"""
CCNA Lab - Topology Visualization Script
Generates an ASCII topology diagram from GNS3 project
"""

import json
import sys
import argparse
import requests
from typing import Dict, List

def get_gns3_topology(api_url: str, project_name: str) -> Dict:
    """Fetch topology from GNS3 API"""
    # Get all projects
    response = requests.get(f"{api_url}/projects")
    response.raise_for_status()
    projects = response.json()
    
    # Find our project
    project = next((p for p in projects if p['name'] == project_name), None)
    if not project:
        print(f"Error: Project '{project_name}' not found")
        sys.exit(1)
    
    project_id = project['project_id']
    
    # Get nodes
    nodes_response = requests.get(f"{api_url}/projects/{project_id}/nodes")
    nodes_response.raise_for_status()
    nodes = nodes_response.json()
    
    # Get links
    links_response = requests.get(f"{api_url}/projects/{project_id}/links")
    links_response.raise_for_status()
    links = links_response.json()
    
    return {
        'project': project,
        'nodes': nodes,
        'links': links
    }

def generate_ascii_topology(topology: Dict) -> str:
    """Generate ASCII art topology diagram"""
    nodes = topology['nodes']
    links = topology['links']
    
    output = []
    output.append("╔═══════════════════════════════════════════════════════════╗")
    output.append("║          CCNA Lab Network Topology                       ║")
    output.append("╚═══════════════════════════════════════════════════════════╝")
    output.append("")
    
    # List all nodes
    output.append("Nodes:")
    output.append("------")
    for node in nodes:
        name = node.get('name', 'Unknown')
        node_type = node.get('node_type', 'unknown')
        status = node.get('status', 'unknown')
        status_icon = "●" if status == "started" else "○"
        output.append(f"  {status_icon} {name} ({node_type}) - {status}")
    
    output.append("")
    
    # List all links
    output.append("Links:")
    output.append("------")
    for link in links:
        nodes_info = link.get('nodes', [])
        if len(nodes_info) >= 2:
            node1_id = nodes_info[0].get('node_id')
            node2_id = nodes_info[1].get('node_id')
            
            node1 = next((n for n in nodes if n['node_id'] == node1_id), None)
            node2 = next((n for n in nodes if n['node_id'] == node2_id), None)
            
            if node1 and node2:
                port1 = nodes_info[0].get('adapter_number', 0)
                port2 = nodes_info[1].get('adapter_number', 0)
                
                output.append(f"  {node1['name']}:Gi0/{port1} ◄──► {node2['name']}:Gi0/{port2}")
    
    output.append("")
    output.append("Legend:")
    output.append("  ● = Running")
    output.append("  ○ = Stopped")
    output.append("")
    
    return "\n".join(output)

def main():
    parser = argparse.ArgumentParser(description='Generate CCNA lab topology diagram')
    parser.add_argument('--api-url', default='http://10.100.0.10:3080/v3',
                       help='GNS3 API URL')
    parser.add_argument('--project', default='ccna-lab',
                       help='GNS3 project name')
    parser.add_argument('--format', choices=['ascii', 'json'], default='ascii',
                       help='Output format')
    
    args = parser.parse_args()
    
    try:
        topology = get_gns3_topology(args.api_url, args.project)
        
        if args.format == 'json':
            print(json.dumps(topology, indent=2))
        else:
            print(generate_ascii_topology(topology))
            
    except requests.exceptions.RequestException as e:
        print(f"Error connecting to GNS3 API: {e}", file=sys.stderr)
        print("\nMake sure GNS3 server is running and accessible.", file=sys.stderr)
        print(f"API URL: {args.api_url}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
