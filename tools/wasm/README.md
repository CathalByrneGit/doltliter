# Running doltliter in the browser: a shinylive spike

Exploratory notes on serving `doltliter` through
[shinylive](https://posit-dev.github.io/r-shinylive/), which runs Shiny apps
entirely in the browser on [webR](https://docs.r-wasm.org/webr/latest/).

Nothing here is wired into the package build. `tools/wasm/build-probe.sh`
reproduces the whole experiment from a clean checkout.

## Why this looked unlikely

shinylive has one hard constraint, and `doltliter` appears to sit on the wrong
side of it. From the r-shinylive documentation, quoting webR's:

> It is not possible to install packages from source in webR. This is not
> likely to change in the near future, as such a process would require an
> entire C and Fortran compiler toolchain to run inside the browser.

Packages must arrive as pre-built WebAssembly binaries from
<https://repo.r-wasm.org>. `doltliter` is not on CRAN, so it is not in that
repository, and it links a 19 MB C library that has never been near
Emscripten. The obvious guess is that this is a non-starter.

That guess is wrong, and the interesting part is *why*.

## What was actually tested

**1. The amalgamation compiles to wasm, unmodified.**

```
emcc -c src/doltlite/doltlite.c -O1 \
  -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION \
  -DSQLITE_MAX_MMAP_SIZE=0 -DSQLITE_DISABLE_LFS
```

Zero errors, zero warnings, 37 seconds, a 4.7 MB object. No patches.

This is less surprising once you look at the file. The amalgamation is
**19 MB of plain C** — no C++ anywhere, despite the package's own binding
layer being C++ — and every feature Emscripten lacks is behind one of
SQLite's standard compile-time switches. Threads, `mmap` and `fcntl` locking
all appear in the source, but only inside the usual `SQLITE_OS_UNIX` /
`SQLITE_THREADSAFE` guards. The three `-D` flags above are the same ones the
official `sqlite3.wasm` build uses. DoltLite inherits SQLite's OS abstraction
wholesale, and that abstraction is exactly what makes it portable here.

**2. The prolly store works at runtime, on a real file.**

Compiling proves nothing on its own — the content-addressed chunk store is
DoltLite's own code, not SQLite's, and it is the part with no upstream wasm
track record. So `probe.c` runs a full version-control round trip against a
**file-backed** database (`:memory:` would not do: DoltLite serves anonymous
databases with the `orig` B-tree engine, where version control does not
exist):

```
ok   engine                 prolly
ok   commit                 1f2334d11ebca1fb9026c864757cf62c9589e9dc
ok   log count              2
ok   branch / checkout      0
ok   commit 2               965b0d38da9958b8a42036a1beda4c47cfb1cf03
ok   diff rows              2
ok   row diff               modified
ok   active branch          experiment
ok   hashof db              0a4c65c40fda841e849717f343a95dd0c1c7773a
```

Commits, branching, checkout, row-level diff and content hashing all behave
under WebAssembly. The engine really is `prolly`, not a silent fallback.

**3. One trap, and it is not DoltLite's.**

The first run crashed with `memory access out of bounds` inside
`sqlite3_close()`, after every assertion had already passed. That is
Emscripten's 64 KB default stack, not a bug: 128 KB is enough, and **webR
links with `STACK_SIZE=1MB`**, so it does not arise there at all. Worth
recording only because a bare `emcc` build hits it immediately and it looks
alarming — a segfault-shaped trap on shutdown, long after the interesting
work succeeded.

## What is left

The native library was the risk. What remains is mechanical, but not nothing:

- **Cross-compile the R package.** [`rwasm`](https://r-wasm.github.io/rwasm/)
  builds R packages for wasm and can take a local source directory, so
  `doltliter` needs no CRAN presence. It runs in a container carrying webR's
  toolchain and its cross-compiled R (currently **R 4.6.0**), which is why
  this step was not run here — the session has a `docker` CLI but no daemon.
- **`configure` already handles it.** The `vendor` strategy compiles the
  amalgamation from source with no network access, which is what a
  cross-compile needs, and the runtime engine probe is already guarded:
  it emits `warning: could not run the engine check (cross-compiling?)`
  rather than failing when the probe cannot be executed. No changes required
  — which is worth knowing, because that guard was written for CRAN, not
  for this.
- **Host a repository.** webR installs from a CRAN-shaped repository of wasm
  binaries. `rwasm` builds one, and it is static files, so the existing
  `gh-pages` branch could carry it alongside the pkgdown site.
- **Decide about size.** The wasm object is 4.7 MB before the rest of R;
  every visitor downloads it. Fine for a demo page, worth measuring before
  putting it on the front page.

## What it would be good for

Two different things, worth keeping apart:

- **Live vignettes.** The pkgdown articles currently show pasted output. The
  same examples embedded as shinylive apps would let a reader branch, commit
  and diff in the page. This is the strongest fit: the examples are small,
  self-contained, and already written.
- **A standalone demo app.** A version-control playground — branch a table,
  edit it, see the diff. More work, and it needs a story for persistence:
  webR's filesystem is per-session, so a database vanishes on reload unless
  it is pushed into IndexedDB.

The ephemerality cuts both ways. Nothing to install and nothing to clean up
is exactly right for a demo, and useless for anything you want to keep.

## Reproducing

```sh
sh tools/wasm/build-probe.sh
```

Installs Emscripten if absent, stages the amalgamation, compiles, links and
runs the probe. Takes a few minutes on a cold start, mostly the toolchain
download.
