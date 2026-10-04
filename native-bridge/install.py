#!/usr/bin/env python3
"""Run by the user after loading the unpacked extension; registers that exact ID."""
import argparse
import json
from pathlib import Path
import re
import shlex
import shutil
import sys

parser = argparse.ArgumentParser(description="Installer le relais local de l’extension Coucou")
parser.add_argument("extension_id", help="Identifiant affiché dans chrome://extensions")
args = parser.parse_args()
if sys.platform != "darwin" or not re.fullmatch(r"[a-p]{32}", args.extension_id):
    parser.error("macOS et un identifiant Chrome de 32 lettres a–p sont nécessaires")
bridge = Path.home() / "Library/Application Support/NotchBuddy/browser-bridge"
bridge.mkdir(parents=True, exist_ok=True, mode=0o700)
shutil.copyfile(Path(__file__).with_name("coucou_native.py"), bridge / "coucou_native.py")
(bridge / "coucou_native.py").chmod(0o600)
origin = f"chrome-extension://{args.extension_id}/"
(bridge / "config.json").write_text(json.dumps({"origin": origin}))
(bridge / "config.json").chmod(0o600)
launcher = bridge / "launch"
launcher.write_text("#!/bin/sh\nexec " + shlex.quote(sys.executable) + " " + shlex.quote(str(bridge / "coucou_native.py")) + ' "$@"\n')
launcher.chmod(0o700)
manifest_dir = Path.home() / "Library/Application Support/Google/Chrome/NativeMessagingHosts"
manifest_dir.mkdir(parents=True, exist_ok=True)
manifest = {"name": "fr.coucou.conversations", "description": "Réponses locales Coucou", "path": str(launcher), "type": "stdio", "allowed_origins": [origin]}
path = manifest_dir / "fr.coucou.conversations.json"
path.write_text(json.dumps(manifest, indent=2))
path.chmod(0o600)
print("Relais installé. Lance Coucou, puis choisis une conversation à suivre dans l’extension.")
