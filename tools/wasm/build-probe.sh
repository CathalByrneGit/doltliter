#!/bin/sh
# Reproduce the WebAssembly feasibility spike from a clean checkout.
#
#   sh tools/wasm/build-probe.sh
#
# Installs Emscripten if it is not already on PATH, stages the DoltLite
# amalgamation, compiles it to wasm, and runs tools/wasm/probe.c under Node.
# See tools/wasm/README.md for what the results mean.
#
# This is a spike, not part of the package build. Nothing here is wired into
# configure or R CMD INSTALL.

set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
work=${WASM_SPIKE_DIR:-${TMPDIR:-/tmp}/doltliter-wasm-spike}
mkdir -p "$work"

# DoltLite needs more than Emscripten's 64KB default stack: sqlite3_close() on
# a prolly database overflows it and traps with "memory access out of bounds".
# 128KB is enough; webR itself links with STACK_SIZE=1MB, so this only has to
# be set for a standalone build like this one.
STACK_SIZE=${STACK_SIZE:-4MB}

if ! command -v emcc >/dev/null 2>&1; then
  if [ ! -d "$work/emsdk" ]; then
    echo "==> installing Emscripten into $work/emsdk"
    git clone --depth 1 https://github.com/emscripten-core/emsdk.git "$work/emsdk"
    (cd "$work/emsdk" && ./emsdk install latest && ./emsdk activate latest)
  fi
  # shellcheck disable=SC1091
  . "$work/emsdk/emsdk_env.sh" >/dev/null 2>&1
fi
emcc --version | head -1

if [ ! -f "$root/src/doltlite/doltlite.c" ]; then
  echo "==> staging the DoltLite amalgamation"
  (cd "$root" && Rscript tools/vendor_amalgamation.R)
fi

cd "$work"

# The same defines the official SQLite wasm build uses: no threads, no mmap,
# no loadable extensions. All three are compile-time switches in the
# amalgamation, so nothing has to be patched out by hand.
echo "==> compiling the amalgamation to wasm"
emcc -c "$root/src/doltlite/doltlite.c" -o doltlite.o -O1 \
  -I"$root/src/doltlite" \
  -DSQLITE_THREADSAFE=0 \
  -DSQLITE_OMIT_LOAD_EXTENSION \
  -DSQLITE_MAX_MMAP_SIZE=0 \
  -DSQLITE_DISABLE_LFS

echo "==> linking the probe"
# NODERAWFS gives the probe the real filesystem under Node. A browser build
# would use MEMFS or IDBFS instead; the engine does not care which, since it
# only ever sees Emscripten's POSIX layer.
emcc "$root/tools/wasm/probe.c" doltlite.o -o probe.js -O1 \
  -I"$root/src/doltlite" \
  -sALLOW_MEMORY_GROWTH=1 \
  -sEXIT_RUNTIME=1 \
  -sNODERAWFS=1 \
  -sSTACK_SIZE="$STACK_SIZE"

mkdir -p /work
rm -f /work/spike.db*
echo "==> running under Node"
node probe.js
