#!/usr/bin/env python3
"""
Heterogeneous Traffic Orchestrator using iperf3

Generates three sequential traffic profiles:
1. High-Rate TCP: 3 Mbps, 1280-byte packets
2. Medium-Rate TCP: 750 kbps, 1280-byte packets
3. Low-Rate TCP: 150 kbps, 1280-byte packets

Each test runs for a configurable duration (default 90 seconds).
Metrics from iperf3 JSON output are extracted and can be exported to Prometheus.
"""

import subprocess
import json
import sys
import time
import argparse
import os
from datetime import datetime
from typing import Dict, List, Optional

class TrafficProfile:
    """Represents a traffic profile with iperf3 parameters."""
    
    def __init__(self, name: str, bitrate_kbps: int, duration_sec: int, 
                 packet_size: int = 1280, protocol: str = 'tcp'):
        self.name = name
        self.bitrate_kbps = bitrate_kbps
        self.duration_sec = duration_sec
        self.packet_size = packet_size
        self.protocol = protocol
    
    def __repr__(self):
        return f"{self.name} ({self.bitrate_kbps} kbps, {self.duration_sec}s)"


def run_iperf3_test(target_host: str, target_port: int, profile: TrafficProfile,
                    ue_namespace: str = 'ue0', client_ip: Optional[str] = None) -> Optional[Dict]:
    """
    Run an iperf3 test with the specified profile inside a UE namespace.
    
    Args:
        target_host: IP address of iperf3 server
        target_port: Port of iperf3 server
        profile: TrafficProfile object with test parameters
        ue_namespace: UE namespace to run test in (e.g., 'ue0', 'ue1')
        client_ip: Optional local IP to bind to (for specific UE namespace)
    
    Returns:
        Dictionary with test results or None on failure
    """
    
    print(f"\n[{datetime.now().isoformat()}] Starting {profile} in namespace {ue_namespace}")
    
    # Build iperf3 command (will be wrapped with ip netns exec)
    iperf_cmd = [
        'iperf3',
        '-c', target_host,
        '-p', str(target_port),
        '-t', str(profile.duration_sec),  # duration
        '-P', '1',  # Single stream
        '-l', str(profile.packet_size),  # Length of buffers to read/write
        '-J',  # JSON output
    ]
    
    # Wrap iperf3 command with namespace execution (follows README pattern)
    # This ensures traffic routes through tun_srsue → srsUE → gNB → UPF
    cmd = ['ip', 'netns', 'exec', ue_namespace] + iperf_cmd
    
    if client_ip:
        cmd.extend(['-B', client_ip])
    
    try:
        print(f"  Command: {' '.join(cmd)}")
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=profile.duration_sec + 30)
        
        if result.returncode != 0:
            print(f"  Error: iperf3 returned {result.returncode}")
            print(f"  Stderr: {result.stderr}")
            return None
        
        # Parse JSON output
        try:
            output_json = json.loads(result.stdout)
            
            # Extract relevant metrics from iperf3 output
            end_stats = output_json.get('end', {})
            sum_stats = end_stats.get('sum_received', end_stats.get('sum_sent', {}))
            
            metrics = {
                'traffic_type': profile.name,
                'bitrate_target_kbps': profile.bitrate_kbps,
                'bitrate_achieved_bps': sum_stats.get('bits_per_second', 0),
                'bitrate_achieved_kbps': sum_stats.get('bits_per_second', 0) / 1000,
                'bytes_sent': sum_stats.get('bytes', 0),
                'duration_sec': profile.duration_sec,
                'jitter_ms': end_stats.get('sum_received', {}).get('jitter_ms', 0),
                'packet_loss': end_stats.get('sum_received', {}).get('lost_packets', 0),
                'packets_sent': end_stats.get('sum_sent', {}).get('packets', 0),
                'timestamp': datetime.now().isoformat()
            }
            
            # Calculate loss percentage
            total_packets = metrics['packets_sent'] + metrics['packet_loss']
            if total_packets > 0:
                metrics['loss_percent'] = (metrics['packet_loss'] / total_packets) * 100
            else:
                metrics['loss_percent'] = 0
            
            # Print summary
            print(f"  Results:")
            print(f"    Bitrate: {metrics['bitrate_achieved_kbps']:.2f} kbps "
                  f"(target: {profile.bitrate_kbps} kbps)")
            print(f"    Bytes sent: {metrics['bytes_sent']:,}")
            print(f"    Jitter: {metrics['jitter_ms']:.2f} ms")
            print(f"    Packet loss: {metrics['loss_percent']:.2f}%")
            
            return metrics
            
        except json.JSONDecodeError as e:
            print(f"  Error parsing JSON output: {e}")
            print(f"  Output: {result.stdout}")
            return None
    
    except subprocess.TimeoutExpired:
        print(f"  Error: iperf3 command timed out")
        return None
    except FileNotFoundError:
        print(f"  Error: iperf3 not found. Install with: apt-get install iperf3")
        return None
    except Exception as e:
        print(f"  Error: {e}")
        return None


def run_traffic_sequence(target_host: str, target_port: int = 5201,
                        duration_per_test: int = 90,
                        ue_namespace: str = 'ue0',
                        client_ip: Optional[str] = None) -> List[Dict]:
    """
    Run the complete traffic sequence (high, medium, low rate) from within a UE namespace.
    
    Args:
        target_host: IP address of iperf3 server
        target_port: Port of iperf3 server (default 5201 for iperf3)
        duration_per_test: How long each test runs (default 90 seconds)
        ue_namespace: UE namespace to run tests in (default 'ue0')
        client_ip: Optional IP to bind to
    
    Returns:
        List of result dictionaries, one per traffic profile
    """
    
    # Define traffic profiles
    profiles = [
        TrafficProfile("high_rate", 3000, duration_per_test),  # 3 Mbps
        TrafficProfile("medium_rate", 750, duration_per_test),  # 750 kbps
        TrafficProfile("low_rate", 150, duration_per_test),    # 150 kbps
    ]
    
    results = []
    
    print(f"[{datetime.now().isoformat()}] Starting heterogeneous traffic test sequence")
    print(f"  Target: {target_host}:{target_port}")
    print(f"  UE Namespace: {ue_namespace} (traffic routed through gNB-UPF)")
    print(f"  Duration per test: {duration_per_test} seconds")
    print(f"  Profiles: {len(profiles)}")
    for i, profile in enumerate(profiles, 1):
        print(f"    {i}. {profile}")
    
    for profile in profiles:
        result = run_iperf3_test(target_host, target_port, profile, ue_namespace, client_ip)
        if result:
            results.append(result)
        
        # Wait a bit between tests
        if profile != profiles[-1]:  # Not the last one
            print(f"  Cooling down for 10 seconds before next test...")
            time.sleep(10)
    
    print(f"\n[{datetime.now().isoformat()}] Traffic sequence complete")
    print(f"  Tests completed: {len(results)}/{len(profiles)}")
    
    return results


def write_prometheus_metrics(results: List[Dict], output_file: str, ue_id: str = 'ue1'):
    """
    Write all results to Prometheus text format file.
    
    Args:
        results: List of result dictionaries from traffic tests
        output_file: Path to output file
        ue_id: UE identifier for labels
    """
    
    try:
        os.makedirs(os.path.dirname(output_file) if os.path.dirname(output_file) else '.', exist_ok=True)
        
        with open(output_file, 'w') as f:
            f.write('# Heterogeneous traffic test results\n')
            f.write('# TYPE ue_traffic_throughput_bps gauge\n')
            f.write('# TYPE ue_traffic_jitter_ms gauge\n')
            f.write('# TYPE ue_traffic_loss_percent gauge\n\n')
            
            for result in results:
                traffic_type = result['traffic_type']
                
                f.write(f'ue_traffic_throughput_bps{{ue_id="{ue_id}", traffic_type="{traffic_type}"}} '
                       f'{result["bitrate_achieved_bps"]}\n')
                
                f.write(f'ue_traffic_jitter_ms{{ue_id="{ue_id}", traffic_type="{traffic_type}"}} '
                       f'{result["jitter_ms"]}\n')
                
                f.write(f'ue_traffic_loss_percent{{ue_id="{ue_id}", traffic_type="{traffic_type}"}} '
                       f'{result["loss_percent"]}\n')
        
        print(f"Prometheus metrics written to: {output_file}")
    except Exception as e:
        print(f"Error writing metrics file: {e}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Run heterogeneous traffic tests using iperf3 from within UE namespace'
    )
    parser.add_argument('--host', default='10.10.3.233',
                        help='Target iperf3 server IP (default: %(default)s)')
    parser.add_argument('--port', type=int, default=5201,
                        help='Target iperf3 server port (default: %(default)s)')
    parser.add_argument('--duration', type=int, default=90,
                        help='Duration per test in seconds (default: %(default)s)')
    parser.add_argument('--namespace', default='ue0',
                        help='UE namespace to run tests in (default: %(default)s)')
    parser.add_argument('--client-ip', default=None,
                        help='Local IP to bind client to (optional)')
    parser.add_argument('--metrics-file', default=None,
                        help='Output file for Prometheus metrics (optional)')
    parser.add_argument('--ue-id', default='ue1',
                        help='UE identifier for metric labels (default: %(default)s)')
    
    args = parser.parse_args()
    
    results = run_traffic_sequence(
        target_host=args.host,
        target_port=args.port,
        duration_per_test=args.duration,
        ue_namespace=args.namespace,
        client_ip=args.client_ip
    )
    
    if args.metrics_file and results:
        write_prometheus_metrics(results, args.metrics_file, args.ue_id)
    
    if results:
        print(f"\n\nFull Results:")
        print(json.dumps(results, indent=2))
        sys.exit(0)
    else:
        print("No results collected")
        sys.exit(1)
