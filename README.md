# clang-padding-leakage-checker

A Clang-Tidy plugin that detects **padding-byte information leakage** at
explicitly annotated trust boundaries in C/C++. The checker uses AST-level
record layout metadata to identify by-value aggregate transfers that expose
compiler-introduced padding bytes which may be uninitialized.

This is the research prototype accompanying the MSc thesis:

> **Detecting and Explaining Cryptographic Misuse in C/C++ via LLVM/Clang:
> A Taxonomy-Driven Integration into CodeChecker**  
> Chandler Camarena — Eötvös Loránd University, Faculty of Informatics (2026)  
> Supervisor: Zoltán Porkoláb

The thesis PDF is included in this repository as `Camarena_Thesis.pdf`.

---

## Quick Start

```bash
git clone https://github.com/ChandlerCamarena/clang-padding-leakage-checker.git
cd clang-padding-leakage-checker
bash setup.sh
```

That's it. `setup.sh` installs all dependencies, builds the plugin, runs the
synthetic benchmark suite, and reproduces the full thesis evaluation.

See [Manual Setup](#manual-setup) below if you need finer control, want to
run on an unsupported OS, or are integrating the checker into an existing
workflow.

---

## Repository Structure

```
clang-padding-leakage-checker/
├── include/
│   └── trust_boundary.h              # TRUST_BOUNDARY annotation macro
├── src/
│   ├── CMakeLists.txt
│   ├── checks/
│   │   ├── TrustBoundaryPaddingLeakCheck.h
│   │   └── TrustBoundaryPaddingLeakCheck.cpp   # core checker implementation
│   └── module/
│       └── SecurityMiscModule.cpp               # plugin entry point
├── synthetic_benchmarks/
│   ├── trust_boundary/
│   │   └── benchmarks.c              # all 8 validation cases (Appendix A)
│   └── cross_family/
│       └── tb_representation_leak_crypto.c      # cross-family DM+CM example
├── evaluated_libraries/              # annotated versions of the 4 evaluated projects
│   ├── README.md                     # what was annotated and why
│   ├── zlib/
│   ├── libuv/
│   ├── raylib/
│   └── chipmunk2d/
├── scripts/
│   ├── build.sh                      # build the plugin against LLVM 21
│   ├── run_codechecker.sh            # run CodeChecker on a single project
│   ├── collect_metrics.py            # parse event log → thesis Tables 8.2–8.3
│   └── reproduce_all.sh             # clone libraries, apply annotations, run all
├── .clang-tidy
├── .gitignore
├── codechecker.json
├── LICENSE
├── Camarena_Thesis.pdf
└── README.md
```

---

## Implemented Check

| Check name | Taxonomy ref | What it detects |
|---|---|---|
| `security-misc-padding-boundary-leak` | §5.5 / Ch. 6–7 | Record objects transferred by value across `TRUST_BOUNDARY`-annotated functions when the ABI layout contains padding bytes that may be uninitialized |

The checker assigns one of two evidence levels (thesis §5.6):

| Level | Meaning |
|---|---|
| `E3` | Padding present + field-wise-only initialization visible at call site (high confidence) |
| `E2` | Padding present + initialization state not visible under translation-unit scope (bounded confidence) |

---

## Manual Setup

Use this if `setup.sh` doesn't cover your environment, or if you want to
run steps individually.

### Supported platforms

| OS | Status |
|---|---|
| Arch Linux | ✅ Evaluated environment |
| Ubuntu 24.04 | ✅ Best effort |
| macOS | ❌ Not supported |
| Windows | ❌ Not supported |

### Step 1 — Install LLVM 21 and build tools

The thesis evaluation used **LLVM/Clang 21.1.8** and **CodeChecker 6.27.3**.
The plugin must be built against the same LLVM version that `clang-tidy` uses
to load it — mismatched versions will cause the plugin to fail silently or crash.

**Arch Linux**

```bash
sudo pacman -S llvm21 clang21 cmake ninja python git
```

LLVM 21 installs to `/usr/lib/llvm21/bin/`. Your system `clang` may point to
a newer version — that is fine. The build scripts use the full path explicitly.

**Ubuntu 24.04**

```bash
wget https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
sudo ./llvm.sh 21
sudo apt install clang-tidy-21 cmake ninja-build python3 python3-venv git
```

On Ubuntu, binaries install to `/usr/bin/` with a `-21` suffix. Update the
`LLVM21` variable in `scripts/build.sh` and `scripts/reproduce_all.sh` from
`/usr/lib/llvm21` to `/usr/bin` before building.

### Step 2 — Install CodeChecker

CodeChecker must be installed in a Python virtual environment:

```bash
python3 -m venv .codechecker-env
source .codechecker-env/bin/activate
pip install codechecker
CodeChecker --version   # verify
```

> You must activate the venv (`source .codechecker-env/bin/activate`) in any
> new shell session before running `reproduce_all.sh` or `run_codechecker.sh`.

### Step 3 — Build the plugin

```bash
source .codechecker-env/bin/activate
bash scripts/build.sh
```

Output: `build/SecurityMiscPlugin.so`

Verify the plugin loads correctly:

```bash
/usr/lib/llvm21/bin/clang-tidy \
  -load build/SecurityMiscPlugin.so \
  -checks='*' -list-checks 2>/dev/null | grep security-misc
```

Expected output:
```
security-misc-padding-boundary-leak
```

---

## Running the Checker

### On the evaluated libraries (pre-annotated, recommended starting point)

The four libraries from the thesis evaluation are included in
`evaluated_libraries/` with `TRUST_BOUNDARY` annotations already applied.
`reproduce_all.sh` clones each library at the exact thesis version, copies
the annotated files in, builds with Clang 21, runs CodeChecker, and prints
the metrics from Tables 8.2 and 8.3 — no manual annotation needed.

```bash
source .codechecker-env/bin/activate
bash scripts/reproduce_all.sh
```

> **Note on build warnings:** libuv, raylib, and Chipmunk2D have minor
> compatibility issues with Clang 21 in some internal implementation files.
> These produce compile errors in non-annotated files but do not affect the
> annotated boundary functions or the reported metrics. The checker correctly
> analyzes all annotated sites and reproduces the thesis results exactly.

### On a single file

```bash
/usr/lib/llvm21/bin/clang-tidy \
  -load build/SecurityMiscPlugin.so \
  -checks='-*,security-misc-padding-boundary-leak' \
  your_file.c -- -I./include
```

### Via CodeChecker on a project with a compilation database

```bash
source .codechecker-env/bin/activate
export PADDING_LEAK_LOG=./events.csv
bash scripts/run_codechecker.sh /path/to/project /path/to/compile_commands.json
```

Generate `compile_commands.json` for CMake projects:

```bash
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DCMAKE_C_COMPILER=/usr/lib/llvm21/bin/clang \
      -DCMAKE_CXX_COMPILER=/usr/lib/llvm21/bin/clang++ \
      ...
```

---

## Annotating Your Own Project

The checker only flags by-value record transfers at functions you explicitly
annotate — it does not infer boundaries automatically (see
[Known Limitations](#known-limitations)).

**Step 1 — Include the annotation header**

Copy `include/trust_boundary.h` into your project or add `include/` to your
compiler's include path. The macro expands to
`__attribute__((annotate("trust_boundary")))` under Clang/GCC and is a
no-op everywhere else.

**Step 2 — Annotate boundary functions**

Add `TRUST_BOUNDARY` to any function declaration whose by-value record
arguments or return values cross a trust domain. Annotate the declaration,
not just the definition:

```c
#include "trust_boundary.h"

TRUST_BOUNDARY int send_packet(struct Packet pkt);
TRUST_BOUNDARY struct Reply receive_reply(void);
```

A function is a good candidate if it:
- is externally visible on a public API surface,
- accepts or returns a struct or class object by value, and
- represents a transition between components with different confidentiality
  assumptions (e.g., library-internal state to external caller, trusted
  enclave to untrusted host, kernel to userspace).

**Step 3 — Build with Clang 21 and run**

```bash
# Generate compile_commands.json
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DCMAKE_C_COMPILER=/usr/lib/llvm21/bin/clang \
      -DCMAKE_CXX_COMPILER=/usr/lib/llvm21/bin/clang++ \
      ...

# Run the checker
source .codechecker-env/bin/activate
export PADDING_LEAK_LOG=./events.csv
bash scripts/run_codechecker.sh /path/to/project compile_commands.json
```

---

## Synthetic Benchmark Suite (Appendix A)

`synthetic_benchmarks/trust_boundary/benchmarks.c` contains all 8 validation
cases from Appendix A:

```bash
/usr/lib/llvm21/bin/clang-tidy \
  -load build/SecurityMiscPlugin.so \
  -checks='-*,security-misc-padding-boundary-leak' \
  synthetic_benchmarks/trust_boundary/benchmarks.c -- -I./include
```

Expected results:

| Case | Scenario | Expected |
|---|---|---|
| `case01` | Padding present, uninit pass-by-value | **WARN** |
| `case02` | Padding present, `memset` zero | no warn† |
| `case03` | No padding in type | no warn |
| `case04` | Padding present, uninit return-by-value | **WARN** |
| `case05` | `__attribute__((packed))`, no padding | no warn |
| `case06` | Field-wise init only | **WARN** |
| `case07` | `= {0}` whole-object init | no warn |
| `case08` | Nested struct with padding | **WARN** |

† case02 currently produces a false positive — `memset`-based suppression is
not yet implemented (see [Known Limitations](#known-limitations)).

---

## Reproducing the Thesis Evaluation

`scripts/reproduce_all.sh` performs the full reproduction in one command:

1. Builds the checker plugin against LLVM 21
2. Runs the synthetic benchmark suite
3. Clones each evaluated library at the exact thesis version
4. Applies the `TRUST_BOUNDARY` annotations from `evaluated_libraries/`
5. Builds each library with Clang 21 to generate `compile_commands.json`
6. Runs CodeChecker on each library
7. Prints the metrics from Tables 8.2 and 8.3

```bash
source .codechecker-env/bin/activate
bash scripts/reproduce_all.sh
```

Expected output matches thesis Tables 8.2 and 8.3:

| Project | \|B\| | \|EB\| | Nrec | Npad | NE2 | NE3 | Nsup | rpad | rdiag |
|---|---|---|---|---|---|---|---|---|---|
| zlib | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0.000 | 0.000 |
| libuv | 1 | 2 | 1 | 0 | 0 | 0 | 0 | 0.000 | 0.000 |
| raylib | 5 | 20 | 3 | 1 | 0 | 0 | 8 | 0.333 | 0.000 |
| chipmunk2d | 3 | 6 | 2 | 1 | 4 | 0 | 0 | 0.500 | 0.667 |

Full logs are written to `_logs/` and CodeChecker results to `_results/`.
See `evaluated_libraries/README.md` for per-project annotation details.

---

## Diagnostic Output

A typical finding looks like:

```
cpArbiter.c:87:10: warning: [E2] boundary transfer of 'cpContactPointSet'
(56 bytes, 4 padding bytes) by value at trust boundary
'cpArbiterGetContactPointSet': the ABI copies the full object representation
including padding bytes that may contain indeterminate or stale data.
Remediation: (a) zero-initialize before assignment
(e.g., `cpContactPointSet v = {0};`), or (b) serialise only semantic fields
into an explicit boundary buffer.
[security-misc-padding-boundary-leak]
```

---

## Known Limitations

Documented as future work in Chapter 9 of the thesis:

- **`memset` suppression not implemented** — whole-object initialization via
  `memset(&obj, 0, sizeof obj)` is not yet recognized as a suppression
  condition. The `= {0}` idiom is correctly handled. (§9.1)
- **No interprocedural analysis** — initialization through helper functions
  defined in separate translation units is not tracked. All real-world
  findings are therefore classified E2 rather than E3. (§9.3)
- **No pointer or alias tracking** — only by-value transfers are modeled;
  pointer-mediated transfers require alias analysis and are out of scope. (§9.4)
- **Explicit boundary annotations required** — `TRUST_BOUNDARY` must be added
  manually; automatic boundary inference is future work. (§9.2)

---

## License

MIT — see [LICENSE](LICENSE).
