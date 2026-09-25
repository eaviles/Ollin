#!/usr/bin/env python3
"""Prints what the system's crash reports say about a test process that died.

    Scripts/crash-report.py <marker file> [process name pattern]

Every crash report (`.ips`) written after the marker file was made, for a
process whose name matches the pattern (the test helpers by default), is read
and summed up: the exception and the signal, what the faulting address was
(a stack's guard page reads as one), and the faulting thread's frames with the
image each sits in, a recursion folded to the frames it repeats. An uncaught
C++ or Objective-C exception keeps its thrower on that thread, under the abort.

A test process that dies takes its buffered output with it, so the run's log
says only that it exited on a signal. On a machine nobody can attach to, the
report the system writes out of process is the one witness left. The system
takes a few seconds to write it, so this waits up to half a minute for one.
"""

import json
import os
import re
import sys
import time

FOLDERS = [os.path.expanduser("~/Library/Logs/DiagnosticReports"), "/Library/Logs/DiagnosticReports"]
FRAMES = 80


def reports(marker, pattern):
    since = os.path.getmtime(marker)
    found = []
    for folder in FOLDERS:
        try:
            names = os.listdir(folder)
        except OSError:
            continue
        for name in names:
            path = os.path.join(folder, name)
            if name.endswith(".ips") and re.search(pattern, name) and os.path.getmtime(path) >= since:
                found.append(path)
    return sorted(found, key=os.path.getmtime)


def frame_text(frame, images):
    index = frame.get("imageIndex")
    image = images[index].get("name", "?") if index is not None and index < len(images) else "?"
    symbol = frame.get("symbol")
    if symbol:
        where = f"{symbol} + {frame.get('symbolLocation', 0)}"
    else:
        where = f"0x{frame.get('imageOffset', 0):x}"
    source = frame.get("sourceFile")
    if source:
        where += f"  ({source}:{frame.get('sourceLine', '?')})"
    return f"{image:<28} {where}"


def summarize(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    header, _, body = text.partition("\n")
    try:
        head = json.loads(header)
        report = json.loads(body)
    except json.JSONDecodeError:
        print(f"crash-report: {path} is not a report this reads; its first lines:")
        print("\n".join(text.splitlines()[:40]))
        return
    images = report.get("usedImages", [])
    exception = report.get("exception", {})
    print(f"crash-report: ====== {head.get('name', '?')} (pid {report.get('pid', '?')}), {head.get('timestamp', '?')} ======")
    print(f"crash-report: {exception.get('type', '?')} ({exception.get('signal', '?')}) {exception.get('subtype', '')}")
    if exception.get("message"):
        print(f"crash-report: {exception['message']}")
    termination = report.get("termination", {})
    if termination.get("indicator"):
        print(f"crash-report: {termination['indicator']}")
    region = report.get("vmRegionInfo")
    if region:
        print("crash-report: the address sits in:")
        for line in region.splitlines()[:6]:
            print(f"    {line}")
    for key, lines in (report.get("asi") or {}).items():
        for line in lines if isinstance(lines, list) else [lines]:
            print(f"crash-report: {key}: {line}")
    threads = report.get("threads", [])
    faulting = report.get("faultingThread")
    if faulting is None or faulting >= len(threads):
        faulting = next((i for i, thread in enumerate(threads) if thread.get("triggered")), None)
    if faulting is None:
        print("crash-report: no faulting thread in the report")
        return
    thread = threads[faulting]
    frames = thread.get("frames", [])
    label = ", ".join(str(thread[key]) for key in ("name", "queue") if thread.get(key))
    depth = thread.get("originalLength", len(frames))
    print(f"crash-report: thread {faulting}{' (' + label + ')' if label else ''}, {depth} frames deep:")
    for recursion in thread.get("recursionInfoArray", []):
        print(f"crash-report: a recursion, folded by the system: {json.dumps(recursion)[:400]}")
    shown = frames[:FRAMES]
    for number, frame in enumerate(shown):
        print(f"  {number:>3} {frame_text(frame, images)}")
    if len(frames) > FRAMES:
        print(f"  ... {len(frames) - FRAMES} more, the last of them:")
        for number, frame in enumerate(frames[-12:], start=len(frames) - 12):
            print(f"  {number:>3} {frame_text(frame, images)}")
    backtrace = report.get("lastExceptionBacktrace")
    if backtrace:
        print("crash-report: where the uncaught exception was thrown:")
        for number, frame in enumerate(backtrace[:FRAMES]):
            print(f"  {number:>3} {frame_text(frame, images)}")


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip())
        return 2
    marker = sys.argv[1]
    pattern = sys.argv[2] if len(sys.argv) > 2 else r"swiftpm-testing-helper|xctest|PackageTests"
    found = []
    deadline = time.time() + 30
    while True:
        found = reports(marker, pattern)
        if found or time.time() >= deadline:
            break
        time.sleep(3)
    if not found:
        print("crash-report: the system wrote no crash report for a test process during this run")
        return 0
    for path in found:
        summarize(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
