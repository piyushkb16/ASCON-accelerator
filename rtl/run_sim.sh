#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

mkdir -p build

iverilog -g2012 -Wall \
  -s tb_ascon \
  -o build/tb_ascon.vvp \
  rtl/ascon_round.sv \
  rtl/ascon_permutation.sv \
  tb/tb_ascon.sv

vvp build/tb_ascon.vvp "$@"