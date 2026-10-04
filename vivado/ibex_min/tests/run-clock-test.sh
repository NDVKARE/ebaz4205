#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
# Keep compiler temporary/output files on Linux storage, avoiding slow DrvFS I/O.
build_dir=${IBEX_TEST_BUILD_DIR:-${TMPDIR:-/tmp}/ebaz4205-ibex-clock-rate}
verilator --binary -j 2 --timing -Wno-fatal --top-module soc_tb \
    --Mdir "$build_dir" -o soc_clock_rate_test \
    ibex_cpu.v rtl/ibex_soc.v rtl/ibex_shared_ram.v tests/bufgce_sim.v tests/soc_tb.sv \
    > simulation_clock_rate_build.log 2>&1
"$build_dir/soc_clock_rate_test"
