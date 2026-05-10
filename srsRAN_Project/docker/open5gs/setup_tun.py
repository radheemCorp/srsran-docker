#!/usr/bin/env python3

import click
import ipaddress
import iptc
import subprocess
from pyroute2 import IPRoute
from pyroute2.netlink import NetlinkError


def handle_ip_string(ctx, param, value):
    try:
        ret = ipaddress.ip_network(value)
        return ret
    except ValueError:
        raise click.BadParameter(f'{value} is not a valid IP range.')


def enable_ip_forward():
    """Enable IPv4 forwarding inside the container."""
    try:
        subprocess.run(
            ["sysctl", "-w", "net.ipv4.ip_forward=1"],
            check=True, capture_output=True
        )
    except subprocess.CalledProcessError:
        pass  # Container may not have permission


def get_internet_iface():
    """Detect the internet-facing interface using the routing table."""
    try:
        output = subprocess.check_output(["ip", "route", "get", "8.8.8.8"], stderr=subprocess.STDOUT).decode().strip()
        parts = output.split()
        if "dev" in parts:
            return parts[parts.index("dev") + 1]
    except (subprocess.CalledProcessError, IndexError):
        pass

    # Fallback: find default route interface
    try:
        output = subprocess.check_output(["ip", "route", "show", "default"], stderr=subprocess.STDOUT).decode().strip()
        if output:
            parts = output.split()
            if "dev" in parts:
                return parts[parts.index("dev") + 1]
    except subprocess.CalledProcessError:
        pass

    return "eth0"


def iptables_add_masquerade(if_name, ip_range):
    """Add NAT MASQUERADE rule: masquerade UE traffic leaving the internet interface."""
    chain = iptc.Chain(iptc.Table(iptc.Table.NAT), "POSTROUTING")
    rule = iptc.Rule()
    rule.src = str(ip_range)
    rule.out_interface = if_name
    target = iptc.Target(rule, "MASQUERADE")
    rule.target = target
    chain.insert_rule(rule)


def iptables_allow_forward(tun_iface, internet_iface):
    """Add FORWARD rules to allow traffic between ogstun and internet interface."""
    chain = iptc.Chain(iptc.Table(iptc.Table.FILTER), "FORWARD")
    
    # Rule 1: ALLOW forwarding from ogstun to internet (outbound UE traffic)
    rule1 = iptc.Rule()
    rule1.in_interface = tun_iface
    rule1.out_interface = internet_iface
    target1 = iptc.Target(rule1, "ACCEPT")
    rule1.target = target1
    chain.insert_rule(rule1)

    # Rule 2: ALLOW established/related connections from internet back to ogstun
    rule2 = iptc.Rule()
    rule2.in_interface = internet_iface
    rule2.out_interface = tun_iface
    target2 = iptc.Target(rule2, "ACCEPT")
    rule2.target = target2
    try:
        from iptc import Match
        rule2.add_match("state").create_options.state = ["RELATED", "ESTABLISHED"]
    except Exception:
        pass

    chain.insert_rule(rule2)


def iptables_allow_all(if_name):
    chain = iptc.Chain(iptc.Table(iptc.Table.FILTER), "INPUT")
    rule = iptc.Rule()
    rule.in_interface = if_name
    target = iptc.Target(rule, "ACCEPT")
    rule.target = target
    chain.insert_rule(rule)


@click.command()
@click.option("--if_name", default="ogstun", help="TUN interface name.")
@click.option("--ip_range", default='10.45.0.0/24', callback=handle_ip_string,
              help="IP range of the TUN interface.")
@click.option("--internet_iface", default=None, help="Internet-facing interface (auto-detected if not specified).")
def main(if_name, ip_range, internet_iface):
    
    if internet_iface is None:
        internet_iface = get_internet_iface()
    
    print(f"Internet interface: {internet_iface}")
    print(f"UE subnet: {ip_range}")

    # Enable IP forwarding
    enable_ip_forward()
    print("IP forwarding enabled")

    # Create the ogstun interface
    ipr = IPRoute()
    try:
        dev = ipr.link_lookup(ifname=if_name)[0]
        ipr.link('set', index=dev, state='down')
    except (IndexError, KeyError):
        dev = None
        pass

    if dev is None:
        ipr.link('add', ifname=if_name, kind='tuntap', mode='tun')
        dev = ipr.link_lookup(ifname=if_name)[0]

    ipr.link('set', index=dev, state='down')
    first_ip_addr = str(next(ip_range.hosts(), None))
    if first_ip_addr:
        ipr.addr('add', index=dev, address=first_ip_addr, mask=ip_range.prefixlen)
    ipr.link('set', index=dev, state='up')

    try:
        ipr.route('add', dst=str(ip_range), gateway=first_ip_addr or '0.0.0.0')
    except NetlinkError:
        pass
    finally:
        ipr.close()

    # Setup iptables: MASQUERADE traffic from UE subnet leaving the internet interface
    iptables_add_masquerade(internet_iface, ip_range)
    print(f"MASQUERADE rule added: source={ip_range}, out={internet_iface}")

    # Setup iptables: FORWARD rules between ogstun and internet interface
    iptables_allow_forward(if_name, internet_iface)
    print(f"FORWARD rules added: {if_name} <-> {internet_iface}")

    # Allow all traffic on ogstun
    iptables_allow_all(if_name)


if __name__ == "__main__":
    main()
