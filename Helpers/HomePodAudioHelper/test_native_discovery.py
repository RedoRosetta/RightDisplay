# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Offline regression tests; never browse, connect, or load user credentials."""
import asyncio
from ipaddress import IPv4Address
import time
import unittest

from native_discovery import NativeDiscovery, NativeScanner, decode_txt
from pyatv.core.mdns import Service


class DiscoveryTests(unittest.IsolatedAsyncioTestCase):
    def test_txt(self):
        self.assertEqual(decode_txt(b"\x09MODEL=ATV")["model"], "ATV")
        with self.assertRaises(ValueError):
            decode_txt(b"\x20bad")

    async def test_removed_and_expired_services(self):
        d = NativeDiscovery(asyncio.get_running_loop(), lambda *a, **kw: None)
        key = (b"TV", b"_airplay._tcp.", b"local.", 14)
        d.records[key] = dict(type="_airplay._tcp.local", name="TV", port=7000,
                              properties={}, addresses={IPv4Address("192.0.2.1"): time.monotonic() + 30})
        self.assertEqual(len(d.snapshot()), 1)
        d.records[(*key[:3], 17)] = d.records[key].copy()
        self.assertEqual(len(d.snapshot()), 1)  # Same service on two interfaces.
        d._browse(None, 0, 14, 0, *key[:3], None)
        self.assertEqual(len(d.snapshot()), 1)
        d._browse(None, 0, 17, 0, *key[:3], None)
        self.assertFalse(d.snapshot())
        d.records[key] = dict(type="_airplay._tcp.local", name="TV", port=7000,
                              properties={}, addresses={IPv4Address("192.0.2.1"): time.monotonic() - 1})
        self.assertFalse(d.snapshot())

    async def test_pyatv_assembly_and_exact_identity(self):
        services = [Service("_airplay._tcp.local", "Test TV", IPv4Address("192.0.2.1"),
                            7000, {"deviceid": "AA:BB:CC:DD:EE:FF", "model": "AppleTV14,1",
                                   "features": "0x4A7FDFD5,0x3C177FDE"})]
        devices = list((await NativeScanner(services).discover(0)).values())
        self.assertEqual(len(devices), 1)
        self.assertTrue(devices[0].ready)
        self.assertIn("AA:BB:CC:DD:EE:FF", devices[0].all_identifiers)
        self.assertNotIn("00:00:00:00:00:00", devices[0].all_identifiers)


if __name__ == "__main__":
    unittest.main()
