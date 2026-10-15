#!/usr/bin/env python3
# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""JSON command helper for Apple TV/HomePod audio control via pyatv."""

import argparse
import asyncio
from datetime import datetime, timezone
import json
import os
import socket
import subprocess
import sys
import time
import traceback
import uuid
from pathlib import Path

import pyatv
from pyatv.const import OperatingSystem, Protocol
from pyatv.interface import DeviceListener, AudioListener
from pyatv.storage.file_storage import FileStorage
from native_discovery import NativeDiscovery
from audio_session import (
    PairingSession,
    audio_feature_states,
    available_feature_names,
    audio_snapshot,
    connection_protocol,
    set_verified_volume,
    remote_audio,
)
from pyatv.const import FeatureName, FeatureState


def emit(payload):
    print(json.dumps(payload, ensure_ascii=False), flush=True)


RUNTIME_ID = str(uuid.uuid4())


def diagnostic(event, **details):
    """Emit structured diagnostics without mixing them with request replies."""
    emit(
        {
            "diagnostic": True,
            "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
            "runtime": RUNTIME_ID,
            "pid": os.getpid(),
            "event": event,
            **details,
        }
    )


class ConnectionListener(DeviceListener):
    def __init__(self, identifier, state_snapshot=None, connection_protocol=None):
        self.identifier = identifier
        self.closed = False
        self.state_snapshot = state_snapshot
        self.connection_protocol = connection_protocol
        self.expected_close = False

    def _log_state(self, event, **details):
        if self.state_snapshot is not None:
            try:
                details.update(self.state_snapshot())
            except Exception as error:
                details["state_snapshot_error"] = repr(error)
        diagnostic(event, identifier=self.identifier, expected_close=self.expected_close, **details)

    def connection_lost(self, exception):
        self.closed = True
        self._log_state("pyatv.connection_lost", connection_state="lost", error=repr(exception),
                        traceback="".join(traceback.format_exception(exception)))

    def connection_closed(self):
        self.closed = True
        self._log_state("pyatv.connection_closed", connection_state="closed")

class VolumeListener(AudioListener):
    def __init__(self, changed):
        self.changed = changed

    def volume_update(self, old_level, new_level):
        self.changed()

    def outputdevices_update(self, old_devices, new_devices):
        self.changed()


def supported_audio_target(config):
    """Expose Apple TV and HomePod, but not every generic AirPlay receiver."""
    info = config.device_info
    model = (info.model_str or "").lower()
    name = (config.name or "").lower()
    return (
        info.operating_system == OperatingSystem.TvOS
        or "homepod" in model
        or "homepod" in name
    )


def device_payload(config):
    info = config.device_info
    model = info.model_str or "Apple 音频设备"
    is_homepod = "homepod" in model.lower() or "homepod" in (config.name or "").lower()
    return {
        "id": config.identifier,
        "name": config.name,
        "address": str(config.address),
        "model": model,
        "kind": "homepod" if is_homepod else "appletv",
        "paired": any(bool(service.credentials) for service in config.services),
    }


def connection_service_observation(config):
    address = getattr(config, "address", None)
    services = []
    for service in getattr(config, "services", ()):
        service_protocol = getattr(service, "protocol", None)
        identifier = getattr(service, "identifier", None)
        services.append({
            "protocol": getattr(service_protocol, "name", str(service_protocol or "unavailable")),
            "port": getattr(service, "port", None),
            "identifier": str(identifier) if identifier is not None else None,
            "credentials_present": bool(getattr(service, "credentials", None)),
        })
    return {
        "config_address": str(address) if address is not None else None,
        "services": services,
    }


def audio_state_observation(device, connection_protocol_name=None):
    try:
        audio = remote_audio(device)
        result = audio_snapshot(audio)
        result["available_features"] = available_feature_names(audio)
        result["audio_feature_states"] = audio_feature_states(audio)
        result["remote_audio_protocol"] = getattr(audio, "protocol", "unavailable")
    except Exception as error:
        result = {"snapshot_error": repr(error)}
    if connection_protocol_name is not None:
        result["connection_protocol"] = connection_protocol_name
    return result


class AudioStateObserver:
    """Observe cached pyatv state even when volume/output callbacks do not fire.

    This neither starts playback nor writes volume. The last connected sample is
    diagnostic history only: pyatv may block its facade before notifying loss.
    """
    def __init__(self, device, identifier, protocol, listener):
        self.device, self.identifier = device, identifier
        self.protocol, self.listener = protocol, listener
        self.last = None
        self.last_at = None

    async def sample(self):
        state = audio_state_observation(self.device, self.protocol)
        try:
            # MRP's playing() reads PlayerStateManager; it does not start a stream.
            playing = await asyncio.wait_for(self.device.metadata.playing(), 1)
            state["playback_state"] = playing.device_state.name
        except Exception as error:
            state["playback_state"] = "UNKNOWN"
            state["playback_observation_error"] = type(error).__name__
        if self.listener.closed or self.listener.expected_close:
            return
        changed = state != self.last
        self.last, self.last_at = state, datetime.now(timezone.utc).isoformat(timespec="milliseconds")
        if changed:
            diagnostic("audio.state.changed", identifier=self.identifier,
                       connection_state="connected", **state)
            if "snapshot_error" not in state:
                emit({"event": "volume_update", "identifier": self.identifier,
                      "volume": state.get("volume"), "outputs": state.get("outputs", []),
                      "can_set_volume": state.get("can_set_volume", False),
                      "remote_protocol": state.get("remote_protocol", "unavailable")})

    def loss_snapshot(self):
        return {**audio_state_observation(self.device, self.protocol),
                "last_connected_state": self.last,
                "last_connected_state_at": self.last_at}

    async def run(self):
        while not self.listener.closed and not self.listener.expected_close:
            await self.sample()
            await asyncio.sleep(2)


def pairing_target_observation(config, protocol, discovery):
    """Describe the exact pyatv endpoint and route for one user-started pairing."""
    service = config.get_service(protocol)
    raw_address = getattr(config, "address", None)
    address = str(raw_address) if raw_address is not None else None
    route = {"status": "unavailable", "interface": None}
    if address:
        try:
            result = subprocess.run(
                ["/sbin/route", "-n", "get", address],
                capture_output=True,
                text=True,
                check=False,
                timeout=1,
            )
            interface = next(
                (line.split(":", 1)[1].strip() for line in result.stdout.splitlines()
                 if line.lstrip().startswith("interface:")),
                None,
            )
            route = {
                "status": "ok" if result.returncode == 0 else f"exit-{result.returncode}",
                "interface": interface,
            }
        except Exception as error:
            route["error"] = type(error).__name__

    service_type = {
        Protocol.AirPlay: "_airplay._tcp.local",
        Protocol.Companion: "_companion-link._tcp.local",
    }.get(protocol)
    native_interfaces = set()
    if service is not None and service_type is not None and address is not None:
        expected_identifier = str(getattr(service, "identifier", None) or "").casefold()
        service_port = getattr(service, "port", None)
        now = time.monotonic()
        for key, record in discovery.records.items():
            if record.get("type") != service_type or record.get("port") != service_port:
                continue
            observed_identifier = str(record.get("properties", {}).get("deviceid") or "").casefold()
            if expected_identifier and observed_identifier and expected_identifier != observed_identifier:
                continue
            if not any(
                str(candidate_address) == address and expiry > now
                for candidate_address, expiry in record.get("addresses", {}).items()
            ):
                continue
            interface_index = key[3]
            try:
                interface_name = socket.if_indextoname(interface_index)
            except OSError:
                interface_name = None
            native_interfaces.add((interface_index, interface_name))
    return {
        "config_name": getattr(config, "name", None),
        "config_identifier": str(getattr(config, "identifier", "unavailable")),
        "target_address": address,
        "target_port": getattr(service, "port", None) if service is not None else None,
        "target_service_identifier": (
            str(service.identifier) if service is not None and getattr(service, "identifier", None) is not None else None
        ),
        "native_interfaces": [
            {"index": index, "name": name}
            for index, name in sorted(native_interfaces)
        ],
        "route": route,
    }


async def load_storage(path, loop):
    target = Path(path).expanduser()
    target.parent.mkdir(parents=True, exist_ok=True)
    storage = FileStorage(str(target), loop)
    await storage.load()
    return storage


async def scan_devices(args, loop, storage):
    configs = await pyatv.scan(loop, timeout=args.timeout, storage=storage)
    devices = []
    for config in configs:
        if not supported_audio_target(config):
            continue
        devices.append(device_payload(config))
    emit({"ok": True, "devices": devices})


async def find_config(args, loop, storage):
    configs = await pyatv.scan(
        loop, identifier=args.identifier, timeout=args.timeout, storage=storage
    )
    if not configs:
        raise RuntimeError("没有发现已选择的 Apple TV 或 HomePod")
    return configs[0]


async def pair_device(args, loop, storage):
    config = await find_config(args, loop, storage)
    pairing = await pyatv.pair(
        config, Protocol.AirPlay, loop, storage=storage, name="Right Display"
    )
    try:
        await pairing.begin()
        if not pairing.device_provides_pin:
            raise RuntimeError("Apple TV 没有提供屏幕验证码配对")
        emit({"ok": True, "event": "pin_required"})
        pin = await loop.run_in_executor(None, sys.stdin.readline)
        if not pin.strip():
            raise RuntimeError("没有输入 Apple TV 验证码")
        pairing.pin(pin.strip())
        await pairing.finish()
        if not pairing.has_paired:
            raise RuntimeError("Apple TV 配对失败")
        await storage.save()
        emit({"ok": True, "event": "paired"})
    finally:
        await pairing.close()


async def with_connection(args, loop, storage, action):
    config = await find_config(args, loop, storage)
    device = await pyatv.connect(config, loop, storage=storage)
    try:
        return await action(device)
    finally:
        pending = device.close()
        if pending:
            await asyncio.gather(*pending, return_exceptions=True)


async def status(args, loop, storage):
    async def read(device):
        outputs = device.audio.output_devices
        emit(
            {
                "ok": True,
                "name": device.device_info.model_str,
                "volume": float(device.audio.volume),
                "outputs": [
                    {
                        "id": item.identifier,
                        "name": item.name,
                        "volume": getattr(item, "volume", None),
                    }
                    for item in outputs
                ],
            }
        )

    await with_connection(args, loop, storage, read)


async def set_volume(args, loop, storage):
    async def write(device):
        await device.audio.set_volume(max(0.0, min(100.0, args.value)))
        emit({"ok": True, "volume": float(device.audio.volume)})

    await with_connection(args, loop, storage, write)


async def adjust_volume(args, loop, storage):
    async def adjust(device):
        if args.command == "volume-up":
            await device.audio.volume_up()
        else:
            await device.audio.volume_down()
        emit({"ok": True})

    await with_connection(args, loop, storage, adjust)


async def serve(args, loop, storage):
    """Keep one Apple TV connection alive and exchange newline-delimited JSON."""
    connected = None
    connected_identifier = None
    connected_protocol = None
    connection_listener = None
    volume_listener = None
    state_task = None
    discovery = NativeDiscovery(loop, diagnostic)
    discovery.start()
    discovery_context_id = discovery.context

    async def pairing_factory(config, protocol):
        return await pyatv.pair(config, protocol, loop, storage=storage, name="Right Display")

    pairing_session = PairingSession(pairing_factory, storage.save, emit)

    async def close_connected():
        nonlocal connected, connected_identifier, connection_listener, volume_listener, state_task
        if connection_listener is not None:
            connection_listener.expected_close = True
        if state_task is not None:
            state_task.cancel()
            await asyncio.gather(state_task, return_exceptions=True)
            state_task = None
        if connected is not None:
            diagnostic("pyatv.disconnect.begin", identifier=connected_identifier)
            pending = connected.close()
            if pending:
                try:
                    await asyncio.wait_for(asyncio.gather(*pending, return_exceptions=True), 5)
                except asyncio.TimeoutError:
                    diagnostic("pyatv.disconnect.timeout")
            diagnostic("pyatv.disconnect.end", identifier=connected_identifier)
        connected = None
        connected_identifier = None
        connection_listener = None
        volume_listener = None

    async def config_for(identifier=None):
        discovery_id = str(uuid.uuid4())
        diagnostic(
            "discovery.begin",
            discovery=discovery_id,
            identifier=identifier,
            scanner="macOS persistent Bonjour",
            discovery_context=discovery_context_id,
        )
        try:
            configs = await discovery.scan(
                identifier=identifier,
                timeout=args.timeout,
                storage=storage,
            )
        except Exception as error:
            diagnostic(
                "discovery.error",
                discovery=discovery_id,
                error=repr(error),
                traceback=traceback.format_exc(),
            )
            raise
        diagnostic("discovery.end", discovery=discovery_id, count=len(configs))
        if not configs:
            if identifier is not None:
                observation_id = str(uuid.uuid4())
                diagnostic(
                    "discovery.identity_observation.begin",
                    discovery=observation_id,
                    saved_identifier=identifier,
                    scanner="macOS persistent Bonjour",
                    discovery_context=discovery_context_id,
                )
                try:
                    observed_configs = await discovery.scan(
                        timeout=min(5, args.timeout),
                        storage=storage,
                    )
                    diagnostic(
                        "discovery.identity_observation.end",
                        discovery=observation_id,
                        saved_identifier=identifier,
                        count=len(observed_configs),
                    )
                    for index, observed in enumerate(observed_configs):
                        diagnostic(
                            "discovery.identity_observation.candidate",
                            discovery=observation_id,
                            saved_identifier=identifier,
                            index=index,
                            name=observed.name,
                            config_identifier=str(observed.identifier),
                            address=str(observed.address),
                            services=[
                                {
                                    "protocol": getattr(
                                        service.protocol, "name", str(service.protocol)
                                    ),
                                    "identifier": (
                                        str(service.identifier)
                                        if service.identifier is not None
                                        else None
                                    ),
                                }
                                for service in observed.services
                            ],
                        )
                except Exception as observation_error:
                    diagnostic(
                        "discovery.identity_observation.error",
                        discovery=observation_id,
                        saved_identifier=identifier,
                        error=repr(observation_error),
                        traceback=traceback.format_exc(),
                    )
            raise RuntimeError("没有发现已选择的 Apple TV 或 HomePod")
        return configs[0]

    async def connection_for(identifier, preferred_protocol="auto"):
        nonlocal connected, connected_identifier, connection_listener, connected_protocol, volume_listener, state_task
        if (connected is not None and connected_identifier == identifier
                and connected_protocol == preferred_protocol
                and connection_listener is not None and not connection_listener.closed):
            return connected
        await close_connected()
        config = await config_for(identifier)
        protocol = (Protocol.Companion if preferred_protocol == "companion" else
                    Protocol.AirPlay if preferred_protocol == "airplay" else connection_protocol(config))
        service_observation = connection_service_observation(config)
        diagnostic(
            "pyatv.connect.begin",
            identifier=identifier,
            protocol=protocol.name if protocol else "auto",
            **service_observation,
        )
        try:
            connected = await asyncio.wait_for(
                pyatv.connect(config, loop, storage=storage, protocol=protocol), 10)
        except Exception as error:
            diagnostic(
                "pyatv.connect.error",
                identifier=identifier,
                protocol=protocol.name if protocol else "auto",
                **service_observation,
                error=repr(error),
                traceback=traceback.format_exc(),
            )
            raise
        connected_identifier = identifier
        connected_protocol = preferred_protocol
        observed_device = connected

        def connection_state_snapshot():
            return audio_state_observation(observed_device, protocol.name if protocol else "auto")

        connection_listener = ConnectionListener(
            identifier,
            connection_state_snapshot,
            protocol.name if protocol else "auto",
        )
        observer = AudioStateObserver(observed_device, identifier,
                                      protocol.name if protocol else "auto", connection_listener)
        connection_listener.state_snapshot = observer.loss_snapshot
        connected.listener = connection_listener

        def changed():
            if connected is not observed_device or connection_listener.closed:
                return
            audio = remote_audio(observed_device)
            snapshot = audio_snapshot(audio)
            diagnostic(
                "volume.remote_update",
                identifier=identifier,
                protocol=protocol.name,
                connection_state="connected",
                available_features=available_feature_names(audio),
                audio_feature_states=audio_feature_states(audio),
                **snapshot,
            )
            emit({"event": "volume_update", "identifier": identifier, **snapshot})
        volume_listener = VolumeListener(changed)
        connected.audio.listener = volume_listener
        diagnostic("pyatv.connect.end", identifier=identifier, **connection_state_snapshot())
        # AirPlay publishes its authoritative output-group volume shortly after
        # the transport connects. Avoid returning the protocol's placeholder.
        await asyncio.sleep(1.0)
        if connection_listener.closed:
            raise RuntimeError("Apple TV 音频连接在初始化时中断")
        state_task = asyncio.create_task(observer.run())
        return connected

    async def read_line():
        return await loop.run_in_executor(None, sys.stdin.readline)

    try:
        diagnostic("helper.serve.begin")
        should_stop = False
        while True:
            line = await read_line()
            if not line:
                diagnostic("helper.stdin.eof")
                break
            request = {}
            try:
                request = json.loads(line)
                request_id = request.get("request")
                action = request.get("action")
                diagnostic("ipc.request", request=request_id, action=action)
                if action == "shutdown":
                    await close_connected()
                    emit({"request": request_id, "ok": True})
                    should_stop = True
                elif action == "reconnect":
                    await close_connected()
                    diagnostic(
                        "discovery.context.retained",
                        context=discovery_context_id,
                    )
                    emit({"request": request_id, "ok": True})
                elif action == "scan":
                    discovery_id = str(uuid.uuid4())
                    diagnostic(
                        "discovery.begin",
                        discovery=discovery_id,
                        request=request_id,
                        scanner="macOS persistent Bonjour",
                        discovery_context=discovery_context_id,
                    )
                    try:
                        configs = await discovery.scan(
                            timeout=args.timeout,
                            storage=storage,
                        )
                    except Exception as error:
                        diagnostic(
                            "discovery.error",
                            discovery=discovery_id,
                            request=request_id,
                            error=repr(error),
                            traceback=traceback.format_exc(),
                        )
                        raise
                    diagnostic(
                        "discovery.end",
                        discovery=discovery_id,
                        request=request_id,
                        count=len(configs),
                    )
                    devices = []
                    for config in configs:
                        if supported_audio_target(config):
                            devices.append(device_payload(config))
                    emit({"request": request_id, "ok": True, "devices": devices})
                elif action == "pair_begin":
                    identifier = request.get("identifier")
                    config = await config_for(identifier)
                    protocol = {"airplay": Protocol.AirPlay,
                                "companion": Protocol.Companion}.get(request.get("protocol"))
                    if protocol is None:
                        raise RuntimeError("未知配对协议")
                    diagnostic(
                        "pair.target",
                        request=request_id,
                        identifier=identifier,
                        protocol=protocol.name,
                        **pairing_target_observation(config, protocol, discovery),
                    )
                    token = await pairing_session.begin(config, identifier, protocol)
                    diagnostic("pair.begin", identifier=identifier, protocol=protocol.name)
                    emit({"request": request_id, "ok": True, "token": token})
                elif action == "pair_pin":
                    await pairing_session.finish(request.get("identifier"), request.get("token"),
                                                 str(request.get("pin", "")).strip())
                    # Keep the prior transport alive on failure/cancel. Only replace
                    # it after confirmed pairing so the next status loads new credentials.
                    await close_connected()
                    diagnostic("pair.saved", identifier=request.get("identifier"))
                    emit({"request": request_id, "ok": True})
                elif action == "pair_cancel":
                    await pairing_session.cancel()
                    emit({"request": request_id, "ok": True})
                elif action in {"status", "set_volume", "volume_up", "volume_down"}:
                    if pairing_session.handler:
                        raise RuntimeError("请先完成或取消配对")
                    device = await connection_for(request.get("identifier"), request.get("protocol", "auto"))
                    if action == "set_volume":
                        value = max(0.0, min(100.0, float(request.get("value", 0))))
                        audio = remote_audio(device)
                        diagnostic(
                            "volume.set.begin",
                            request=request_id,
                            value=value,
                            connection_protocol=(connection_listener.connection_protocol if connection_listener else "unavailable"),
                            connection_state=("closed" if connection_listener and connection_listener.closed else "connected"),
                            **audio_state_observation(device),
                        )
                        try:
                            snapshot = await set_verified_volume(audio, value)
                            if connection_listener.closed:
                                raise RuntimeError("音量写入期间连接中断，结果未确认")
                        except Exception as error:
                            diagnostic(
                                "volume.set.error",
                                request=request_id,
                                identifier=request.get("identifier"),
                                requested=value,
                                connection_protocol=(connection_listener.connection_protocol if connection_listener else "unavailable"),
                                connection_state=("closed" if connection_listener and connection_listener.closed else "connected"),
                                **audio_state_observation(device),
                                error=repr(error),
                            )
                            raise
                        diagnostic(
                            "volume.set.confirmed",
                            request=request_id,
                            requested=value,
                            actual=snapshot["volume"],
                            connection_protocol=(connection_listener.connection_protocol if connection_listener else "unavailable"),
                            connection_state=("closed" if connection_listener and connection_listener.closed else "connected"),
                            **audio_state_observation(device),
                        )
                        emit({"request": request_id, "ok": True, **snapshot})
                    elif action == "volume_up":
                        audio = remote_audio(device)
                        await set_verified_volume(audio, min(100, (audio_snapshot(audio)["volume"] or 0) + 4))
                        emit({"request": request_id, "ok": True})
                    elif action == "volume_down":
                        audio = remote_audio(device)
                        await set_verified_volume(audio, max(0, (audio_snapshot(audio)["volume"] or 0) - 4))
                        emit({"request": request_id, "ok": True})
                    else:
                        diagnostic("volume.read.begin", request=request_id)
                        audio = remote_audio(device)
                        snapshot = audio_snapshot(audio)
                        diagnostic(
                            "volume.read.end",
                            request=request_id,
                            connection_protocol=(connection_listener.connection_protocol if connection_listener else "unavailable"),
                            connection_state=("closed" if connection_listener and connection_listener.closed else "connected"),
                            **audio_state_observation(device),
                        )
                        emit({"request": request_id, "ok": True, **snapshot})
                else:
                    raise RuntimeError("未知的 Apple TV 音频命令")
            except Exception as error:
                diagnostic(
                    "ipc.error",
                    request=request.get("request") if "request" in locals() else None,
                    action=request.get("action") if "request" in locals() else None,
                    error=repr(error),
                    traceback=traceback.format_exc(),
                )
                emit(
                    {
                        "request": request.get("request") if "request" in locals() else None,
                        "ok": False,
                        "error": str(error) or type(error).__name__,
                    }
                )
            if should_stop:
                diagnostic("helper.shutdown.completed")
                break
    finally:
        try:
            await pairing_session.cancel()
        finally:
            try:
                await close_connected()
            finally:
                discovery.close()
        diagnostic(
            "discovery.context.closed",
            context=discovery_context_id,
        )
        diagnostic("helper.serve.end")


async def main_async(args):
    loop = asyncio.get_running_loop()
    loop.set_exception_handler(
        lambda _loop, context: diagnostic(
            "asyncio.unhandled_exception",
            message=context.get("message"),
            error=repr(context.get("exception")),
        )
    )
    diagnostic(
        "helper.start",
        command=args.command,
        python=sys.version.split()[0],
        pyatv=getattr(pyatv, "__version__", "unknown"),
    )
    storage = await load_storage(args.storage, loop)
    if args.command == "scan":
        await scan_devices(args, loop, storage)
    elif args.command == "serve":
        await serve(args, loop, storage)
    elif args.command == "pair":
        await pair_device(args, loop, storage)
    elif args.command == "status":
        await status(args, loop, storage)
    elif args.command == "set-volume":
        await set_volume(args, loop, storage)
    else:
        await adjust_volume(args, loop, storage)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--storage", required=True)
    parser.add_argument("--timeout", type=float, default=5.0)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("scan")
    subparsers.add_parser("serve")
    for name in ("pair", "status", "volume-up", "volume-down"):
        command = subparsers.add_parser(name)
        command.add_argument("--identifier", required=True)
    command = subparsers.add_parser("set-volume")
    command.add_argument("--identifier", required=True)
    command.add_argument("--value", required=True, type=float)
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        asyncio.run(main_async(args))
    except Exception as error:  # Keep Swift-side parsing deterministic.
        diagnostic("helper.fatal", error=repr(error), traceback=traceback.format_exc())
        emit({"ok": False, "error": str(error)})
        raise SystemExit(1)
    finally:
        diagnostic("helper.exit")


if __name__ == "__main__":
    main()
