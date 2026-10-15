# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Bounded pairing and independently queried audio capabilities (no discovery)."""
import asyncio
import uuid
from types import SimpleNamespace

from pyatv.const import FeatureName, FeatureState, Protocol
from pyatv.exceptions import NotSupportedError


def remote_audio(device):
    """Pinned pyatv 0.16 adapter: bind audio AND capability to the same remote protocol.

    AirPlay setup can itself install RAOP, even with protocol=AirPlay. Never
    use the aggregate facade's fallback for control of the TV's existing output.
    """
    for protocol in (Protocol.Companion, Protocol.MRP):
        audio = device.audio.get(protocol) if hasattr(device.audio, "get") else None
        features = device.features.get(protocol) if hasattr(device.features, "get") else None
        if audio is not None and features is not None:
            return SimpleNamespace(audio=audio, features=features, protocol=protocol.name)
    return SimpleNamespace(audio=object(), protocol="unavailable",
                           features=SimpleNamespace(get_feature=lambda _: SimpleNamespace(state=FeatureState.Unsupported)))


def audio_feature_states(device):
    """Return a read-only diagnostic snapshot of the audio-related feature states."""
    result = {}
    for key, feature in (
        ("volume", FeatureName.Volume),
        ("set_volume", FeatureName.SetVolume),
        ("output_devices", FeatureName.OutputDevices),
    ):
        try:
            state = device.features.get_feature(feature).state
            result[key] = getattr(state, "name", str(state))
        except Exception as error:
            result[key] = f"unavailable:{type(error).__name__}"
    return result


def available_feature_names(device):
    """List pyatv features currently reported as available, for diagnostics only."""
    result = []
    for feature in FeatureName:
        try:
            if device.features.get_feature(feature).state == FeatureState.Available:
                result.append(feature.name)
        except Exception:
            continue
    return result


def audio_snapshot(device):
    """Optional group metadata must not turn an established connection into failure."""
    available = lambda name: device.features.get_feature(name).state == FeatureState.Available
    volume = None
    if available(FeatureName.Volume):
        try:
            volume = float(device.audio.volume)
        except NotSupportedError:
            pass
    outputs = []
    if available(FeatureName.OutputDevices):
        try:
            outputs = [{"id": item.identifier, "name": item.name}
                       for item in device.audio.output_devices]
        except NotSupportedError:
            pass
    return {"volume": volume, "outputs": outputs,
            "can_set_volume": available(FeatureName.SetVolume),
            "remote_protocol": getattr(device, "protocol", "unavailable")}


def connection_protocol(config):
    """Never use an all-protocol connection: RAOP can only update local stream gain."""
    companion = config.get_service(Protocol.Companion)
    if companion and companion.credentials:
        return Protocol.Companion
    # AirPlay may supply remote MRP control; if not, report unavailable, never RAOP.
    return Protocol.AirPlay


async def set_verified_volume(device, value, timeout=8):
    before = audio_snapshot(device)
    if not before["can_set_volume"]:
        raise RuntimeError("当前连接不支持音量写入")
    await asyncio.wait_for(device.audio.set_volume(value), timeout)
    # Only remote-control protocols are connected. Never substitute the requested value.
    for _ in range(10):
        actual = audio_snapshot(device)
        if actual["volume"] is not None and abs(actual["volume"] - value) <= 1:
            return actual
        await asyncio.sleep(0.1)
    raise RuntimeError("设备未确认目标音量，已保留实际回读")


class PairingSession:
    """PIN waiting never consumes the IPC reader; cancellation remains available."""
    def __init__(self, factory, save, event, pin_timeout=60):
        self.factory, self.save, self.event = factory, save, event
        self.pin_timeout = pin_timeout
        self.handler = None
        self.token = None
        self.identifier = None
        self.expiry = None

    async def cancel(self):
        if self.expiry:
            self.expiry.cancel()
            self.expiry = None
        handler, self.handler = self.handler, None
        self.token = self.identifier = None
        if handler:
            await asyncio.wait_for(handler.close(), 5)

    async def begin(self, config, identifier, protocol):
        await self.cancel()
        if config.get_service(protocol) is None:
            raise RuntimeError("设备未提供所选配对协议")
        try:
            self.handler = await asyncio.wait_for(self.factory(config, protocol), 5)
            self.identifier = identifier
            self.token = uuid.uuid4().hex
            await asyncio.wait_for(self.handler.begin(), 8)
            if not self.handler.device_provides_pin:
                raise RuntimeError("设备没有提供屏幕验证码配对")
            token = self.token
            self.expiry = asyncio.get_running_loop().call_later(
                self.pin_timeout, lambda: asyncio.create_task(self._expire(token)))
            return token
        except BaseException:
            await self.cancel()
            raise

    async def _expire(self, token):
        if token != self.token:
            return
        try:
            await self.cancel()
        finally:
            self.event({"event": "pair_expired", "token": token})

    async def finish(self, identifier, token, pin):
        if not self.handler or token != self.token or identifier != self.identifier:
            raise RuntimeError("配对会话已失效，请重新配对")
        if not pin.isdigit() or len(pin) != 4:
            raise RuntimeError("请输入四位验证码")
        self.expiry.cancel()
        self.expiry = None
        try:
            self.handler.pin(pin)
            await asyncio.wait_for(self.handler.finish(), 10)
            if not self.handler.has_paired:
                raise RuntimeError("设备未确认配对")
            await self.save()
        finally:
            await self.cancel()
