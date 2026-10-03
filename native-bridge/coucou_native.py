#!/usr/bin/env python3
"""Chrome native messaging → Coucou's owner-only Unix socket. No network requests."""
import json
from pathlib import Path
import socket
import struct
import sys
from urllib.parse import urlsplit

MAX_BYTES = 300_000
SPACES = {"chatgptMac": "chatgpt.com", "claudeCobra": "claude.ai", "claudeHL": "claude.ai"}


def read_exact(stream, size):
    data = bytearray()
    while len(data) < size:
        chunk = stream.read(size - len(data))
        if not chunk:
            raise ValueError("Message incomplet")
        data.extend(chunk)
    return bytes(data)


def read_message(stream):
    header = read_exact(stream, 4)
    size = struct.unpack("=I", header)[0]
    if not 0 < size <= MAX_BYTES:
        raise ValueError("Message trop long")
    return json.loads(read_exact(stream, size))


def validate(message):
    if not isinstance(message, dict) or message.get("coucou_kind") != "conversation_response":
        raise ValueError("Événement non autorisé")
    space = message.get("space")
    if not isinstance(space, str) or space not in SPACES:
        raise ValueError("Compte non autorisé")
    for key, limit in (("title", 300), ("message_id", 500), ("text", 200_000), ("conversation_id", 500), ("url", 1000)):
        value = message.get(key)
        size = len(value.encode("utf-8")) if isinstance(value, str) and key == "text" else len(value) if isinstance(value, str) else 0
        if not isinstance(value, str) or not value.strip() or size > limit:
            raise ValueError("Réponse invalide")
    url = urlsplit(message["url"])
    prefix = "/c/" if space == "chatgptMac" else "/chat/"
    if (url.scheme != "https" or url.hostname != SPACES[space] or url.username or url.password
            or url.port not in (None, 443) or not url.path.startswith(prefix)
            or len(url.path) <= len(prefix) or url.path != message["conversation_id"]
            or url.query or url.fragment):
        raise ValueError("Lien de conversation invalide")
    return {key: message[key] for key in ("coucou_kind", "space", "title", "message_id", "text", "conversation_id", "url")}


def relay(message, socket_path=None):
    message = validate(message)
    path = socket_path or str(Path.home() / "Library/Application Support/NotchBuddy/nb.sock")
    encoded = json.dumps(message, ensure_ascii=False).encode("utf-8") + b"\n"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(8)
        client.connect(path)
        client.sendall(encoded)
        response = bytearray()
        while b"\n" not in response and len(response) < 1024:
            chunk = client.recv(1024)
            if not chunk:
                break
            response.extend(chunk)
        if json.loads(response).get("ok") is not True:
            raise ValueError("Coucou n’a pas pu sauvegarder cette réponse")
    return {"ok": True}


def write_message(stream, message):
    body = json.dumps(message, ensure_ascii=False).encode("utf-8")
    stream.write(struct.pack("=I", len(body)) + body)
    stream.flush()


def main():
    try:
        config_path = Path(__file__).with_name("config.json")
        origin = json.loads(config_path.read_text())["origin"]
        if len(sys.argv) < 2 or sys.argv[1] != origin:
            raise ValueError("Extension non autorisée")
        result = relay(read_message(sys.stdin.buffer))
    except Exception:
        # Do not log response text, account identifiers or file paths.
        result = {"ok": False, "error": "Connexion impossible. Lance Coucou et vérifie l’installation du connecteur."}
    write_message(sys.stdout.buffer, result)


if __name__ == "__main__":
    main()
