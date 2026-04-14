#!/usr/bin/env python3
"""
Prometheus Exporter for UE Traffic Tests

Orchestrates traffic generation (VoIP + heterogeneous profiles) and 
pushes metrics to Prometheus Pushgateway for monitoring.

Workflow:
1. Start VoIP traffic generator (runs in background)
2. Run heterogeneous traffic tests (sequential: high → medium → low)
3. Collect metrics from both tests
4. Push aggregated metrics to Prometheus Pushgateway
5. Store metrics locally in Prometheus text format
"""

import subprocess
import requests
import json
import sys
import time
import os
import argparse
import threading
from datetime import datetime
from typing import Dict, Optional, List


class PrometheusExporter:
    """Manages traffic tests and exports metrics to Prometheus."""
    
    def __init__(self, ue_id: str = 'ue0', pushgateway_url: str = 'http://prometheus-pushgateway:9091',
                 iperf_server: str = '10.10.3.233', iperf_port: int = 5201,
                 test_duration: int = 90, metrics_dir: str = '/var/lib/node_exporter',
                 test_type: str = 'default'):
        """
        Initialize exporter.
        
        Args:
            ue_id: UE identifier (ue0, ue1, ue2, etc.)
            pushgateway_url: URL of Prometheus Pushgateway
            iperf_server: IP of iperf3 server
            iperf_port: Port of iperf3 server
            test_duration: Duration of each traffic test in seconds
            metrics_dir: Directory for local Prometheus metric files
            test_type: Test type label for metrics (e.g., 'baseline', 'stress', 'validation')
        """
        self.ue_id = ue_id
        self.pushgateway_url = pushgateway_url
        self.iperf_server = iperf_server
        self.iperf_port = iperf_port
        self.test_duration = test_duration
        self.metrics_dir = metrics_dir
        self.test_type = test_type
        self.metrics_data = {}
        
        # Ensure metrics directory exists
        os.makedirs(metrics_dir, exist_ok=True)
    
    def run_voip_generator(self) -> Dict:
        """
        Run VoIP traffic generator from within a UE namespace.
        
        Returns:
            Dictionary with VoIP metrics
        """
        
        script_dir = os.path.dirname(os.path.abspath(__file__))
        voip_script = os.path.join(script_dir, 'voip_generator.py')
        
        if not os.path.exists(voip_script):
            print(f"Warning: VoIP generator script not found at {voip_script}")
            return {}
        
        # Extract UE number from ue_id (e.g., 'ue0' → '0', 'ue1' → '1')
        ue_number = self.ue_id.replace('ue', '') if self.ue_id.startswith('ue') else '0'
        ue_namespace = f"ue{ue_number}"
        
        print(f"[{datetime.now().isoformat()}] Starting VoIP traffic generator in namespace {ue_namespace}")
        
        # Run VoIP generator with duration=test_duration (runs in specified namespace)
        cmd = [
            'python3', voip_script,
            '--host', self.iperf_server,
            '--port', '5001',
            '--duration', str(self.test_duration),
            '--namespace', ue_namespace,  # ← Run VoIP from within UE namespace
        ]
        
        try:
            # Note: This runs synchronously but can be adapted to run in parallel with threading
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=self.test_duration + 30)
            
            if result.returncode != 0:
                print(f"VoIP generator error: {result.stderr}")
                return {}
            
            # Parse JSON from output (look for JSON on last line)
            try:
                lines = result.stdout.strip().split('\n')
                # Find JSON object (usually last one with metrics summary)
                for line in reversed(lines):
                    if line.strip().startswith('{'):
                        metrics = json.loads(line)
                        return metrics
            except (json.JSONDecodeError, ValueError):
                print("Could not parse VoIP metrics from output")
                return {}
                
        except subprocess.TimeoutExpired:
            print("VoIP generator timed out")
            return {}
        except Exception as e:
            print(f"Error running VoIP generator: {e}")
            return {}
    
    def run_heterogeneous_tests(self) -> List[Dict]:
        """
        Run heterogeneous traffic tests (high, medium, low rate) from within a UE namespace.
        
        Returns:
            List of result dictionaries
        """
        
        print(f"[{datetime.now().isoformat()}] Starting heterogeneous traffic tests")
        
        script_dir = os.path.dirname(os.path.abspath(__file__))
        orchestrator_script = os.path.join(script_dir, 'traffic_test_orchestrator.py')
        
        if not os.path.exists(orchestrator_script):
            print(f"Warning: Orchestrator script not found at {orchestrator_script}")
            return []
        
        # Extract UE number from ue_id (e.g., 'ue0' → '0', 'ue1' → '1')
        ue_number = self.ue_id.replace('ue', '') if self.ue_id.startswith('ue') else '0'
        ue_namespace = f"ue{ue_number}"
        
        cmd = [
            'python3', orchestrator_script,
            '--host', self.iperf_server,
            '--port', str(self.iperf_port),
            '--duration', str(self.test_duration),
            '--namespace', ue_namespace,  # ← Run tests within UE namespace
            '--ue-id', self.ue_id
        ]
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, 
                                   timeout=self.test_duration * 3 + 60)  # Triple the duration for 3 tests
            
            if result.returncode != 0:
                print(f"Orchestrator error: {result.stderr}")
                return []
            
            # Parse JSON from output
            try:
                full_output = result.stdout
                
                # Find "Full Results:" marker followed by JSON array
                marker = "Full Results:"
                marker_pos = full_output.find(marker)
                if marker_pos != -1:
                    # Start searching for '[' after the marker
                    search_start = marker_pos + len(marker)
                else:
                    search_start = 0
                
                # Find the start of JSON array (look for '[\n' or '[ ')
                json_start = -1
                for i in range(search_start, len(full_output) - 1):
                    if full_output[i] == '[' and (full_output[i+1] in '\n\r\t '):
                        json_start = i
                        break
                
                if json_start == -1:
                    print("  ✗ No JSON array found in orchestrator output")
                    return []
                
                # Find the matching closing bracket
                json_end = full_output.rfind(']')
                if json_end == -1 or json_end <= json_start:
                    print("  ✗ Incomplete JSON array in orchestrator output")
                    return []
                
                # Extract and parse JSON
                json_str = full_output[json_start:json_end+1]
                results = json.loads(json_str)
                print(f"  ✓ Parsed {len(results)} traffic test results")
                return results
                
            except (json.JSONDecodeError, ValueError) as e:
                print(f"  ✗ Could not parse orchestrator metrics: {e}")
                return []
                
        except subprocess.TimeoutExpired:
            print("Heterogeneous tests timed out")
            return []
        except Exception as e:
            print(f"Error running heterogeneous tests: {e}")
            return []
    
    def push_to_pushgateway(self, metrics: Dict) -> bool:
        """
        Push metrics to Prometheus Pushgateway.
        
        Args:
            metrics: Dictionary with 'voip' and 'heterogeneous_tests' keys
        
        Returns:
            True if successful, False otherwise
        """
        
        print(f"[{datetime.now().isoformat()}] Pushing metrics to Prometheus Pushgateway")
        
        # Format: http://pushgateway:9091/metrics/job/{job}/instance/{instance}
        job_name = f"ue_traffic_{self.ue_id}_{self.test_type}"
        instance_name = f"{self.ue_id}_{datetime.now().strftime('%s')}"
        
        url = f"{self.pushgateway_url}/metrics/job/{job_name}/instance/{instance_name}"
        
        # Build Prometheus text format
        prom_text = ""
        
        # VoIP metrics
        voip_metrics = metrics.get('voip', {})
        if voip_metrics:
            for key, value in voip_metrics.items():
                if key not in ['timestamp', 'traffic_type'] and isinstance(value, (int, float)):
                    prom_text += f'ue_voip_{key}{{test_type="{self.test_type}", ue_id="{self.ue_id}"}} {value}\n'
        
        # Heterogeneous test metrics
        test_results = metrics.get('heterogeneous_tests', [])
        if test_results:
            for result in test_results:
                traffic_type = result.get('traffic_type', 'unknown')
                for key, value in result.items():
                    if key not in ['timestamp', 'traffic_type'] and isinstance(value, (int, float)):
                        prom_text += f'ue_traffic_{key}{{test_type="{self.test_type}", traffic_type="{traffic_type}", ue_id="{self.ue_id}"}} {value}\n'
        
        try:
            response = requests.post(url, data=prom_text, timeout=10)
            if response.status_code in [200, 202]:
                print(f"  ✓ Metrics pushed successfully")
                return True
            else:
                print(f"  ✗ Pushgateway returned {response.status_code}: {response.text}")
                return False
        except requests.exceptions.RequestException as e:
            print(f"  ✗ Error pushing metrics: {e}")
            return False
    
    def save_local_metrics(self, voip_metrics: Dict, test_results: List[Dict]) -> bool:
        """
        Save metrics locally in Prometheus text format.
        
        Args:
            voip_metrics: VoIP test metrics
            test_results: List of heterogeneous test results
        
        Returns:
            True if successful
        """
        
        try:
            # Build local metrics file
            metrics_file = os.path.join(self.metrics_dir, f'ue_traffic_{self.ue_id}.prom')
            
            with open(metrics_file, 'w') as f:
                # Write VoIP metrics
                if voip_metrics:
                    f.write('# VoIP Traffic Metrics\n')
                    for key, value in voip_metrics.items():
                        if key not in ['timestamp', 'traffic_type']:
                            if isinstance(value, (int, float)):
                                f.write(f'ue_voip_{key}{{test_type="{self.test_type}", ue_id="{self.ue_id}"}} {value}\n')
                
                # Write heterogeneous test metrics
                if test_results:
                    f.write('\n# Heterogeneous Traffic Metrics\n')
                    for result in test_results:
                        traffic_type = result.get('traffic_type', 'unknown')
                        
                        f.write(f'ue_traffic_throughput_bps{{test_type="{self.test_type}", ue_id="{self.ue_id}", traffic_type="{traffic_type}"}} '
                               f'{result.get("bitrate_achieved_bps", 0)}\n')
                        
                        f.write(f'ue_traffic_jitter_ms{{test_type="{self.test_type}", ue_id="{self.ue_id}", traffic_type="{traffic_type}"}} '
                               f'{result.get("jitter_ms", 0)}\n')
                        
                        f.write(f'ue_traffic_loss_percent{{test_type="{self.test_type}", ue_id="{self.ue_id}", traffic_type="{traffic_type}"}} '
                               f'{result.get("loss_percent", 0)}\n')
                        
                        f.write(f'ue_traffic_bytes_sent{{test_type="{self.test_type}", ue_id="{self.ue_id}", traffic_type="{traffic_type}"}} '
                               f'{result.get("bytes_sent", 0)}\n')
            
            print(f"Metrics saved to: {metrics_file}")
            return True
        except Exception as e:
            print(f"Error saving local metrics: {e}")
            return False
    
    def run_single_cycle(self, cycle_num: int = 0) -> bool:
        """
        Execute a single test cycle.
        
        Args:
            cycle_num: Current cycle number (for continuous mode)
        
        Returns:
            True if successful
        """
        cycle_info = f" (Cycle {cycle_num})" if cycle_num > 0 else ""
        
        print(f"\n{'='*70}")
        print(f"UE Traffic Exporter - {self.ue_id}{cycle_info}")
        print(f"{'='*70}")
        print(f"Test type: {self.test_type}")
        print(f"Start time: {datetime.now().isoformat()}")
        print(f"iperf server: {self.iperf_server}:{self.iperf_port}")
        print(f"Test duration: {self.test_duration} seconds per profile")
        print(f"Pushgateway: {self.pushgateway_url}")
        print(f"Metrics directory: {self.metrics_dir}")
        print(f"{'='*70}\n")
        
        # Run VoIP traffic generator
        voip_metrics = self.run_voip_generator()
        
        # Run heterogeneous traffic tests
        test_results = self.run_heterogeneous_tests()
        
        # Save metrics locally
        self.save_local_metrics(voip_metrics, test_results)
        
        # Push to Pushgateway
        if voip_metrics or test_results:
            aggregated_metrics = {
                'voip': voip_metrics if voip_metrics else {},
                'heterogeneous_tests': test_results if test_results else []
            }
            self.push_to_pushgateway(aggregated_metrics)
        
        print(f"\n{'='*70}")
        print(f"Cycle completed at: {datetime.now().isoformat()}")
        print(f"{'='*70}\n")
        
        return bool(voip_metrics or test_results)
    
    def run_continuous(self, interval_sec: int = 5) -> bool:
        """
        Execute tests continuously with periodic metric updates.
        Runs until user interrupts with Ctrl+C.
        
        Args:
            interval_sec: Wait time between test cycles in seconds (default: 5)
        
        Returns:
            True if stopped gracefully
        """
        print(f"\n{'='*70}")
        print(f"UE Traffic Monitoring - {self.ue_id}")
        print(f"{'='*70}")
        print(f"Test type: {self.test_type}")
        print(f"Interval: {interval_sec} seconds between cycles")
        print(f"Started at: {datetime.now().isoformat()}")
        print(f"Press Ctrl+C to stop")
        print(f"{'='*70}\n")
        
        cycle = 0
        successful_cycles = 0
        
        try:
            while True:
                cycle += 1
                
                # Run test cycle
                success = self.run_single_cycle(cycle_num=cycle)
                if success:
                    successful_cycles += 1
                
                # Wait before next cycle
                print(f"[{datetime.now().isoformat()}] Waiting {interval_sec} seconds before next cycle...")
                time.sleep(interval_sec)
                
        except KeyboardInterrupt:
            print(f"\n\n{'='*70}")
            print(f"Monitoring stopped by user (Ctrl+C)")
            print(f"Total cycles completed: {cycle}")
            print(f"Successful cycles: {successful_cycles}/{cycle}")
            print(f"Stopped at: {datetime.now().isoformat()}")
            print(f"{'='*70}\n")
            return True


def main():
    parser = argparse.ArgumentParser(
        description='Prometheus exporter for UE traffic tests - runs continuously until stopped',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Traffic Types (automatically labeled):
  - high_rate   : 3 Mbps TCP (HD video, file downloads, video conferencing)
  - medium_rate : 750 kbps TCP (web browsing, social media, music streaming)
  - low_rate    : 150 kbps TCP (IoT apps, messaging, background sync)
  - voip        : 64 kbps UDP (G.711 VoIP)

Test Type Examples:
  - baseline_validation  : Initial system performance baseline
  - stress_test          : High load / long duration testing
  - daily_monitoring     : Regular system health checks
  - regression_test      : Post-change validation
  - stability_test       : Long-running stability assessment

Usage Examples:
  # Quick 5-second tests, 30-second intervals
  python3 traffic_metrics_exporter.py --ue-id ue1 --test-type daily_monitoring --test-duration 5 --interval 30
  
  # Standard tests every 5 minutes
  python3 traffic_metrics_exporter.py --ue-id ue1 --test-type baseline_validation --test-duration 120 --interval 300
  
  # Stop anytime with Ctrl+C
        """
    )
    parser.add_argument('--ue-id', default='ue0',
                        help='UE identifier (default: %(default)s)')
    parser.add_argument('--test-type', default='default',
                        help='Test type label for metrics (e.g., baseline_validation, stress_test, daily_monitoring)')
    parser.add_argument('--test-duration', type=int, default=30,
                        help='Test duration per traffic profile in seconds (default: %(default)s)')
    parser.add_argument('--interval', type=int, default=5,
                        help='Seconds to wait between test cycles (default: %(default)s)')
    parser.add_argument('--pushgateway-url', default='http://prometheus-pushgateway:9091',
                        help='Pushgateway URL (default: %(default)s)')
    parser.add_argument('--iperf-host', default='10.10.3.233',
                        help='iperf3 server IP (default: %(default)s)')
    parser.add_argument('--iperf-port', type=int, default=5201,
                        help='iperf3 server port (default: %(default)s)')
    parser.add_argument('--metrics-dir', default='/var/lib/node_exporter',
                        help='Local metrics directory (default: %(default)s)')
    
    args = parser.parse_args()
    
    exporter = PrometheusExporter(
        ue_id=args.ue_id,
        pushgateway_url=args.pushgateway_url,
        iperf_server=args.iperf_host,
        iperf_port=args.iperf_port,
        test_duration=args.test_duration,
        metrics_dir=args.metrics_dir,
        test_type=args.test_type
    )
    
    # Always run in continuous mode until Ctrl+C
    success = exporter.run_continuous(interval_sec=args.interval)
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
