#!/usr/bin/env python3

from argparse import ArgumentParser
import signal
import sys

from gnuradio import blocks
from gnuradio import gr
from gnuradio import zeromq


class ZmqUeBridge(gr.top_block):
    def __init__(self, ue_ids, gnb_ip: str, bridge_ip: str, ue_ip_base: int):
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
        self.gnb_ul_sink = zeromq.rep_sink(
            gr.sizeof_gr_complex,
            1,
            f"tcp://{bridge_ip}:2001",
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
            ue_ip = f"10.10.3.{ue_ip_base + i}"

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
                f"tcp://{bridge_ip}:{dl_port}",
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
    parser.add_argument("--gnb-ip", default="10.10.3.231", help="gNB N3 IP")
    parser.add_argument("--bridge-ip", default="10.10.3.236", help="Bridge IP on N3")
    parser.add_argument(
        "--ue-ip-base",
        type=int,
        default=233,
        help="Last-octet base for UE IP allocation (UE1=base+1, UE2=base+2)",
    )
    args = parser.parse_args()

    if args.ue_ids.strip():
        ue_ids = [int(x.strip()) for x in args.ue_ids.split(",") if x.strip()]
    else:
        ue_ids = list(range(1, args.num_ues + 1))

    if not ue_ids:
        raise ValueError("No UE IDs provided to bridge")

    tb = ZmqUeBridge(ue_ids, args.gnb_ip, args.bridge_ip, args.ue_ip_base)

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
