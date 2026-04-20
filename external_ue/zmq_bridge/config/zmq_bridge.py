#!/usr/bin/env python3

from argparse import ArgumentParser
import signal
import sys

from gnuradio import blocks
from gnuradio import gr
from gnuradio import zeromq


class ZmqUeBridge(gr.top_block):
    def __init__(self, ue_ids, gnb_ip: str, bridge_ip: str, ue_ip_base: int, ue_ip_list=None):
        super().__init__("srsRAN_ZMQ_UE_Bridge")

        zmq_timeout = 100
        zmq_hwm = -1
        samp_rate = 23040000

        # gNB side (single pair)
        # gNB tx -> bridge req source (downlink samples)
        self.gnb_dl_source = zeromq.req_source(
            gr.sizeof_gr_complex,
            1,
            f"tcp://{gnb_ip}:2000",
            zmq_timeout,
            False,
            zmq_hwm,
        )
        # bridge rep sink -> gNB rx (uplink aggregate)
        # NOTE: by default the bridge binds its reply sinks to the configured
        # bridge_ip. In multi-network Docker setups it's often preferable to
        # bind on all interfaces (tcp://*:port) so peers from any attached
        # network can connect. The CLI exposes `--bind-all` to enable this.
        bind_addr = f"tcp://{bridge_ip}:2001"
        if getattr(self, 'bind_all', False):
            bind_addr = "tcp://*:2001"
        self.gnb_ul_sink = zeromq.rep_sink(
            gr.sizeof_gr_complex,
            1,
            bind_addr,
            zmq_timeout,
            False,
            zmq_hwm,
        )

        # Aggregate uplink from all UEs
        self.ul_add = blocks.add_vcc(1)
        self.throttle = blocks.throttle(gr.sizeof_gr_complex * 1, samp_rate, True)

        self.connect((self.gnb_dl_source, 0), (self.throttle, 0))
        self.connect((self.ul_add, 0), (self.gnb_ul_sink, 0))

        # UE-specific sockets
        self.ue_ul_sources = []
        self.ue_dl_sinks = []
        for input_idx, i in enumerate(ue_ids):
            ul_port = 2100 + i
            dl_port = 2200 + i
            # derive UE IP from provided ue_ip_list (preferred) or fall back to
            # prefix/base calculation using the provided bridge configuration
            if ue_ip_list and input_idx < len(ue_ip_list):
                ue_ip = ue_ip_list[input_idx]
            else:
                ue_ip = f"10.53.1.{ue_ip_base + i}"

            ue_ul = zeromq.req_source(
                gr.sizeof_gr_complex,
                1,
                f"tcp://{ue_ip}:{ul_port}",
                zmq_timeout,
                False,
                zmq_hwm,
            )
            ue_dl = zeromq.rep_sink(
                gr.sizeof_gr_complex,
                1,
                ("tcp://*:%d" % dl_port) if getattr(self, 'bind_all', False) else f"tcp://{bridge_ip}:{dl_port}",
                zmq_timeout,
                False,
                zmq_hwm,
            )

            self.ue_ul_sources.append(ue_ul)
            self.ue_dl_sinks.append(ue_dl)

            self.connect((ue_ul, 0), (self.ul_add, input_idx))
            self.connect((self.throttle, 0), (ue_dl, 0))


def main():
    parser = ArgumentParser(description="ZMQ bridge for multiple external UEs")
    parser.add_argument("--num-ues", type=int, default=10, help="Maximum number of UEs")
    parser.add_argument(
        "--ue-ids",
        default="",
        help="Comma-separated UE IDs to activate (e.g. 1,2). If empty, uses 1..num-ues",
    )
    parser.add_argument("--gnb-ip", default="10.53.1.3", help="gNB N3 IP")
    parser.add_argument("--bridge-ip", default="10.53.1.6", help="Bridge IP on N3")
    parser.add_argument("--bind-all", action="store_true", help="Bind bridge reply sinks on all interfaces (tcp://*:port)")
    parser.add_argument(
        "--ue-ip-base",
        type=int,
        default=233,
        help="Last-octet base for UE IP allocation (UE1=base+1, UE2=base+2)",
    )
    parser.add_argument(
        "--ue-ip-prefix",
        default="10.53.1.",
        help="IP prefix for computed UE IPs (e.g. '10.53.1.') when --ue-ips isn't provided",
    )
    parser.add_argument(
        "--ue-ips",
        default="",
        help="Comma-separated explicit UE IPs (overrides --ue-ip-prefix/--ue-ip-base)",
    )
    args = parser.parse_args()

    if args.ue_ids.strip():
        ue_ids = [int(x.strip()) for x in args.ue_ids.split(",") if x.strip()]
    else:
        ue_ids = list(range(1, args.num_ues + 1))

    if not ue_ids:
        raise ValueError("No UE IDs provided to bridge")

    # prepare UE IP list: either explicit via --ue-ips or computed using prefix+base
    explicit_ue_ips = [x.strip() for x in args.ue_ips.split(",") if x.strip()] if args.ue_ips.strip() else []
    if explicit_ue_ips:
        ue_ip_list = explicit_ue_ips
    else:
        ue_ip_list = [f"{args.ue_ip_prefix}{args.ue_ip_base + i}" for i in range(1, args.num_ues + 1)]

    tb = ZmqUeBridge(ue_ids, args.gnb_ip, args.bridge_ip, args.ue_ip_base, ue_ip_list)
    # attach computed UE ips list to the top block for internal use
    setattr(tb, 'ue_ip_list', ue_ip_list)
    # If requested, instruct top block to bind reply sinks on all interfaces.
    if args.bind_all:
        setattr(tb, 'bind_all', True)

    def sig_handler(sig=None, frame=None):
        tb.stop()
        tb.wait()
        sys.exit(0)

    signal.signal(signal.SIGINT, sig_handler)
    signal.signal(signal.SIGTERM, sig_handler)

    tb.start()
    signal.pause()


if __name__ == "__main__":
    main()
