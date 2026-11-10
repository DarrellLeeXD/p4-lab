#!/usr/bin/env python3
"""Check the Week 5 Mininet observations before publishing them."""

from pathlib import Path
import re
import sys


evidence = Path(sys.argv[1] if len(sys.argv) > 1 else "assignment/evidence")


def counts(phase):
    output = (evidence / phase).read_text()
    labels = (
        "== switch receive counts before loop packet ==",
        "== switch receive counts after 5 seconds ==",
    )
    pairs = []
    for label in labels:
        assert label in output, f"{phase}: missing {label}"
        section = output.split(label, 1)[1].split("==", 1)[0]
        pairs.append(tuple(int(n) for n in re.findall(r"logs/s[12]\.txt:(\d+)", section)))
        assert len(pairs[-1]) == 2, f"{phase}: missing switch counts after {label}"
    return tuple(end - start for start, end in zip(*pairs))


before = counts("loop-before.txt")
after = counts("loop-after.txt")
mixed = counts("mixed.txt")
assert sum(before) > 100, f"old loop did not keep growing: {before}"
assert sum(after) == 5, f"new loop should have five visits: {after}"
assert sum(mixed) == 9, f"mixed loop should have nine visits: {mixed}"

delivery = (evidence / "delivery.txt").read_text()
assert "Received (tunnelled, dst_id=2, hops=2)" in delivery
assert "Received (tunnelled, dst_id=3, hops=2)" in delivery
assert "2 packets transmitted, 2 received, 0% packet loss" in delivery

mixed_output = (evidence / "mixed.txt").read_text()
assert "Received (tunnelled, dst_id=2, hops=3)" in mixed_output
assert "hdr.myTunnel.hops == 0" in mixed_output

print(f"Evidence verified: old loop {before}; new loop {after}; mixed loop {mixed}")
