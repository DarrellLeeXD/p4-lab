"""Host-side wire-format and CLI checks for the Week 5 tunnel."""

import contextlib
import importlib
import io
import unittest

from scapy.all import Ether, IP, Raw, UDP, raw

import send


class PacketTests(unittest.TestCase):
    def test_tunnel_header_keeps_old_fields_first_and_appends_one_hop_byte(self):
        packet = send.MyTunnel(dst_id=3, hops=4)
        self.assertEqual(bytes.fromhex("0800000304"), raw(packet))

    def test_sender_defaults_to_four_hops_and_accepts_zero(self):
        self.assertEqual(4, send.parse_args(["10.40.0.2", "hello", "--tunnel", "2"]).hops)
        self.assertEqual(0, send.parse_args(["10.40.0.2", "hello", "--tunnel", "2", "--hops", "0"]).hops)

    def test_sender_rejects_hops_without_tunnel_or_outside_one_byte(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                send.parse_args(["10.40.0.2", "hello", "--hops", "4"])
            with self.assertRaises(SystemExit):
                send.parse_args(["10.40.0.2", "hello", "--tunnel", "2", "--hops", "256"])

    def test_receiver_import_does_not_start_live_sniffer(self):
        self.assertIsNotNone(importlib.import_module("receive").show)

    def test_receiver_prints_arriving_hop_limit(self):
        receive = importlib.import_module("receive")
        packet = (Ether(type=0x1212) / receive.MyTunnel(dst_id=2, hops=2)
                  / IP(src="10.40.0.1", dst="10.40.0.2")
                  / UDP(sport=4321, dport=4321) / Raw(load=b"hello"))
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            receive.show(packet)
        self.assertIn("dst_id=2, hops=2", output.getvalue())
        self.assertIn("TTL 64", output.getvalue())


if __name__ == "__main__":
    unittest.main()
