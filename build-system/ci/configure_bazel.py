#!/usr/bin/env python3
"""Configure only the canonical CI checkout, never developer Bazel defaults."""

import argparse
import os
from pathlib import Path
import subprocess


BEGIN = "# BEGIN SHADOW CI RESOURCES"
END = "# END SHADOW CI RESOURCES"
MIB = 1024 * 1024


def resource_options(memory_mb: int, cpu_count: int) -> tuple[int, int, int]:
    if memory_mb < 4096 or cpu_count < 1:
        raise ValueError("Shadow CI requires at least 4 GiB RAM and one CPU")
    # A maximum, not preallocated memory. Reserve room for macOS and swiftc.
    heap_mb = min(4096, max(1536, memory_mb // 3)) // 256 * 256
    action_memory_mb = memory_mb - heap_mb - 1024
    return heap_mb, action_memory_mb, min(2, cpu_count)


def configured_rc(original: str, memory_mb: int, cpu_count: int) -> str:
    heap_mb, action_memory_mb, jobs = resource_options(memory_mb, cpu_count)
    if BEGIN in original or END in original:
        if original.count(BEGIN) != 1 or original.count(END) != 1:
            raise ValueError("Malformed Shadow CI resource block")
        before, block = original.split(BEGIN, 1)
        _, separator, after = block.partition(END)
        if not separator:
            raise ValueError("Malformed Shadow CI resource block")
        original = before + after
    # Same scope as the repository's SwiftCompile=worker setting. Appending a
    # generic build option would lose to the auto-applied build:macos scope.
    # Standalone execution avoids buffering Swift diagnostics as a JSON worker
    # response inside the Bazel JVM (the JsonWorkerProtocol heap OOM in CI #75).
    return original.rstrip() + "\n\n" + "\n".join([
        BEGIN,
        f"startup --host_jvm_args=-Xmx{heap_mb}m",
        "build:macos --strategy=SwiftCompile=standalone",
        f"build:macos --jobs={jobs}",
        # This is a scheduling budget, not an OS limit on a single compiler.
        f"build:macos --local_resources=memory={action_memory_mb}",
        END,
        "",
    ])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, required=True)
    args = parser.parse_args()
    rc_path = args.workspace / ".bazelrc"
    memory_mb = int(subprocess.check_output(
        ["sysctl", "-n", "hw.memsize"], text=True
    ).strip()) // MIB
    cpu_count = os.cpu_count() or 1
    original = rc_path.read_text(encoding="utf-8")
    configured = configured_rc(original, memory_mb, cpu_count)
    rc_path.write_text(configured, encoding="utf-8")
    heap_mb, action_memory_mb, jobs = resource_options(memory_mb, cpu_count)
    print(f"Runner: {memory_mb} MiB RAM, {cpu_count} CPUs")
    print(f"Bazel: heap <= {heap_mb} MiB, jobs={jobs}, "
          f"action scheduling budget={action_memory_mb} MiB")
    print("SwiftCompile: standalone (no JSON worker response buffering)")


if __name__ == "__main__":
    main()
