#!/usr/bin/env python3
"""
CCNA Lab - Link Status Monitor
Continuously monitors link status in GNS3 topology
"""

import json
import sys
import time
import argparse
import requests
from datetime import datetime

def monitor_links(api_url: str, project_name: str, interval: int = 5):
    """Monitor link status in real-time"""
    print("╔═══════════════════════════════════════════════════════════╗")
    print("║       CCNA Lab - Link Status Monitor                     ║")
    print("╚═══════════════════════════════════════════════════════════╝")
    print()
    print(f"Monitoring project: {project_name}")
    print(f"Refresh interval: {interval} seconds")
    print(f"API URL: {api_url}")
    print()
    print("Press Ctrl+C to stop")
    print()
    
    try:
        while True:
            # Get project
            response = requests.get(f"{api_url}/projects", timeout=5)
            response.raise_for_status()
            projects = response.json()
            
            project = next((p for p in projects if p['name'] == project_name), None)
            if not project:
                print(f"Error: Project '{project_name}' not found")
                time.sleep(interval)
                continue
            
            project_id = project['project_id']
            
            # Get nodes
            nodes_response = requests.get(f"{api_url}/projects/{project_id}/nodes", timeout=5)
            nodes_response.raise_for_status()
            nodes = nodes_response.json()
            
            # Get links
            links_response = requests.get(f"{api_url}/projects/{project_id}/links", timeout=5)
            links_response.raise_for_status()
            links = links_response.json()
            
            # Clear screen (works on Unix-like systems)
            print("\033[2J\033[H", end='')
            
            # Print header
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            print(f"Last update: {timestamp}")
            print()
            
            # Print node status
            print("Node Status:")
            print("-" * 60)
            for node in nodes:
                name = node.get('name', 'Unknown')
                status = node.get('status', 'unknown')
                console = node.get('console', 'N/A')
                
                status_icon = "🟢" if status == "started" else "⚫"
                print(f"  {status_icon} {name:20s} {status:10s} Console: {console}")
            
            print()
            
            # Print link status
            print("Link Status:")
            print("-" * 60)
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
                        
                        # Check if both nodes are running
                        link_up = (node1.get('status') == 'started' and 
                                 node2.get('status') == 'started')
                        
                        status_icon = "🟢" if link_up else "🔴"
                        print(f"  {status_icon} {node1['name']:15s} Gi0/{port1} ◄──► Gi0/{port2:1d} {node2['name']}")
            
            print()
            print(f"Next refresh in {interval} seconds... (Ctrl+C to stop)")
            
            time.sleep(interval)
            
    except KeyboardInterrupt:
        print("\n\nMonitoring stopped.")
        sys.exit(0)
    except requests.exceptions.RequestException as e:
        print(f"\nError connecting to GNS3 API: {e}", file=sys.stderr)
        print("Retrying in 10 seconds...", file=sys.stderr)
        time.sleep(10)
    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        time.sleep(5)

def main():
    parser = argparse.ArgumentParser(description='Monitor CCNA lab link status')
    parser.add_argument('--api-url', default='http://10.100.0.10:3080/v3',
                       help='GNS3 API URL')
    parser.add_argument('--project', default='ccna-lab',
                       help='GNS3 project name')
    parser.add_argument('--interval', type=int, default=5,
                       help='Refresh interval in seconds')
    
    args = parser.parse_args()
    
    monitor_links(args.api_url, args.project, args.interval)

if __name__ == '__main__':
    main()
