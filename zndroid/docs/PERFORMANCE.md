# Zndroid: VM Performance & Scheduling Notes

These are back-of-envelope estimates from Z80 instruction timing, not a
measured benchmark — no Z80 emulator was available in this sandbox to
actually run the numbers. Treat the ranges as planning guidance, not spec.

## Native vs. TinyJ bytecode

The 84+ runs its Z80 at 6 MHz stock (up to ~15 MHz in the "fast mode" many
games/shells use). A tight native loop — increment, compare, branch — is
~5-6 instructions, ~40-60 T-states: roughly 100,000-150,000 iterations/sec
at 6 MHz.

The same loop compiled to TinyJ bytecode (`ILOAD`, `ICONST`, `IADD`,
`ISTORE`, `ILOAD`, `ICONST`, `ICMP_LT`, `IFNE`) is ~8 ops. Each op costs
fetch + computed-jump dispatch + the actual work, roughly 80-110 T-states
per op. That's **very roughly 10-20x slower than native** — somewhere in
the 7,000-20,000 iterations/sec range depending on clock speed.
`GETFIELD`/`ARRAYLOAD`-heavy code sits toward the slower end (extra pointer
dereference per op).

**What that's fine for:** menu navigation, settings, small data records,
anything reacting at human speed.
**What it isn't fine for:** per-pixel graphics work or a tight animation
loop driven entirely from bytecode. That's why `SYSCALL` (see
`docs/DESIGN.md` sec 4.3) routes graphics/timing-critical work into native
Z80 instead — same split Android itself uses between native drivers/
compositor and managed app code.

## Does the grayscale flip ISR stay smooth under a slow VM?

Yes, structurally: the flip ISR (`z80/gfx_driver.asm`) fires from a
hardware timer interrupt, not from anything the foreground code does. As
long as the VM's dispatch loop doesn't sit with interrupts disabled (`DI`)
for long stretches, the ISR preempts it on schedule regardless of how fast
or slow the interpreter is running underneath. A slow VM makes the *app*
feel less responsive; it does not make the *display* flicker.

**The one thing that needs care:** if a TinyJ app's `SYSCALL` handler
writes into `plane0`/`plane1` directly and the flip ISR fires mid-write,
you can tear a frame. The fix is `gfx_driver.asm`'s `writePixelSafe` — a
short `DI`/`EI` bracket around the buffer write, costing maybe a few dozen
T-states against a ~33ms frame budget. Negligible.

## Open question: KnightOS scheduler

Whether KnightOS's process scheduler is cooperative or timer-preemptive
changes whether the TinyJ VM loop needs explicit yield points to avoid
starving other processes. Needs checking against the current kernel
source (`kernel/scheduler.inc` or equivalent) before `tinyjvm.asm`'s main
loop is finalized — flagged as a `TODO` there.
