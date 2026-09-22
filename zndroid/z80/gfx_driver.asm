; ============================================================
; gfx_driver.asm — grayscale flip-ISR driver for Zndroid
; Target: KnightOS on TI-84 Plus (Z80), 2-plane grayscale
;
; The 84+ LCD is physically 1-bit. Flipping two different
; 1-bit frames fast enough that LCD persistence blends them
; gives ~3 apparent gray levels (white/gray/black).
;
; Uses IM2 for the custom interrupt vector so we don't
; conflict with KnightOS's IM1 timer handler.
; ============================================================

; --- Grayscale framebuffers ---
; 96x64 1-bit = 768 bytes/plane. Two planes = 1536 bytes.
plane0:      .ds 768
plane1:      .ds 768
curPlane:    .db 0

; IM2 vector table — 257 bytes, filled at init with flipISR addr
im2VectorTable:
    .ds 257

; ============================================================
; installFlipISR — switch to IM2 and hook our flip handler.
; ============================================================
installFlipISR:
    di
    ld hl, im2VectorTable
    ld de, flipISR
    ld b, 0              ; 0 = 256 iterations
.patchLoop:
    ld (hl), e
    inc hl
    ld (hl), d
    inc hl
    djnz .patchLoop
    ld (hl), e           ; 257th byte
    inc hl
    ld (hl), d

    ld a, im2VectorTable >> 8
    ld i, a
    im 2

    in a, (0x30)
    or 0x02              ; enable timer1 interrupt
    out (0x30), a

    ei
    ret

; ============================================================
; removeFlipISR — restore IM1 and disable our timer hook.
; ============================================================
removeFlipISR:
    di
    in a, (0x30)
    and 0xFD             ; clear timer1 interrupt enable
    out (0x30), a
    im 1
    ei
    ret

; ============================================================
; flipISR — swaps plane0/plane1 to the physical LCD each tick.
; ============================================================
flipISR:
    push af
    push bc
    push de
    push hl

    ld a, (curPlane)
    xor 1
    ld (curPlane), a

    or a
    jr z, .usePlane0
    ld hl, plane1
    jr .blitStart
.usePlane0:
    ld hl, plane0

.blitStart:
    ld a, 0x20           ; LCD auto-increment write mode
    out (0x10), a
    ld c, 0x11           ; LCD data port in C for outi
    ld a, 3              ; 3 batches of 256 bytes = 768
.blitOuter:
    ld b, 0              ; 0 = 256 iterations for outi
.blitInner:
    outi                 ; out (C), (HL); HL++; B--
    jp nz, .blitInner    ; B wrapped to 0 means done with 256
    dec a
    jp nz, .blitOuter

    pop hl
    pop de
    pop bc
    pop af
    ei
    reti

; ============================================================
; clearPlanes — zero both plane buffers
; ============================================================
clearPlanes:
    ld hl, plane0
    ld de, plane0 + 1
    ld bc, 767
    ld (hl), 0
    ldir
    ld hl, plane1
    ld de, plane1 + 1
    ld bc, 767
    ld (hl), 0
    ldir
    ret
