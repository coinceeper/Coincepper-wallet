#!/usr/bin/env python3
"""
خروجی: TSP1 | nonce(12) | aes-256-gcm(plaintext)  — همان KDF/dart [lib/tsp_agent_config_cipher.dart]
استفاده:  python3 scripts/encrypt_tsp_agent_config.py assets/tsp_agent/default_agent.yml assets/tsp_agent/tsp1.enc
نیاز:     pip install cryptography
"""
import hashlib
import os
import sys
from pathlib import Path

KDF = os.environ.get(
    "TSP_KDF_SECRET", "tsp-asset-tsp1-kdf-v1-rotated-by-build"
).encode("utf-8")

MAGIC = b"TSP1"


def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: ... input.yml output.tsp1.enc", file=sys.stderr)
        return 1
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    plain = Path(sys.argv[1]).read_bytes()
    key = hashlib.sha256(KDF).digest()
    aes = AESGCM(key)
    nonce = os.urandom(12)
    ct = aes.encrypt(nonce, plain, None)
    out = MAGIC + nonce + ct
    Path(sys.argv[2]).write_bytes(out)
    print(f"Wrote {len(out)} bytes (TSP1) -> {sys.argv[2]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
