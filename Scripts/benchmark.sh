#!/bin/bash
#
# Run Ollin's GPU micro-benchmarks on THIS GPU and recommend per-tier quality values.
#
# Each one renders a representative scene across a sweep of its quality knob, measures the
# true per-frame GPU time (vsync-independent, from command-buffer timestamps), and prints
# the count that holds 60/120 fps plus a suggested .performance/.default/.detail mapping.
# Run it on each machine you care about (Intel Mac, M-series, …) to tune the per-GPU values
# in MetalRenderer.resolveShadowSamples / resolveDofTaps.
#
#   shadows — soft-shadow ray count (RT GPUs only; cube-fallback cost otherwise),
#             measured at the live window drawable resolution.
#   dof     — depth-of-field bokeh tap count, measured at the `.defocus` layer's canvas size.
#
# Usage:
#   Scripts/benchmark.sh                 # all benchmarks at their default resolutions
#   Scripts/benchmark.sh dof             # just depth of field
#   Scripts/benchmark.sh shadows 1600    # just shadows at a specific square resolution
#   Scripts/benchmark.sh all 1600        # all at a resolution
#
set -euo pipefail
cd "$(dirname "$0")/.."
export OLLIN_BENCH=1

case "${1:-all}" in
  shadows) filter="ShadowBenchmarkTests" ;;
  dof)     filter="DofBenchmarkTests" ;;
  all)     filter="BenchmarkTests" ;;   # substring matches both suites
  *) echo "usage: $0 [all|shadows|dof] [resolution]" >&2; exit 1 ;;
esac
[ "${2:-}" != "" ] && export OLLIN_BENCH_RES="$2"

# Run only the gated benchmark test(s); surface just their report blocks.
swift test --filter "$filter" 2>&1 | awk '/=== Ollin .* benchmark ===/,/=== end ===/'
