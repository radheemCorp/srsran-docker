#!/usr/bin/env python3
# -*- coding: utf-8 -*-

#
# SPDX-License-Identifier: GPL-3.0
#
# GNU Radio Python Flow Graph
# Title: srsRAN_multi_UE
# GNU Radio version: 3.10.1.1

from gnuradio import blocks
from gnuradio import gr
from gnuradio import zeromq
from argparse import ArgumentParser
import signal
import sys
import threading
import time


class multi_ue_scenario(gr.top_block):
    def __init__(
        self,
        gnb_ip,
        bridge_ip,
        gnb_dl_port1,
        gnb_dl_port2,
        gnb_ul_port1,
        gnb_ul_port2,
        ue_tx_port,
        ue_rx_port,
        sweep_seconds,
    ):
        gr.top_block.__init__(self, "srsRAN_multi_UE")

        zmq_timeout = 100
        zmq_hwm = -1
        samp_rate = 23040000

        # Downlink: gNB cell1 + cell2 -> per-cell gain -> sum -> UE RX
        self.dl_cell1 = zeromq.req_source(
            gr.sizeof_gr_complex, 1, f"tcp://{gnb_ip}:{gnb_dl_port1}", zmq_timeout, False, zmq_hwm
        )
        self.dl_cell2 = zeromq.req_source(
            gr.sizeof_gr_complex, 1, f"tcp://{gnb_ip}:{gnb_dl_port2}", zmq_timeout, False, zmq_hwm
        )
        self.dl_gain1 = blocks.multiply_const_cc(1.0)
        self.dl_gain2 = blocks.multiply_const_cc(0.0)
        self.dl_adder = blocks.add_vcc(1)
        self.dl_throttle = blocks.throttle(gr.sizeof_gr_complex, samp_rate, True)
        self.ue_rx_sink = zeromq.rep_sink(
            gr.sizeof_gr_complex, 1, f"tcp://{bridge_ip}:{ue_rx_port}", zmq_timeout, False, zmq_hwm
        )

        # Uplink: UE TX -> split -> per-cell gain -> gNB RX (cell1/cell2)
        self.ue_tx_src = zeromq.req_source(
            gr.sizeof_gr_complex, 1, f"tcp://{bridge_ip}:{ue_tx_port}", zmq_timeout, False, zmq_hwm
        )
        self.ul_gain1 = blocks.multiply_const_cc(1.0)
        self.ul_gain2 = blocks.multiply_const_cc(1.0)
        self.ul_cell1_sink = zeromq.rep_sink(
            gr.sizeof_gr_complex, 1, f"tcp://{bridge_ip}:{gnb_ul_port1}", zmq_timeout, False, zmq_hwm
        )
        self.ul_cell2_sink = zeromq.rep_sink(
            gr.sizeof_gr_complex, 1, f"tcp://{bridge_ip}:{gnb_ul_port2}", zmq_timeout, False, zmq_hwm
        )

        # Connect DL path
        self.connect((self.dl_cell1, 0), (self.dl_gain1, 0))
        self.connect((self.dl_cell2, 0), (self.dl_gain2, 0))
        self.connect((self.dl_gain1, 0), (self.dl_adder, 0))
        self.connect((self.dl_gain2, 0), (self.dl_adder, 1))
        self.connect((self.dl_adder, 0), (self.dl_throttle, 0))
        self.connect((self.dl_throttle, 0), (self.ue_rx_sink, 0))

        # Connect UL path
        self.connect((self.ue_tx_src, 0), (self.ul_gain1, 0))
        self.connect((self.ue_tx_src, 0), (self.ul_gain2, 0))
        self.connect((self.ul_gain1, 0), (self.ul_cell1_sink, 0))
        self.connect((self.ul_gain2, 0), (self.ul_cell2_sink, 0))

        # Start sweep thread to simulate movement between the two cells.
        self._sweep_seconds = max(1, int(sweep_seconds))
        self._sweep_thread = threading.Thread(target=self._sweep_loop, daemon=True)
        self._sweep_thread.start()

    def _sweep_loop(self):
        start = time.time()
        while True:
            elapsed = time.time() - start
            ratio = min(1.0, elapsed / float(self._sweep_seconds))
            gain1 = 1.0 - ratio
            gain2 = ratio
            self.dl_gain1.set_k(gain1)
            self.dl_gain2.set_k(gain2)
            time.sleep(0.1)

def main():
    parser = ArgumentParser(description='srsRAN dual-cell ZMQ channel emulator')
    parser.add_argument('--gnb-ip', type=str, default='10.10.3.231', help='gNB N3 IP for ZMQ DL ports')
    parser.add_argument('--bridge-ip', type=str, default='0.0.0.0', help='Emulator bind IP for ZMQ UL/DL ports')
    parser.add_argument('--gnb-dl-port1', type=int, default=2100, help='gNB DL port for cell 1')
    parser.add_argument('--gnb-dl-port2', type=int, default=2200, help='gNB DL port for cell 2')
    parser.add_argument('--gnb-ul-port1', type=int, default=2101, help='gNB UL port for cell 1')
    parser.add_argument('--gnb-ul-port2', type=int, default=2201, help='gNB UL port for cell 2')
    parser.add_argument('--ue-tx-port', type=int, default=2301, help='UE TX port (emulator connects)')
    parser.add_argument('--ue-rx-port', type=int, default=2300, help='UE RX port (emulator binds)')
    parser.add_argument('--sweep-seconds', type=int, default=60, help='Gain sweep duration in seconds')
    args = parser.parse_args()

    tb = multi_ue_scenario(
        args.gnb_ip,
        args.bridge_ip,
        args.gnb_dl_port1,
        args.gnb_dl_port2,
        args.gnb_ul_port1,
        args.gnb_ul_port2,
        args.ue_tx_port,
        args.ue_rx_port,
        args.sweep_seconds,
    )

    def sig_handler(sig=None, frame=None):
        tb.stop()
        tb.wait()
        sys.exit(0)

    signal.signal(signal.SIGINT, sig_handler)
    signal.signal(signal.SIGTERM, sig_handler)

    tb.start()

    try:
        input('Press Enter to quit: ')
    except EOFError:
        pass
    tb.stop()
    tb.wait()


if __name__ == '__main__':
    main()
