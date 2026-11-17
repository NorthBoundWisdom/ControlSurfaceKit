#!/usr/bin/env python3
"""A short frame must receive a reply while the peer deliberately keeps stdin open."""
import argparse
import json
from pathlib import Path
import select
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bridge", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    args.evidence.mkdir(parents=True, exist_ok=True)
    child = subprocess.Popen([str(args.bridge.resolve())], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    replies = []
    started = time.monotonic()
    try:
        for index, (op, arguments) in enumerate([
            ("create", {"definitions": [dict(id="p1", minimum=0, maximum=127, initial=0)]}),
            ("destroy", {}), ("finish", {})
        ], 1):
            request = dict(version=1, id=index, op=op, instance="interactive", at=index / 10, arguments=arguments)
            child.stdin.write(json.dumps(request, allow_nan=False).encode() + b"\n")
            child.stdin.flush()
            # No EOF or padding is sent to make a fill-size reader complete.
            assert select.select([child.stdout], [], [], 1)[0], "short_frame_blocked_waiting_for_fill_or_EOF"
            raw = child.stdout.readline(65538)
            assert len(raw) <= 65537 and raw.endswith(b"\n")
            response = json.loads(raw)
            replies.append(response)
            assert response["id"] == index and response["ok"] is True
        child.stdin.close()
        assert child.wait(timeout=2) == 0
        (args.evidence / "summary.json").write_text(json.dumps(dict(interactive_framing="pass", frames=3,
            elapsed_seconds=time.monotonic() - started, replies=replies), indent=2) + "\n")
        print("INTERACTIVE_FRAMING_PASS frames=3 stdin_open_at_every_response=true")
    finally:
        if child.poll() is None:
            child.terminate(); child.wait(timeout=2)
        (args.evidence / "stderr.log").write_bytes(child.stderr.read(65537))
        (args.evidence / "replies.json").write_text(json.dumps(replies, indent=2) + "\n")


if __name__ == "__main__":
    main()
