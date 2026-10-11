#!/usr/bin/env python3
"""Python3.9-compatible launcher for the pinned publication replay runtime."""
import hashlib
import json
import os
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
config_path = root / "evidence/maker-publication-extraction/verification-config.json"
if len(sys.argv) != 1:
    raise ValueError("This local CI launcher takes no arguments")
if hashlib.sha256(config_path.read_bytes()).hexdigest() != "597b076d00a577d8c6b4545851130a6f1260bce37d49eb70941775ed3031f1d2":
    raise ValueError("Reviewed publication config changed")
config = json.loads(config_path.read_text())
runtime = config["python_tool"]
binary = Path(runtime["invoked_python"])
if binary.resolve() != Path(runtime["resolved_binary"]):
    raise ValueError("Pinned Python locator changed")
if hashlib.sha256(binary.read_bytes()).hexdigest() != runtime["binary_sha256"]:
    raise ValueError("Pinned Python binary changed")
os.execv(str(binary), [str(binary), str(root / "scripts/verify_maker_publication.py"), "--actual", "--config", str(config_path)])
