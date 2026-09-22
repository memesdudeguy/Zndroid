; ============================================================
; zndroid_launcher.asm — Zndroid launcher for KnightOS
; Simplified working version first, then we'll add Android style
; ============================================================

#include "kernel.inc"

    .db "KEXC"
    .db KEXC_ENTRY_POINT
    .dw start
    .db KEXC_STACK_SIZE
    .dw 64
    .db KEXC_NAME
    .dw appName
    .db KEXC_HEADER_END

appName:
    .db "Zndroid", 0

; --- Constants ---
GRID_COLS       .equ 4
GRID_TOP_Y      .equ 10
MAX_APPS        .equ 16
NAME_SLOT_SIZE  .equ 16

; --- State ---
cursorIndex:  .db 0
numApps:      .db 0

; --- App name slots (16 x 16 bytes) ---
slot00: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot01: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot02: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot03: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot04: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot05: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot06: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot07: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot08: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot09: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot10: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot11: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot12: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot13: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot14: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
slot15: .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; Launch path buffer
launchBuf:
    .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; ============================================================
start:
    pcall(getLcdLock)
    pcall(getKeypadLock)
    pcall(allocScreenBuffer)

    call loadPackageList

    xor a
    ld (cursorIndex), a

mainLoop:
    pcall(clearBuffer)
    call drawTitle
    call drawAppNames
    call drawCursorHighlight
    pcall(fastCopy)

readInput:
    pcall(flushKeys)
    pcall(waitKey)
    cp kRight
    jp z, moveRight
    cp kLeft
    jp z, moveLeft
    cp kDown
    jp z, moveDown
    cp kUp
    jp z, moveUp
    cp kEnter
    jp z, launchSelected
    cp kMode
    jp z, exitLauncher
    jp readInput

exitLauncher:
    pcall(freeScreenBuffer)
    ret

launchSelected:
    ld a, (numApps)
    or a
    jp z, mainLoop
    call execSelectedPackage
    call loadPackageList
    xor a
    ld (cursorIndex), a
    jp mainLoop

; ============================================================
; Navigation
; ============================================================
moveRight:
    ld a, (cursorIndex)
    and GRID_COLS - 1
    cp GRID_COLS - 1
    jp nc, mainLoop
    ld a, (cursorIndex)
    inc a
    ld (cursorIndex), a
    jp mainLoop

moveLeft:
    ld a, (cursorIndex)
    and GRID_COLS - 1
    or a
    jp z, mainLoop
    ld a, (cursorIndex)
    dec a
    ld (cursorIndex), a
    jp mainLoop

moveDown:
    ld a, (cursorIndex)
    add a, GRID_COLS
    ld b, a
    ld a, (numApps)
    cp b
    jp c, mainLoop
    jp z, mainLoop
    ld a, b
    ld (cursorIndex), a
    jp mainLoop

moveUp:
    ld a, (cursorIndex)
    sub GRID_COLS
    jp c, mainLoop
    ld (cursorIndex), a
    jp mainLoop

; ============================================================
; drawTitle — Simple title at top
; ============================================================
drawTitle:
    kld(hl, titleStr)
    ld d, 0
    ld e, 0
    pcall(drawStr)
    ret

titleStr:
    .db "Zndroid", 0

; ============================================================
; drawAppNames — Draw app names in a grid
; ============================================================
drawAppNames:
    ld a, (numApps)
    or a
    ret z

    ld b, 0                     ; app index
.drawLoop:
    ld a, b
    cp MAX_APPS
    ret nc

    push bc

    ; Compute x = (index % 4) * 24
    ld a, b
    and 3                       ; col (0-3)
    ld l, a
    ld h, 0
    add hl, hl                  ; *2
    add hl, hl                  ; *4
    add hl, hl                  ; *8
    push hl                     ; save *8
    add hl, hl                  ; *16
    pop de                      ; DE = *8
    add hl, de                  ; HL = *24
    ld d, l                     ; D = x

    ; Compute y = (index / 4) * 20 + 10
    ld a, b
    srl a
    srl a                       ; row
    ld l, a
    ld h, 0
    add hl, hl                  ; *2
    add hl, hl                  ; *4
    add hl, hl                  ; *8
    push hl                     ; save *8
    add hl, hl                  ; *16
    pop de                      ; DE = *8
    add hl, de                  ; HL = *24
    ld a, l
    add a, GRID_TOP_Y
    ld e, a                     ; E = y

    ; Get app name pointer
    ld a, b
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                  ; *16
    ld de, slot00
    add hl, de

    ld a, (hl)
    or a
    jr z, .skip

    pcall(drawStr)

.skip:
    pop bc
    inc b
    jp .drawLoop

; ============================================================
; drawCursorHighlight — Invert pixels around selected app
; ============================================================
drawCursorHighlight:
    ld a, (numApps)
    or a
    ret z

    ; Compute cell position
    ld a, (cursorIndex)
    and 3                       ; col
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    push hl
    add hl, hl
    pop de
    add hl, de                  ; col * 24
    ld d, l                     ; D = x

    ld a, (cursorIndex)
    srl a
    srl a                       ; row
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    push hl
    add hl, hl
    pop de
    add hl, de
    ld a, l
    add a, GRID_TOP_Y
    ld e, a                     ; E = y

    ; Invert a 22x18 rectangle
    ld b, 18
.hlRow:
    push bc
    push de
    ld b, 22
.hlCol:
    pcall(invertPixel)
    inc d
    djnz .hlCol
    pop de
    inc e
    pop bc
    djnz .hlRow
    ret

; ============================================================
; loadPackageList — Enumerate /bin directory
; ============================================================
loadPackageList:
    xor a
    ld (numApps), a

    kld(de, binPath)
    kld(hl, dirCallback)
    pcall(listDirectory)
    ret

binPath:
    .db "/bin", 0

; ============================================================
; dirCallback — Called by listDirectory for each entry
; HL = FAT entry, BC = length, A = type
; kernelGarbage = entry name (in RAM, banked in)
; 
; CRITICAL: This runs with flash banked, so we CANNOT use
; kld or pcall here. We must use direct addresses only.
; We CAN modify IX and IY freely.
; ============================================================
dirCallback:
    cp fsFile
    ret nz

    push af
    push bc
    push de
    push hl

    ld a, (numApps)
    cp MAX_APPS
    jp nc, .done

    ld c, a                     ; C = current index

    ; dest = slot00 + index * 16
    ; Use IX for destination pointer
    ld ix, slot00
    ld h, 0
    ld l, c
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                  ; *16
    add ix, hl                  ; IX = destination

    ; Source: kernelGarbage - use kld to get the address
    ; Wait, we can't use kld! But kernelGarbage is a symbol we can reference
    ; Actually, the name is already in kernelGarbage buffer in RAM
    ; We need to find its address. From kernel.inc, it's at a fixed location.
    ; Let's use IY for source pointer
    ld iy, kernelGarbage

    ld b, 15
.copyLoop:
    ld a, (iy+0)
    ld (ix+0), a
    or a
    jr z, .copyDone
    inc iy
    inc ix
    djnz .copyLoop
    xor a
    ld (ix+0), a
.copyDone:

    ld a, c
    inc a
    ld (numApps), a

.done:
    pop hl
    pop de
    pop bc
    pop af
    ret

; ============================================================
; execSelectedPackage — Launch selected app
; ============================================================
execSelectedPackage:
    ld a, (numApps)
    or a
    ret z

    ; Build path: "/bin/" + appname
    ld hl, launchBuf
    ld de, binSlash
    ld bc, 5
    ldir

    ; Get selected app name
    ld a, (cursorIndex)
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                  ; *16
    ld de, slot00
    add hl, de                  ; HL = &slot[cursorIndex]

    ld de, launchBuf + 5
    ld b, 15
.appendLoop:
    ld a, (hl)
    ld (de), a
    or a
    jr z, .appendDone
    inc hl
    inc de
    djnz .appendLoop
    xor a
    ld (de), a
.appendDone:

    ld de, launchBuf
    pcall(launchProgram)
    ret

binSlash:
    .db "/bin/", 0
