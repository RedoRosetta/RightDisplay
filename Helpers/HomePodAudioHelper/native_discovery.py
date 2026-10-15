# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Persistent macOS DNS-SD discovery, adapted to the pinned pyatv 0.16.1 parser.

The system daemon owns multicast/interface selection. No shell output is parsed,
no credentials are created, and discovery never connects to a receiver.
"""

import asyncio
import ctypes as C
from ipaddress import IPv4Address
import socket
import time
import uuid

from pyatv.core import mdns
from pyatv.core.scan import BaseScanner
from pyatv.protocols import PROTOCOLS
from pyatv.support.collections import CaseInsensitiveDict


REF = C.c_void_p
U32 = C.c_uint32
I32 = C.c_int32
STR = C.c_char_p
BROWSE = C.CFUNCTYPE(None, REF, U32, U32, I32, STR, STR, STR, REF)
RESOLVE = C.CFUNCTYPE(None, REF, U32, U32, I32, STR, STR, C.c_uint16,
                     C.c_uint16, REF, REF)
ADDRESS = C.CFUNCTYPE(None, REF, U32, U32, I32, STR, REF, U32, REF)


def decode_txt(data):
    """Preserve DNS-SD TXT semantics and pyatv's case-insensitive properties."""
    result = CaseInsensitiveDict()
    offset = 0
    while offset < len(data):
        length = data[offset]
        offset += 1
        if offset + length > len(data):
            raise ValueError("truncated DNS-SD TXT record")
        item = data[offset:offset + length]
        offset += length
        key, _, value = item.partition(b"=")
        if key:
            result[key.decode("utf-8")] = mdns.decode_value(value)
    return result


class NativeDiscovery:
    def __init__(self, loop, diagnostic):
        self.loop = loop
        self.log = diagnostic
        self.context = str(uuid.uuid4())
        self.refs = {}  # Keep callbacks alive for as long as the C API uses them.
        self.records = {}
        self.lib = C.CDLL("/usr/lib/libSystem.B.dylib")
        signatures = {
            "DNSServiceBrowse": ([C.POINTER(REF), U32, U32, STR, STR, BROWSE, REF], I32),
            "DNSServiceResolve": ([C.POINTER(REF), U32, U32, STR, STR, STR, RESOLVE, REF], I32),
            "DNSServiceGetAddrInfo": ([C.POINTER(REF), U32, U32, U32, STR, ADDRESS, REF], I32),
            "DNSServiceRefSockFD": ([REF], C.c_int),
            "DNSServiceProcessResult": ([REF], I32),
            "DNSServiceRefDeallocate": ([REF], None),
        }
        for name, (args, result) in signatures.items():
            fn = getattr(self.lib, name)
            fn.argtypes, fn.restype = args, result

    def _callback(self, kind, function):
        def guarded(*args):
            try:
                function(*args)
            except Exception as error:
                self.log("discovery.native.callback_error", context=self.context,
                         error=repr(error))
        return kind(guarded)

    def _start(self, key, api, callback, *args):
        self._stop(key)
        ref = REF()
        error = getattr(self.lib, api)(C.byref(ref), *args, callback, None)
        if error:
            raise RuntimeError(f"{api}: DNS-SD error {error}")
        fd = self.lib.DNSServiceRefSockFD(ref)
        if fd < 0:
            self.lib.DNSServiceRefDeallocate(ref)
            raise RuntimeError(f"{api}: invalid DNS-SD socket")
        self.refs[key] = (ref, fd, callback)
        self.loop.add_reader(fd, self._process, key)

    def _stop(self, key):
        entry = self.refs.pop(key, None)
        if entry:
            ref, fd, callback = entry
            self.loop.remove_reader(fd)
            self.lib.DNSServiceRefDeallocate(ref)

    def _process(self, key):
        entry = self.refs.get(key)
        if entry:
            error = self.lib.DNSServiceProcessResult(entry[0])
            if error:
                self.log("discovery.native.error", context=self.context, error=error)
                # Do not expose stale identities following a daemon failure.
                self.close()

    def start(self):
        types = sorted({kind for methods in PROTOCOLS.values() for kind in methods.scan()})
        try:
            for kind in types:
                regtype = kind.removesuffix(".local")
                self._start(("browse", kind), "DNSServiceBrowse",
                            self._callback(BROWSE, self._browse),
                            0, 0, regtype.encode(), b"local.")
        except Exception:
            self.close()
            raise
        self.log("discovery.context.started", context=self.context,
                 scanner="macOS DNS-SD", service_types=types)

    def _browse(self, ref, flags, interface, error, name, regtype, domain, context):
        if error:
            self.log("discovery.native.browse_error", context=self.context, error=error)
            self.loop.call_soon(self.close)
            return
        key = (name, regtype, domain, interface)
        added = bool(flags & 2)
        self.log("discovery.service.changed", context=self.context,
                 state="Added" if added else "Removed", interface=interface,
                 name=name.decode(), service_type=regtype.decode())
        if not added:
            self.records.pop(key, None)
            self._stop(("resolve", key))
            self._stop(("address", key))
            return

        def resolved(ref, flags, index, error, fullname, host, port, size, txt, context):
            self.records.pop(key, None)
            if error:
                self.log("discovery.native.resolve_error", context=self.context,
                         name=name.decode(), error=error)
                return
            properties = decode_txt(C.string_at(txt, size)) if size else CaseInsensitiveDict()
            kind = regtype.decode().rstrip(".") + "." + domain.decode().rstrip(".")
            self.records[key] = {"type": kind, "name": name.decode(),
                                 "port": socket.ntohs(port), "properties": properties,
                                 "addresses": {}}

            def addressed(ref, flags, index, error, hostname, address, ttl, context):
                record = self.records.get(key)
                if record is None:
                    return
                if error:
                    record["addresses"].clear()
                    self.log("discovery.native.address_error", context=self.context,
                             name=name.decode(), error=error)
                    return
                # macOS sockaddr has sa_len then sa_family; pyatv 0.16.1 uses IPv4.
                raw = C.string_at(address, 8)
                if raw[1] != socket.AF_INET:
                    return
                ip = IPv4Address(raw[4:8])
                if flags & 2:
                    record["addresses"][ip] = time.monotonic() + ttl
                else:
                    record["addresses"].pop(ip, None)
                self.log("discovery.native.resolved", context=self.context,
                         name=record["name"], service_type=kind, address=str(ip),
                         port=record["port"], interface=index, added=bool(flags & 2),
                         identifier=properties.get("deviceid"))

            self._start(("address", key), "DNSServiceGetAddrInfo",
                        self._callback(ADDRESS, addressed), 0, index, 1, host)

        self._start(("resolve", key), "DNSServiceResolve",
                    self._callback(RESOLVE, resolved), 0, interface, name, regtype, domain)

    def snapshot(self):
        services = {}
        now = time.monotonic()
        for record in self.records.values():
            for address, expiry in record["addresses"].items():
                if expiry > now:
                    service = mdns.Service(record["type"], record["name"], address,
                                           record["port"], record["properties"])
                    services[(address, service.type, service.name)] = service
        return list(services.values())

    async def scan(self, timeout, storage, identifier=None):
        if not self.refs:
            self.start()
        # Bounded initial collection. Subsequent requests reuse live service records.
        if not self.snapshot():
            await asyncio.sleep(timeout)
        scanner = NativeScanner(self.snapshot())
        devices = (await scanner.discover(0)).values()
        configs = [device for device in devices if device.ready and
                   (identifier is None or identifier in device.all_identifiers)]
        for device in configs:
            device.apply(await storage.get_settings(device))
        self.log("discovery.native.assembled", context=self.context,
                 services=len(scanner.native_services), count=len(configs),
                 filtered=identifier is not None)
        return configs

    def close(self):
        for key in list(self.refs):
            self._stop(key)
        self.records.clear()


class NativeScanner(BaseScanner):
    """Only transport changes; retain pyatv's protocol parsers and service_info."""
    def __init__(self, services):
        super().__init__()
        self.native_services = services
        for protocol, methods in PROTOCOLS.items():
            self.add_service_info(protocol, methods.service_info)
            for kind, handler in methods.scan().items():
                self.add_service(kind, handler, methods.device_info)

    async def process(self, timeout):
        groups = {}
        for service in self.native_services:
            groups.setdefault(service.address, []).append(service)
        for services in groups.values():
            self.handle_response(mdns.Response(services, False, None))
