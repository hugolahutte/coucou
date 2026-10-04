import importlib.util
import io
import json
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("bridge", Path(__file__).resolve().parents[1] / "native-bridge/coucou_native.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

class BridgeTests(unittest.TestCase):
    def event(self):
        return {"coucou_kind": "conversation_response", "space": "claudeHL", "title": "HL", "conversation_id": "/chat/abc", "url": "https://claude.ai/chat/abc", "message_id": "1", "text": "Réponse"}
    def test_roundtrip_unicode(self):
        stream = io.BytesIO()
        bridge.write_message(stream, self.event())
        stream.seek(0)
        self.assertEqual(bridge.read_message(stream), self.event())
    def test_short_reads(self):
        class ShortReader(io.BytesIO):
            def read(self, count=-1): return super().read(min(2, count))
        body = json.dumps(self.event()).encode()
        self.assertEqual(bridge.read_message(ShortReader(struct.pack("=I", len(body)) + body)), self.event())
    def test_rejects_truncated_or_oversized(self):
        for data in (b"x", struct.pack("=I", 300001), struct.pack("=I", 10) + b"{}"):
            with self.assertRaises(ValueError): bridge.read_message(io.BytesIO(data))
    def test_limits_and_provider_identity(self):
        for changes in ({"space": "chatgptMac"}, {"text": "é" * 100001}, {"space": []}, {"url": "https://claude.ai.evil.test/chat/abc"}, {"url": "https://user:pass@claude.ai/chat/abc"}, {"url": "https://claude.ai/chat/abc?token=secret"}, {"coucou_kind": "PermissionRequest"}):
            with self.assertRaises(ValueError): bridge.validate(self.event() | changes)
    def test_cowork_session_paths(self):
        for path in ("/cowork/cse_01abc-DEF", "/cowork/projects", "/cowork/cse_", "/cowork/cse_abc/other", "/epitaxy/local_abc"):
            event = self.event() | {"url": "https://claude.ai" + path, "conversation_id": path}
            if path == "/cowork/cse_01abc-DEF":
                self.assertEqual(bridge.validate(event), event)
            else:
                with self.assertRaises(ValueError): bridge.validate(event)
    def test_ignores_extra_fields(self):
        self.assertEqual(bridge.validate(self.event() | {"command": "never execute"}), self.event())

if __name__ == '__main__': unittest.main()
