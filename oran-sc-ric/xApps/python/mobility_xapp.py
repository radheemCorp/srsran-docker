#!/usr/bin/env python3

import argparse
import signal
import time
from lib.xAppBase import xAppBase


def _first_two(values):
    if isinstance(values, list) and len(values) >= 2:
        return values[0], values[1]
    if isinstance(values, list) and len(values) == 1:
        return values[0], None
    return values, None


class MobilityXapp(xAppBase):
    def __init__(self, config, http_server_port, rmr_port):
        super(MobilityXapp, self).__init__(config, http_server_port, rmr_port)
        self.last_ho_time = 0

    def _should_handover(self, rsrp1, rsrp2, hysteresis_db):
        if rsrp1 is None or rsrp2 is None:
            return False
        return rsrp2 > (rsrp1 + hysteresis_db)

    def _extract_metric(self, meas_data, metric_name):
        data = meas_data.get("measData", {})
        if metric_name not in data:
            return None, None
        return _first_two(data[metric_name])

    def _handle_kpm(self, e2_agent_id, subscription_id, indication_hdr, indication_msg):
        meas_data = self.e2sm_kpm.extract_meas_data(indication_msg)

        rsrp1, rsrp2 = self._extract_metric(meas_data, "RSRP")
        rsrq1, rsrq2 = self._extract_metric(meas_data, "RSRQ")

        now = time.time()
        if self._should_handover(rsrp1, rsrp2, self.hysteresis_db):
            if now - self.last_ho_time < self.ho_min_interval_s:
                return
            print(
                "HO condition met: RSRP2({}) > RSRP1({}) + H({})".format(
                    rsrp2, rsrp1, self.hysteresis_db
                )
            )
            self.e2sm_rc.control_handover(
                self.e2_node_id,
                self.amf_ue_ngap_id,
                self.gnb_cu_ue_f1ap_id,
                self.plmn,
                self.target_nr_cell_id,
            )
            self.last_ho_time = now
        else:
            print(
                "RSRP/RSRQ: cell1=({}, {}), cell2=({}, {})".format(
                    rsrp1, rsrq1, rsrp2, rsrq2
                )
            )

    @xAppBase.start_function
    def start(
        self,
        e2_node_id,
        ue_id,
        amf_ue_ngap_id,
        gnb_cu_ue_f1ap_id,
        plmn,
        target_nr_cell_id,
        hysteresis_db,
        ho_min_interval_s,
    ):
        self.e2_node_id = e2_node_id
        self.ue_id = ue_id
        self.amf_ue_ngap_id = amf_ue_ngap_id
        self.gnb_cu_ue_f1ap_id = gnb_cu_ue_f1ap_id
        self.plmn = plmn
        self.target_nr_cell_id = target_nr_cell_id
        self.hysteresis_db = hysteresis_db
        self.ho_min_interval_s = ho_min_interval_s

        report_period = 1000
        granul_period = 1000
        metrics = ["RSRP", "RSRQ"]

        print(
            "Subscribe to E2 node ID: {}, UE ID: {}, metrics: {}".format(
                e2_node_id, ue_id, metrics
            )
        )
        self.e2sm_kpm.subscribe_report_service_style_2(
            e2_node_id,
            report_period,
            ue_id,
            metrics,
            granul_period,
            self._handle_kpm,
        )


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Closed-loop mobility xApp')
    parser.add_argument('--config', type=str, default='', help='xApp config file path')
    parser.add_argument('--http_server_port', type=int, default=8093, help='HTTP server listen port')
    parser.add_argument('--rmr_port', type=int, default=4563, help='RMR port')
    parser.add_argument('--e2_node_id', type=str, default='gnbd_001_001_00019b_0', help='E2 Node ID')
    parser.add_argument('--kpm_ran_func_id', type=int, default=2, help='E2SM KPM RAN function ID')
    parser.add_argument('--rc_ran_func_id', type=int, default=3, help='E2SM RC RAN function ID')
    parser.add_argument('--ue_id', type=int, default=0, help='gNB-DU UE ID for KPM style 2')
    parser.add_argument('--amf_ue_ngap_id', type=int, default=1, help='AMF UE NGAP ID')
    parser.add_argument('--gnb_cu_ue_f1ap_id', type=int, default=1, help='gNB CU UE F1AP ID')
    parser.add_argument('--plmn', type=str, default='00101', help='PLMN (e.g., 00101)')
    parser.add_argument('--target_nr_cell_id', type=int, default=1, help='Target NR Cell ID (NCI)')
    parser.add_argument('--hysteresis_db', type=float, default=3.0, help='Hysteresis in dB')
    parser.add_argument('--ho_min_interval_s', type=int, default=10, help='Min seconds between HO triggers')

    args = parser.parse_args()

    xapp = MobilityXapp(args.config, args.http_server_port, args.rmr_port)
    xapp.e2sm_kpm.set_ran_func_id(args.kpm_ran_func_id)
    xapp.e2sm_rc.set_ran_func_id(args.rc_ran_func_id)

    signal.signal(signal.SIGQUIT, xapp.signal_handler)
    signal.signal(signal.SIGTERM, xapp.signal_handler)
    signal.signal(signal.SIGINT, xapp.signal_handler)

    xapp.start(
        args.e2_node_id,
        args.ue_id,
        args.amf_ue_ngap_id,
        args.gnb_cu_ue_f1ap_id,
        args.plmn,
        args.target_nr_cell_id,
        args.hysteresis_db,
        args.ho_min_interval_s,
    )
