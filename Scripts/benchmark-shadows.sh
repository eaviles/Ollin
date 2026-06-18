#!/bin/bash
#
# Benchmark Ollin's soft-shadow ray cost on THIS GPU and recommend per-tier ray counts.
#
# Run it on each machine you care about (Intel Mac, M-series, …) to tune the values in
# MetalRenderer.resolveShadowSamples — it measures the true per-frame GPU time across a
# sweep of ray counts (vsync-independent) and prints the count that holds 60/120 fps plus a
# suggested .performance/.default/.detail mapping. On a GPU without render-stage ray tracing
# (e.g. an Intel Mac) it reports the cube-fallback cost instead (the tiers don't apply there).
#
# Usage:
#   Scripts/benchmark-shadows.sh           # ~Retina full-window proxy (2160x2160)
#   Scripts/benchmark-shadows.sh 1600      # benchmark at a specific square resolution
#
set -euo pipefail
cd "$(dirname "$0")/.."
export OLLIN_BENCH=1
[ "${1:-}" != "" ] && export OLLIN_BENCH_RES="$1"

# Run only the gated benchmark test; surface just its report block.
swift test --filter "ShadowBenchmarkTests/shadowQualityBenchmark" 2>&1 \
  | awk '/=== Ollin shadow benchmark ===/,/=== end ===/'
