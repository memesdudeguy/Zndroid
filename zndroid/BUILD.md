# Building Zndroid on Arch Linux

## Quick build

```bash
./build.sh
```

This assembles the Z80 binary and runs the Python TinyJ toolchain test.

## Manual build

### Z80 binary (KnightOS app)

```bash
cd build
make            # assembles z80/*.asm -> bin/root/bin/zndroid-launcher
make clean      # remove build artifacts
```

### Python TinyJ toolchain (no install needed)

```bash
cd tools
python3 run_example.py
```

## Prerequisites

- **sass** (KnightOS Z80 assembler) — installed via `knightos-sdk` from AUR
- **Python 3** — for the TinyJ toolchain
- **knightos** SDK tools (`genkfs`, `kpack`, `kimg`) — from AUR

The kernel headers were built from `/home/memesdudeguy/src/knightos/kernel` using
locally compiled `patchrom` and `mkrom` tools. The generated headers live in
`build/.knightos/include/kernel.inc`.

## What compiles and what doesn't

| Component | Status |
|---|---|
| `tools/run_example.py` | **Working.** End-to-end TinyJ test passes. |
| `z80/zndroid_launcher.asm` | **Assembles.** KnightOS KEXC app with real syscalls. |
| `z80/gfx_driver.asm` | **Assembles.** IM2-based grayscale flip ISR. |
| `z80/tinyjvm.asm` | **Assembles.** Full TinyJ dispatch loop with all opcodes. |

## Notes

- The Z80 binary needs the **z80e** emulator to run (`make run` in `build/`),
  which is not currently installed. Install with `yay -S z80e`.
- Several launcher features (package enumeration, RTC display, icon rendering)
  are structurally present but need further implementation against a running
  KnightOS system to validate.
- The `sass` assembler is case-insensitive, so label and `.equ` names must
  not differ only by case (e.g., `OP_NOP` and `op_NOP` would conflict).
