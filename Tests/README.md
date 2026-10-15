# Safe offline tests

Run from repository root: `python3 Scripts/offline_targeted.py`, then `python3 Scripts/offline_recovery.py`. These nine suites compile actual native/Swift code with fake backends, use no-op evidence sinks and do not install, play audio or operate real devices. Helper build separately runs 23 mocked Python tests.

Other preserved historical runners are not automatically safe entry points: some construct offscreen UI or read host identities. Review them before use. The abandoned Build42 own-component-policy runner is excluded from this Build44 candidate; its expected policy is incompatible with the retained Build41/44 authentication.

安全入口仅为上述两份runner和Helper离线单测；不要全量执行历史脚本。模拟通过不等于真机验收。

Additional safe security regression: `python3 Scripts/test_signing.py` verifies official/default and custom team requirements and rejects an ad-hoc broker with a forged identifier. It invokes no XPC/HAL or devices.
