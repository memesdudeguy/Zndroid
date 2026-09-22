# Zndroid

A FOSS, Android-*flavored* userspace built on top of **KnightOS** for the
TI-84 Plus (Z80, monochrome), with grayscale via LCD-persistence flicker
and a tiny managed-bytecode app runtime ("TinyJ") playing Dalvik's role.

## What's actually real here vs. what's a starting skeleton

| Piece | Status |
|---|---|
| `tools/tinyj_compiler.py` | **Tested.** Compiles a real single-class subset (fields, `if`/`else`, `while`, method calls) to TinyJ bytecode. |
| `tools/tinyj_vm_ref.py` | **Tested.** Reference interpreter, same semantics the Z80 VM should implement. |
| `tools/run_example.py` | **Tested, passing.** End-to-end: compiles `Counter`, runs it, verifies a while-loop sum against a hand-computed expected value. Run it yourself: `python3 tools/run_example.py`. |
| `z80/zndroid_launcher.asm` | **Untested skeleton.** Structure and control flow are filled in; syscalls marked `TODO` need real KnightOS kernel headers to resolve. |
| `z80/gfx_driver.asm` | **Untested skeleton.** Same caveat — the flip-ISR *logic* is written, the interrupt-hookup syscalls are placeholders. |
| `z80/tinyjvm.asm` | **Untested skeleton**, deliberately structured as a near-mechanical port of `tinyj_vm_ref.py`'s dispatch loop, opcode-for-opcode. A few spots (`PUTFIELD` stack order, `INVOKEVIRTUAL`/`RETURN` frame handling) are flagged `TODO` because they need to be wired up carefully against the tested Python semantics rather than guessed. |

**Why the Z80 files aren't compiled or verified:** I don't have network
access in this environment to pull the KnightOS SDK/kernel source, and no
z80 assembler installed locally. The Python toolchain, by contrast, needed
nothing external — so that's the part I could actually run and check.

## Why this design (not literal Android, not literal FUZIX)

- **Android** needs a JVM, a GPU compositor, and gigabytes of RAM — not a
  scaled-down version of the same problem, a different machine. The 84+ has
  ~24 KB of usable RAM.
- **FUZIX**'s own Z80 port targets machines with ~96 KB+ of banked RAM
  (RC2014, Microbee, Spectrum 128K-class hardware) — about 4x what a stock
  84+ has. Its kernel is real and works, just not on this hardware unmodified.
- **KnightOS** already targets this exact calculator within its real RAM
  budget, so it's the kernel. Android and FUZIX contribute *vocabulary and
  conventions* — launcher/manifest/permissions from Android, Unix-y
  path/VFS thinking from FUZIX — reimplemented natively as KnightOS
  userspace.

Full design rationale, the grayscale-flicker technique, and the TinyJ
memory model are in `docs/DESIGN.md`. Rough perf numbers for the bytecode
VM vs. native Z80 are in `docs/PERFORMANCE.md`.

## Build order

1. Get vanilla KnightOS building: `knightos init --platform=TI84p && make run`.
2. Bring up `zndroid_launcher.asm` against the real kernel headers —
   resolve every `TODO` syscall first.
3. Bring up `gfx_driver.asm`'s flip ISR; confirm grayscale renders without
   tearing before building anything on top of it.
4. Bring up `tinyjvm.asm`'s dispatch loop; validate opcode-by-opcode against
   `tools/tinyj_vm_ref.py`'s (working) behavior on the same bytecode file.
5. Only then: manifests, intents, permission dialogs, more apps.

## Directory layout

```
zndroid/
  README.md
  docs/
    DESIGN.md         full architecture writeup
    PERFORMANCE.md    VM overhead estimates, ISR/scheduling notes
  tools/              host-side, tested
    tinyj_compiler.py
    tinyj_vm_ref.py
    run_example.py
    example_counter.tj.java
    example_counter.tjc
  z80/                on-device, untested skeletons
    zndroid_launcher.asm
    gfx_driver.asm
    tinyjvm.asm
    manifests/
      zndroid_launcher.ini
      counter.ini
```
