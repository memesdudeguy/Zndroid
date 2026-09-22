# Zndroid Design Doc
### Fusing ideas from KnightOS and FUZIX — realistically

## 1. Reality check first

| | Android | FUZIX (Z80, realistic target) | TI-84 Plus (Z80, mono) |
|---|---|---|---|
| RAM | 2 GB+ | ~96 KB+ with banking, per FUZIX's own wiki | ~24 KB usable |
| Storage | GBs, flash | Hard disk / CF / SD typical | ~1.5 MB flash, shared with TI-OS apps |
| Display | Composited GPU framebuffer | Text/VT52 or simple framebuffer | 96×64 1-bit LCD |
| Runtime | Java/Kotlin + ART | C, banked processes | Z80 machine code / C via SDCC |

Two conclusions fall out of this immediately:

- **A literal Android port is not a scaled-down engineering problem, it's a different machine.** There's no realistic path to a JVM, a compositor, or touch-style multitasking on 24 KB of RAM and a 1-bit display.
- **A literal FUZIX kernel boot is also out of reach on stock hardware.** FUZIX's Z80 port assumes bank-switched RAM in the 96 KB+ range (its supported Z80 targets are things like the RC2014, Microbee, and Spectrum 128K) — about 4x more RAM than an unmodified 84+ has, with no hard disk equivalent either. It's a real, working Unix on Z80 — just not on this particular calculator without a hardware RAM-expansion mod.

What *is* realistic: KnightOS already targets this exact hardware and already gives you a Unix-flavored base (tree filesystem, package manager, cooperative multitasking) within the real RAM budget. So the practical plan is:

> **Kernel: KnightOS, unmodified.**
> **Borrowed from FUZIX: design/VFS conventions, not the kernel itself.**
> **Borrowed from Android: the *user experience* vocabulary — launcher, app drawer, manifests, lightweight permissions — reimplemented natively as KnightOS userspace apps.**

If you later get real RAM expansion hardware (or target a beefier Z80 board), the FUZIX kernel itself becomes viable and this same app layer could in principle be ported over its VFS, since KnightOS and FUZIX both use fairly conventional Unix-y path/inode conventions.

## 1.1 Grayscale on 1-bit hardware

The 84+'s LCD is physically 1-bit — but Z80 calc devs have a standard trick to fake grayscale: draw two (or three) different 1-bit frames and flip between them fast enough that LCD pixel persistence blends the on/off states into apparent gray levels. This is how classic TI-83+/84+ games get "3-level" or "4-level" grayscale with no special hardware. The tradeoffs:

- **Cost:** CPU time and a second (or third) framebuffer in RAM — real money in a 24 KB budget. 2-plane grayscale (3 levels: black/gray/white) is the practical ceiling for a launcher UI; going to 3 planes (7 levels) eats more RAM and CPU than an app drawer needs.
- **Flicker artifacts:** if the flip rate drops (e.g. blocked on a slow syscall), you get visible flicker instead of smooth gray. Anything that draws grayscale needs to run inside a tight, uninterrupted timer-driven loop.
- **Interrupt-driven swap:** the standard approach hooks a timer interrupt to swap `plane0`/`plane1` to the LCD on a fixed cadence (commonly ~60 Hz total, so each plane shows at ~30 Hz), independent of whatever the main app logic is doing.

This changes the design in two concrete ways from a pure 1-bit UI:
- Icons and UI chrome are now **2-bitplane images** instead of 1-bit `.kimg` — each pixel is 2 bits (00=white, 01/10=gray, 11=black) split across the two planes.
- Rendering code writes to *both* planes, and a small interrupt-driven "flip driver" owns swapping them to the LCD — app code should never `clearLCD`/blit directly to the display during normal operation, only into the plane buffers.

## 2. Proposed system layers

```
┌─────────────────────────────────────────┐
│  "Droidlets" — userspace apps            │  ← Android-inspired UX
│  (launcher, app drawer, settings, shell) │
├─────────────────────────────────────────┤
│  Shell/compat layer                      │  ← FUZIX-inspired conventions:
│  - manifest.json per app                 │    /bin, /dev, /etc layout;
│  - lightweight capability flags          │    simple message-passing "intents"
│  - intent-style mailbox messaging        │
├─────────────────────────────────────────┤
│  KnightOS kernel + package manager       │  ← unmodified, does the real work
│  (multitasking, tree FS, drivers)        │
├─────────────────────────────────────────┤
│  TI-84 Plus hardware (Z80, 96×64 mono)   │
└─────────────────────────────────────────┘
```

### 2.1 "Launcher" home screen
A grid-based app drawer app, analogous to an Android launcher, drawn with KnightOS's graphics syscalls, reading installed packages from the existing KnightOS package directory and rendering each as a small monochrome icon + label in a scrollable grid, with the arrow keys/2nd for navigation and Enter to launch.

### 2.2 App manifest ("mini-APK")
KnightOS already installs packages via `package.config`/its SDK. Extend each app's package metadata with a small JSON/INI sidecar so the launcher and permission layer can reason about it without parsing binaries:

```ini
; manifest.ini — lives alongside the app's .k binary in its package
[app]
name = Notes
icon = notes.gimg       ; 16x16 2-bitplane grayscale icon (see 1.1)
entry = notes.k
version = 0.1

[display]
grayscale = true         ; opt-in: app draws into plane0/plane1, not 1-bit LCD directly

[permissions]
filesystem = rw         ; none | ro | rw
link_port = false       ; needs the calc-to-calc link cable
clock = read
```

### 2.3 Lightweight "intents"
FUZIX-style: keep it as plain files/mailboxes rather than a real IPC bus. A shared `/etc/intents/` directory (or a KnightOS mailbox primitive, if the kernel exposes one) where an app drops a small message file (`target_app`, `action`, `data`) and the target app polls or is woken on next launch. This gets you "share to," "open with," etc. without inventing a binder protocol.

### 2.4 Permissions, lite
No real sandboxing is feasible in 24 KB, but you can get the *spirit* of Android permissions: the launcher reads each manifest's `[permissions]` block and shows a one-time confirmation ("Notes wants to use the link port — Allow?") stored as a bit in a per-app settings file, purely a UX/consent layer, not a security boundary.

## 3. Starter skeleton (z80 asm, KnightOS conventions, grayscale)

This is a **skeleton to adapt**, not tested/compiled code — I don't have a working KnightOS SDK toolchain in this sandbox (no network access to fetch it), and exact syscall names should be checked against the current kernel headers at github.com/KnightOS/kernel and the docs at knightos.org. The structure below follows the SDK's usual app layout (`knightos init`, `make`, `make run`).

```z80
; launcher.asm — grid-based app drawer skeleton for KnightOS, 2-plane grayscale
; Build with the KnightOS SDK: knightos init --platform=TI84p
; then drop this into a package and `make run` in the emulator.

.module Launcher

.org 0
    jp start

app_name:
    .db "Launcher", 0

; --- Grayscale framebuffers ---
; 96x64 1-bit = 768 bytes per plane. Two planes = 1536 bytes, ~6% of RAM budget.
plane0: .ds 768              ; "on" bits for frame A
plane1: .ds 768              ; "on" bits for frame B
curPlane: .db 0               ; which plane the flip ISR is currently pushing to LCD

start:
    call installFlipISR       ; hook timer interrupt, see section below
    call loadPackageList      ; enumerate installed packages, see kernel/package.inc
    ld hl, packageListBuffer
    ld b, 0                   ; cursor index

drawLoop:
    call clearPlanes          ; zero plane0 + plane1 (NOT clearLCD — ISR owns the LCD now)
    call renderGridGray        ; draw 2-bit icons into plane0/plane1 from packageListBuffer
    call highlightCursorGray    ; invert cell [b] in both planes

readInput:
    call getKey                ; blocking key read, see kernel/keyboard.inc
    cp KEY_RIGHT
    jr z, moveRight
    cp KEY_LEFT
    jr z, moveLeft
    cp KEY_ENTER
    jr z, launchSelected
    jr readInput

launchSelected:
    call removeFlipISR         ; hand the LCD back before exec, launched app owns display mode
    call execSelectedPackage   ; see kernel/exec.inc for the actual process-spawn syscall
    call installFlipISR        ; reinstall on return to launcher
    jr drawLoop

moveRight:
    inc b
    jr drawLoop
moveLeft:
    dec b
    jr drawLoop

; --- Flip ISR: swaps plane0/plane1 to the LCD each timer tick ---
; Runs independent of drawLoop/readInput so grayscale stays smooth
; even while blocked on getKey. Target ~30Hz per plane (~60Hz total flips).
flipISR:
    ld a, (curPlane)
    xor 1
    ld (curPlane), a
    or a
    jr z, pushPlane0
    ld hl, plane1
    jr pushToLCD
pushPlane0:
    ld hl, plane0
pushToLCD:
    call blitToLCD             ; existing 1-bit LCD blit syscall, see kernel/graphics.inc
    ei
    reti

packageListBuffer:
    .ds 256                    ; adjust to real package-list format
```

Companion 2-bitplane icon format (replaces the earlier 1-bit `.kimg` sketch):

```
.gimg layout (16x16 example):
  byte 0-1   : width, height
  byte 2..33  : plane0 bitmap, 16x16 1bpp, row-major (32 bytes)
  byte 34..65 : plane1 bitmap, 16x16 1bpp, row-major (32 bytes)
  pixel value = (plane1_bit << 1) | plane0_bit
    00 = white, 01/10 = gray (pick one consistently, e.g. 01=light gray),
    11 = black
```

Companion manifest for the launcher itself:

```ini
[app]
name = Launcher
icon = launcher.kimg
entry = launcher.k
version = 0.1

[permissions]
filesystem = ro
```

## 4. TinyJ: a simplified Java VM for apps

Rather than writing every app in raw Z80, give KnightOS apps a tiny bytecode VM — the same role Dalvik/ART plays for Android APKs, scaled to a 24 KB machine. This isn't unprecedented: several real embedded/8-bit-class devices have shipped cut-down Java VMs (e.g. leJOS's custom VM for the Lego Mindstorms RCX brick, NanoVM for AVR) by aggressively dropping the parts of the JVM spec that don't fit — no GC, no reflection, no exceptions, fixed-size everything. TinyJ follows the same recipe.

**What TinyJ keeps from Java:** classes with fields and methods, single inheritance, `int`/`byte`/`boolean` primitives, arrays, `if`/`while`, static and virtual method calls.
**What it drops:** garbage collection, exceptions, interfaces/generics, threads, floating point (or: fixed-point only), strings-as-objects (use byte arrays instead), reflection.

### 4.1 Where compilation happens
The compiler runs **off-device**, on your PC — exactly like `javac`+`dex` never run on an Android phone either. Only the interpreter runs on the calculator. So the toolchain is:

```
MyApp.tj.java  --[host-side Python/whatever compiler]-->  MyApp.tjc (bytecode)
                                                                 │
                                                     packaged as a KnightOS app,
                                                     entry = MyApp.tjc, runtime = tinyjvm.k
```

### 4.2 Memory model (no GC)
- **Constant pool** (class/method names, string/byte-array literals, bytecode itself) lives in flash — costs zero RAM.
- **Object heap** is a simple bump allocator, arena-scoped to the app's run. `new` just advances a pointer; there is no `free` and no collector. When the app exits, KnightOS reclaims the whole process's memory in one shot — same as it already does for native apps.
- If the bump pointer hits the top of the arena, the VM traps with an `OutOfMemory` error rather than silently corrupting memory.
- **Operand stack + call frames** are a small fixed region (e.g. 64 words); recursion depth is bounded and checked, not GC'd.

This means TinyJ is fine for UI logic, settings, simple data structures — but not for anything that allocates unboundedly in a loop. That's an explicit, documented limitation, not a bug to work around.

### 4.3 Bytecode (stack machine, 1-byte opcodes)

| Opcode | Effect |
|---|---|
| `ICONST n` | push immediate 8-bit int (sign-extended) |
| `ILOAD s` / `ISTORE s` | push/pop local variable slot `s` |
| `IADD` `ISUB` `IMUL` `IDIV` | pop 2, push result |
| `ICMP_LT` `ICMP_EQ` | pop 2, push 0/1 |
| `IFEQ off` `GOTO off` | conditional/unconditional branch |
| `NEW classIdx` | bump-allocate an instance, push ref |
| `GETFIELD i` / `PUTFIELD i` | object field access |
| `NEWARRAY n` / `ALOAD` / `ASTORE` | fixed-size array alloc/access |
| `INVOKEVIRTUAL m` / `INVOKESTATIC m` | call, pushes new frame |
| `RETURN` / `IRETURN` | pop frame, optionally push result |
| `SYSCALL id` | bridge into a native KnightOS syscall — this is how a TinyJ app draws icons into `plane0`/`plane1`, reads keys, or reads the package list from §3 |
| `HALT` | stop the VM (app exit) |

`SYSCALL` is the important bit: it's the seam between managed TinyJ code and the native launcher/grayscale driver from §3. The flip ISR and any tight timing-critical code (the grayscale swap loop itself) should stay hand-written Z80 — interpretation overhead makes a bytecode VM the wrong tool for a 60 Hz interrupt handler, same reason Android's own compositor and drivers are native, not Dalvik bytecode.

### 4.4 VM main loop skeleton (Z80)

```z80
; tinyjvm.asm — bytecode interpreter core (fetch/decode/dispatch)
; runs as a KnightOS package, loads a .tjc file and executes its main method

vmLoop:
    ld a, (pc)          ; fetch opcode byte pointed to by virtual PC
    inc_pc
    ld hl, dispatchTable
    ld d, 0
    ld e, a
    add hl, de
    add hl, de           ; *2, each table entry is a 2-byte jp target
    ld e, (hl)
    inc hl
    ld d, (hl)
    push de
    ret                   ; "computed jump" to the opcode handler

op_ICONST:
    ld a, (pc)
    inc_pc
    call pushStack        ; sign-extend and push onto operand stack
    jp vmLoop

op_IADD:
    call popStack          ; -> HL
    call popStack          ; -> DE
    add hl, de
    call pushStackHL
    jp vmLoop

op_SYSCALL:
    ld a, (pc)
    inc_pc
    ld hl, syscallTable
    ; ... dispatch to native launcher/graphics/keyboard routines from §3 ...
    jp vmLoop

op_HALT:
    call teardownVM         ; free the arena, return to KnightOS
    ret
```

### 4.5 Example TinyJ source (compiled off-device)

```java
// Counter.tj.java — compiled by the host-side toolchain to Counter.tjc
class Counter {
    int value;

    void increment() {
        value = value + 1;
    }

    boolean isMax() {
        return value >= 99;
    }
}
```

Manifest gains a `runtime` field so the launcher knows to hand this off to `tinyjvm.k` instead of exec'ing it as native code:

```ini
[app]
name = Counter
icon = counter.gimg
entry = counter.tjc
runtime = tinyjvm       ; launcher execs tinyjvm.k, passing counter.tjc as its argument
version = 0.1
```

## 5. Suggested build order

1. **Get vanilla KnightOS building and running** in the `jsTIfied`/KnightOS emulator via `knightos init --platform=TI84p && make run` — confirms toolchain before any custom work.
2. **Launcher app** (above skeleton) reading the real package list format from the current KnightOS kernel source.
3. **Manifest sidecar + permission-confirmation dialog.**
4. **Intent mailbox** for simple app-to-app handoff (e.g., "share text" from Notes to a Send-via-link app).
5. **TinyJ VM + host-side compiler** (§4) — get the interpreter running a trivial `Counter`-style app before porting anything more ambitious to it.
6. *(Stretch, needs RAM-expansion hardware)* Explore whether a FUZIX Z80 target could host this same app layer over its VFS instead of KnightOS's.

## References
- KnightOS kernel/userspace: https://github.com/KnightOS/KnightOS, https://github.com/KnightOS
- KnightOS SDK & docs: https://knightos.org
- FUZIX: https://github.com/EtchedPixels/FUZIX (see `Kernel/PORTING` and the wiki for per-architecture memory requirements)
