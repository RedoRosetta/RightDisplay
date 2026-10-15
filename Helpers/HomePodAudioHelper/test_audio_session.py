# Copyright © 2026 RedoRosetta
# First-party portions only; Licensed under RNSL 1.0 for first-party portions; see LICENSE_SCOPE.md.
"""Offline tests: no network, real devices, credentials, or volume writes."""
import asyncio
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock
from unittest.mock import patch, Mock
import json

from pyatv.const import FeatureName, FeatureState, Protocol
from pyatv.exceptions import NotSupportedError
from audio_session import PairingSession, audio_snapshot, connection_protocol, remote_audio, set_verified_volume


class AudioTests(unittest.TestCase):
    def test_optional_outputs_do_not_break_volume(self):
        class Audio:
            volume = 35
            @property
            def output_devices(self):
                raise NotSupportedError()
        device = SimpleNamespace(audio=Audio(), features=SimpleNamespace(
            get_feature=lambda _: SimpleNamespace(state=FeatureState.Available)))
        self.assertEqual(audio_snapshot(device), {
            "volume": 35.0, "outputs": [], "can_set_volume": True,
            "remote_protocol": "unavailable"})

    def test_unavailable_properties_are_not_read(self):
        device = SimpleNamespace(audio=object(), features=SimpleNamespace(
            get_feature=lambda _: SimpleNamespace(state=FeatureState.Unsupported)))
        self.assertEqual(audio_snapshot(device), {
            "volume": None, "outputs": [], "can_set_volume": False,
            "remote_protocol": "unavailable"})

    def test_protocol_selection_uses_credentials_not_os_version(self):
        service = {Protocol.Companion: SimpleNamespace(credentials="test-only")}
        config = SimpleNamespace(get_service=service.get)
        self.assertEqual(connection_protocol(config), Protocol.Companion)
        service[Protocol.AirPlay] = SimpleNamespace(credentials="test-only")
        self.assertEqual(connection_protocol(config), Protocol.Companion)
        service.clear()
        self.assertEqual(connection_protocol(config), Protocol.AirPlay)


class PairingTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.handler = SimpleNamespace(begin=AsyncMock(), close=AsyncMock(), finish=AsyncMock(),
                                       pin=lambda _: None, device_provides_pin=True, has_paired=True)
        self.save = AsyncMock()
        self.events = []
        self.session = PairingSession(AsyncMock(return_value=self.handler),
                                      self.save, self.events.append)
        self.config = SimpleNamespace(get_service=lambda _: object())

    async def asyncTearDown(self):
        await self.session.cancel()

    async def test_begin_does_not_wait_for_pin_and_cancel_does_not_save(self):
        token = await self.session.begin(self.config, "target", Protocol.AirPlay)
        self.assertTrue(token)
        await self.session.cancel()
        self.save.assert_not_awaited()

        self.handler.close.assert_awaited_once()

    async def test_target_and_token_are_checked(self):
        token = await self.session.begin(self.config, "target", Protocol.Companion)
        for identifier, candidate_token in [("other", token), ("target", "stale")]:
            with self.assertRaises(RuntimeError):
                await self.session.finish(identifier, candidate_token, "1234")
        self.handler.finish.assert_not_awaited()
        self.save.assert_not_awaited()

    async def test_success_saves_only_after_confirmation(self):
        token = await self.session.begin(self.config, "target", Protocol.AirPlay)
        await self.session.finish("target", token, "1234")
        self.handler.finish.assert_awaited_once()
        self.save.assert_awaited_once()
        self.assertIsNone(self.session.handler)

    async def test_failure_does_not_save(self):
        self.handler.has_paired = False
        token = await self.session.begin(self.config, "target", Protocol.AirPlay)
        with self.assertRaises(RuntimeError):
            await self.session.finish("target", token, "1234")
        self.save.assert_not_awaited()
        self.assertIsNone(self.session.handler)

    async def test_expiry_releases_session(self):
        token = await self.session.begin(self.config, "target", Protocol.AirPlay)
        await self.session._expire(token)
        self.assertEqual(self.events, [{"event": "pair_expired", "token": token}])
        self.save.assert_not_awaited()
        self.assertIsNone(self.session.handler)

    async def test_begin_error_releases_session(self):
        self.handler.begin.side_effect = TimeoutError()
        with self.assertRaises(TimeoutError):
            await self.session.begin(self.config, "target", Protocol.AirPlay)
        self.handler.close.assert_awaited_once()
        self.save.assert_not_awaited()


class RuntimeTests(unittest.IsolatedAsyncioTestCase):
    async def check_pairing_preserves_connection(self, begin_error=None):
        import homepod_audio_helper as helper
        config = SimpleNamespace(get_service=lambda _: SimpleNamespace(credentials="fake-only"))
        discovery = SimpleNamespace(start=Mock(), close=Mock(), scan=AsyncMock(return_value=[config]), context="offline")
        handler = SimpleNamespace(begin=AsyncMock(side_effect=begin_error), close=AsyncMock(),
                                  device_provides_pin=True)
        device = SimpleNamespace(close=Mock(return_value=[]), audio=SimpleNamespace(volume=33),
                                 features=SimpleNamespace(get_feature=lambda name: SimpleNamespace(
                                     state=FeatureState.Available if name in [FeatureName.Volume, FeatureName.SetVolume]
                                     else FeatureState.Unsupported)))
        connect = AsyncMock(return_value=device)
        device.audio.get = lambda p: device.audio if p == Protocol.Companion else None
        device.features.get = lambda p: device.features if p == Protocol.Companion else None
        replies = []
        def record(payload):
            replies.append(payload)
            if payload.get("request") != "5":
                device.close.assert_not_called()
        commands = [dict(request="1", action="status", identifier="target"),
                    dict(request="2", action="pair_begin", identifier="target", protocol="airplay"),
                    dict(request="3", action="pair_cancel"),
                    dict(request="4", action="status", identifier="target"),
                    dict(request="5", action="shutdown")]
        with patch.object(helper, "NativeDiscovery", return_value=discovery), \
             patch.object(helper.pyatv, "pair", AsyncMock(return_value=handler)), \
             patch.object(helper.pyatv, "connect", connect), \
             patch.object(helper, "diagnostic"), patch.object(helper, "emit", record), \
             patch.object(helper.sys.stdin, "readline", side_effect=[json.dumps(c) + "\n" for c in commands]):
            storage = SimpleNamespace(save=AsyncMock())
            await helper.serve(SimpleNamespace(timeout=0.01), asyncio.get_running_loop(), storage)
        replies = [reply for reply in replies if "request" in reply]
        self.assertTrue(replies[0]["ok"], replies)
        self.assertEqual(replies[1]["ok"], begin_error is None)
        self.assertTrue(replies[2]["ok"], replies)
        self.assertTrue(replies[3]["ok"], replies)
        self.assertTrue(replies[4]["ok"], replies)
        self.assertEqual(replies[3]["volume"], 33)
        connect.assert_awaited_once()
        storage.save.assert_not_awaited()
        device.close.assert_called_once()  # Shutdown only.

    async def test_pair_failure_preserves_connection(self):
        await self.check_pairing_preserves_connection(OSError(65, "No route to host"))

    async def test_pair_cancel_preserves_connection(self):
        await self.check_pairing_preserves_connection()

    async def test_one_context_pair_cancel_status_shutdown(self):
        import homepod_audio_helper as helper
        config = SimpleNamespace(get_service=lambda _: SimpleNamespace(credentials="fake-only"))
        discovery = SimpleNamespace(start=Mock(), close=Mock(), scan=AsyncMock(return_value=[config]), context="offline")
        handler = SimpleNamespace(begin=AsyncMock(), close=AsyncMock(), device_provides_pin=True)
        device = SimpleNamespace(close=Mock(return_value=[]), audio=SimpleNamespace(volume=30),
                                 features=SimpleNamespace(get_feature=lambda name: SimpleNamespace(
                                     state=FeatureState.Available if name in [FeatureName.Volume, FeatureName.SetVolume]
                                     else FeatureState.Unsupported)))
        device.audio.get = lambda p: device.audio if p == Protocol.Companion else None
        device.features.get = lambda p: device.features if p == Protocol.Companion else None
        replies = []
        commands = [dict(request="1", action="pair_begin", identifier="target", protocol="airplay"),
                    dict(request="2", action="pair_cancel"),
                    dict(request="3", action="status", identifier="target"),
                    dict(request="4", action="shutdown")]
        with patch.object(helper, "NativeDiscovery", return_value=discovery), \
             patch.object(helper.pyatv, "pair", AsyncMock(return_value=handler)), \
             patch.object(helper.pyatv, "connect", AsyncMock(return_value=device)), \
             patch.object(helper, "diagnostic"), patch.object(helper, "emit", replies.append), \
             patch.object(helper.sys.stdin, "readline", side_effect=[json.dumps(c) + "\n" for c in commands]):
            storage = SimpleNamespace(save=AsyncMock())
            await helper.serve(SimpleNamespace(timeout=0.01), asyncio.get_running_loop(), storage)
        replies = [reply for reply in replies if "request" in reply]
        self.assertEqual([r["request"] for r in replies], ["1", "2", "3", "4"])
        self.assertTrue(all(r["ok"] for r in replies), replies)
        self.assertEqual(replies[2]["volume"], 30)
        storage.save.assert_not_awaited()
        discovery.start.assert_called_once()
        discovery.close.assert_called_once()

    async def test_status_rebuilds_only_lost_connection_and_preserves_discovery(self):
        import homepod_audio_helper as helper
        config = SimpleNamespace(get_service=lambda _: SimpleNamespace(credentials="fake-only"))
        discovery = SimpleNamespace(start=Mock(), close=Mock(),
                                    scan=AsyncMock(return_value=[config]), context="offline")
        devices = []
        for value in (30, 31):
            audio = SimpleNamespace(volume=value)
            features = SimpleNamespace(get_feature=lambda name: SimpleNamespace(
                state=FeatureState.Available if name in (FeatureName.Volume, FeatureName.SetVolume)
                else FeatureState.Unsupported))
            audio.get = lambda p, a=audio: a if p == Protocol.Companion else None
            features.get = lambda p, f=features: f if p == Protocol.Companion else None
            device = SimpleNamespace(audio=audio, features=features)
            def close(d=device):
                d.listener.connection_closed()
                return []
            device.close = Mock(side_effect=close)
            devices.append(device)
        replies, events = [], []
        def record(payload):
            if "request" in payload:
                replies.append(payload)
                if payload["request"] == "1":
                    devices[0].listener.connection_lost(RuntimeError("offline disconnect"))
        commands = [dict(request="1", action="status", identifier="target"),
                    dict(request="2", action="status", identifier="target"),
                    dict(request="3", action="shutdown")]
        connect = AsyncMock(side_effect=devices)
        with patch.object(helper, "NativeDiscovery", return_value=discovery), \
             patch.object(helper.pyatv, "connect", connect), \
             patch.object(helper, "diagnostic", side_effect=lambda e, **d: events.append((e, d))), \
             patch.object(helper, "emit", record), \
             patch.object(helper.sys.stdin, "readline", side_effect=[json.dumps(c)+"\n" for c in commands]):
            await helper.serve(SimpleNamespace(timeout=0.01), asyncio.get_running_loop(),
                               SimpleNamespace(save=AsyncMock()))
        self.assertTrue(all(r["ok"] for r in replies))
        self.assertEqual([r["volume"] for r in replies[:2]], [30, 31])
        self.assertEqual(connect.await_count, 2)
        discovery.start.assert_called_once()
        for device in devices:
            device.close.assert_called_once()
        closed = [d for e, d in events if e == "pyatv.connection_closed"]
        self.assertEqual(len(closed), 2)
        self.assertTrue(all(d["expected_close"] for d in closed))

class RemoteControlTests(unittest.IsolatedAsyncioTestCase):
    def test_raop_is_not_remote_output_control(self):
        raop = SimpleNamespace(volume=33, set_volume=AsyncMock())
        device = SimpleNamespace(audio=SimpleNamespace(get=lambda p: raop if p == Protocol.RAOP else None),
                                 features=SimpleNamespace(get=lambda p: object() if p == Protocol.RAOP else None))
        selected = remote_audio(device)
        self.assertEqual(selected.protocol, "unavailable")
        self.assertIsNone(audio_snapshot(selected)["volume"])
        self.assertFalse(audio_snapshot(selected)["can_set_volume"])
        raop.set_volume.assert_not_awaited()

    async def test_write_return_is_not_confirmation(self):
        audio = SimpleNamespace(volume=33, output_devices=[], set_volume=AsyncMock())
        device = SimpleNamespace(audio=audio, features=SimpleNamespace(
            get_feature=lambda _: SimpleNamespace(state=FeatureState.Available)))
        with self.assertRaisesRegex(RuntimeError, "设备未确认"):
            await set_verified_volume(device, 45)
        self.assertEqual(audio.volume, 33)

    async def test_write_uses_actual_not_requested(self):
        audio = SimpleNamespace(volume=33, output_devices=[])
        async def update(value):
            audio.volume = 44.8
        audio.set_volume = update
        device = SimpleNamespace(audio=audio, features=SimpleNamespace(
            get_feature=lambda _: SimpleNamespace(state=FeatureState.Available)))
        result = await set_verified_volume(device, 45)
        self.assertEqual(result["volume"], 44.8)


class IdleObservationTests(unittest.IsolatedAsyncioTestCase):
    def make_device(self):
        audio = SimpleNamespace(volume=30, output_devices=[], set_volume=AsyncMock())
        features = SimpleNamespace(get_feature=lambda name: SimpleNamespace(
            state=FeatureState.Available if name in (FeatureName.Volume, FeatureName.SetVolume)
            else FeatureState.Unsupported))
        audio.get = lambda protocol: audio if protocol == Protocol.MRP else None
        features.get = lambda protocol: features if protocol == Protocol.MRP else None
        device = SimpleNamespace(audio=audio, features=features,
            metadata=SimpleNamespace(playing=AsyncMock(return_value=SimpleNamespace(
                device_state=SimpleNamespace(name="Playing")))))
        return device

    async def test_capability_only_change_is_published_and_recovers_without_volume_change(self):
        import homepod_audio_helper as helper
        device = self.make_device()
        listener = helper.ConnectionListener("target")
        observer = helper.AudioStateObserver(device, "target", "AirPlay", listener)
        with patch.object(helper, "emit") as emit, patch.object(helper, "diagnostic") as diagnostic:
            await observer.sample()
            self.assertTrue(emit.call_args.args[0]["can_set_volume"])
            await observer.sample()
            self.assertEqual(emit.call_count, 1)  # No constant polling log flood.
            feature = device.features.get_feature
            device.features.get_feature = lambda _: SimpleNamespace(state=FeatureState.Unavailable)
            device.metadata.playing.return_value.device_state.name = "Idle"
            await observer.sample()
            state = emit.call_args.args[0]
            self.assertFalse(state["can_set_volume"])
            self.assertIsNone(state["volume"])
            self.assertEqual(observer.last["playback_state"], "Idle")
            device.features.get_feature = feature
            await observer.sample()
            self.assertTrue(emit.call_args.args[0]["can_set_volume"])
            self.assertEqual(emit.call_args.args[0]["volume"], 30)
            self.assertEqual(diagnostic.call_count, 3)
            device.audio.set_volume.assert_not_awaited()

    async def test_loss_retains_explicit_history_when_facade_is_blocked(self):
        import homepod_audio_helper as helper
        device = self.make_device()
        listener = helper.ConnectionListener("target")
        observer = helper.AudioStateObserver(device, "target", "AirPlay", listener)
        listener.state_snapshot = observer.loss_snapshot
        with patch.object(helper, "emit"), patch.object(helper, "diagnostic") as diagnostic:
            await observer.sample()
            with patch.object(helper, "remote_audio", side_effect=RuntimeError("blocked")):
                listener.connection_lost(RuntimeError("lost transport"))
            details = diagnostic.call_args.kwargs
            self.assertTrue(listener.closed)
            self.assertEqual(details["last_connected_state"]["volume"], 30)
            self.assertIn("snapshot_error", details)
            self.assertNotIn("volume", details)  # History is never a current readback.
            self.assertFalse(details["expected_close"])
            self.assertIn("lost transport", details["traceback"])

    async def test_expected_close_and_late_sample_never_publish_live_volume(self):
        import homepod_audio_helper as helper
        device = self.make_device()
        listener = helper.ConnectionListener("target")
        observer = helper.AudioStateObserver(device, "target", "AirPlay", listener)
        async def close_during_read():
            listener.expected_close = True
            listener.connection_closed()
            return SimpleNamespace(device_state=SimpleNamespace(name="Idle"))
        device.metadata.playing.side_effect = close_during_read
        with patch.object(helper, "emit") as emit, patch.object(helper, "diagnostic") as diagnostic:
            await observer.sample()
            emit.assert_not_called()
            self.assertTrue(diagnostic.call_args.kwargs["expected_close"])

    async def test_real_pyatv_mrp_idle_capability_and_device_update_readback(self):
        # Exercise the installed pyatv classes offline. No assumption that this
        # user's Apple TV advertises these capabilities while idle is made here.
        from pyatv.protocols.mrp import MrpAudio, MrpFeatures, protobuf
        protocol = SimpleNamespace(listen_to=Mock(), device_info=SimpleNamespace(
            inner=lambda: SimpleNamespace(clusterID="", deviceUID="offline-target")))
        audio = MrpAudio(protocol, SimpleNamespace(dispatch=Mock()))
        audio._update_volume_controls(SimpleNamespace(volumeControlAvailable=True,
            volumeCapabilities=protobuf.VolumeCapabilities.Absolute))
        psm = SimpleNamespace(playing=SimpleNamespace(playback_state=0))
        features = MrpFeatures(SimpleNamespace(), psm, audio)
        self.assertEqual(features.get_feature(FeatureName.SetVolume).state, FeatureState.Available)
        async def respond_to_write(message):
            asyncio.get_running_loop().call_soon(lambda: asyncio.create_task(
                audio._volume_did_change(SimpleNamespace(inner=lambda: SimpleNamespace(
                    outputDeviceUID="offline-target", volume=0.348)))))
        protocol.send = respond_to_write
        result = await set_verified_volume(SimpleNamespace(audio=audio, features=features,
                                                           protocol="MRP"), 35)
        self.assertEqual(result["volume"], 34.8)
        audio._update_volume_controls(SimpleNamespace(volumeControlAvailable=False,
            volumeCapabilities=protobuf.VolumeCapabilities.Absolute))
        self.assertEqual(features.get_feature(FeatureName.SetVolume).state, FeatureState.Unavailable)
