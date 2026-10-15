# Native discovery adapter (0.36 Build 34)

The persistent `serve` runtime now uses macOS DNS-SD through libSystem instead
of a Python Zeroconf multicast socket. Browse/resolve/address references live on
the existing asyncio loop and are retained across `reconnect`; `shutdown` closes
every DNS-SD reference. Removed/expired records are excluded from snapshots.
Daemon failure clears records; a later scan can recreate the discovery context.

`native_discovery.NativeScanner` deliberately uses the pinned pyatv **0.16.1**
`BaseScanner`, `PROTOCOLS.scan`, and `service_info` implementations, preserving
protocol-specific TXT parsing, credential application, and `ready` filtering.
This is an internal pyatv adapter: re-run its regression and integration checks
before changing pyatv versions. IPv4 is the current pyatv 0.16.1 scanner contract;
IPv6-only receivers are not supported by this adapter.

Only configurations whose `all_identifiers` contain the exact saved identifier
may be selected for connection. No identity migration, credential replacement,
automatic pairing, or volume commands were added. Standalone legacy CLI commands
remain on their existing path; the App uses the persistent `serve` runtime.

Diagnostics: `discovery.service.changed`, `discovery.native.resolved`,
`discovery.native.assembled`, and explicit callback/daemon/resolve errors correlate
through the helper runtime and discovery context IDs. TXT blobs and credentials
are not logged.

Validation on 2026-09-20:

- Native services assembled Apple TV 4K and both HomePods.
- Existing saved Apple TV identity/credentials connected to tvOS 27.0.
- Source and packaged helper returned volume 35%.
- Packaged `status → reconnect → status → shutdown` passed; the same discovery
  context survived reconnect and was released on shutdown.
- No volume write was performed. HomePod connection, real volume adjustment,
  sleep/wake and long-term reconnect remain manual acceptance items.

Offline tests: run `test_native_discovery.py` with the helper's existing venv.
