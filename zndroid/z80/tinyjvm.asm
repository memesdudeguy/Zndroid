; ============================================================
; tinyjvm.asm — TinyJ bytecode interpreter for Zndroid
;
; Opcode semantics match tools/tinyj_vm_ref.py (tested).
; Memory model: no GC. NEW bump-allocates from a fixed arena.
; ============================================================

; --- opcode constants (must match tinyj_compiler.py OP dict) ---
; Named for reference only; dispatch table uses literal values
TJOP_NOP            .equ 0x00
TJOP_ICONST         .equ 0x01
TJOP_ILOAD          .equ 0x02
TJOP_ISTORE         .equ 0x03
TJOP_IADD           .equ 0x04
TJOP_ISUB           .equ 0x05
TJOP_IMUL           .equ 0x06
TJOP_IDIV           .equ 0x07
TJOP_ICMP_LT        .equ 0x08
TJOP_ICMP_LE        .equ 0x09
TJOP_ICMP_GT        .equ 0x0A
TJOP_ICMP_GE        .equ 0x0B
TJOP_ICMP_EQ        .equ 0x0C
TJOP_ICMP_NE        .equ 0x0D
TJOP_IFEQ           .equ 0x0E
TJOP_GOTO           .equ 0x0F
TJOP_GETFIELD       .equ 0x10
TJOP_PUTFIELD       .equ 0x11
TJOP_INVOKEVIRTUAL  .equ 0x12
TJOP_RETURN         .equ 0x13
TJOP_IRETURN        .equ 0x14
TJOP_NEW            .equ 0x15
TJOP_LOAD_THIS      .equ 0x16
TJOP_SYSCALL        .equ 0x17
TJOP_HALT           .equ 0xFF

; --- VM state ---
vmPC:        .ds 2
vmSP:        .ds 2
opStack:     .ds 128
frameLocals: .ds 32
arenaPtr:    .ds 2
arenaTop:    .ds 2

; --- Call frame stack ---
MAX_FRAMES   .equ 8
frameStack:  .ds 40
frameDepth:  .db 0

; --- Bytecode storage ---
bytecodeBase: .ds 2

; --- Class metadata ---
classNFields: .db 0
classMethods: .ds 64

; ============================================================
; vmInit — initialize the VM state
; HL = arena ptr, BC = arena size, DE = method code ptr
; ============================================================
vmInit:
    ld (arenaPtr), hl
    push hl
    add hl, bc
    ld (arenaTop), hl
    pop hl
    ld (bytecodeBase), de
    ld hl, opStack + 128
    ld (vmSP), hl
    ld hl, frameLocals
    ld de, frameLocals + 1
    ld bc, 31
    ld (hl), 0
    ldir
    xor a
    ld (frameDepth), a
    ret

; ============================================================
; vmLoop — fetch/decode/dispatch
; ============================================================
vmLoop:
    call fetchByte
    ld hl, dispatchTable
    ld d, 0
    ld e, a
    add hl, de
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    ex de, hl
    jp (hl)

; ============================================================
; Opcode handlers
; ============================================================

op_NOP:
    jp vmLoop

op_ICONST:
    call fetchByte
    call signExtendA_HL
    call pushHL
    jp vmLoop

op_ILOAD:
    call fetchByte
    call localSlotAddr
    ld e, (hl)
    inc hl
    ld d, (hl)
    ex de, hl
    call pushHL
    jp vmLoop

op_ISTORE:
    call fetchByte
    push af
    call popHL
    push hl
    pop af
    call localSlotAddr
    pop de
    ld (hl), e
    inc hl
    ld (hl), d
    jp vmLoop

op_IADD:
    call popHL
    ex de, hl
    call popHL
    add hl, de
    call pushHL
    jp vmLoop

op_ISUB:
    call popHL
    ex de, hl
    call popHL
    or a
    sbc hl, de
    call pushHL
    jp vmLoop

op_IMUL:
    call popHL
    ex de, hl
    call popHL
    call mul16
    call pushHL
    jp vmLoop

op_IDIV:
    call popHL
    ex de, hl
    call popHL
    call div16
    call pushHL
    jp vmLoop

op_ICMP_LT:
    call popHL
    ex de, hl
    call popHL
    or a
    sbc hl, de
    jp m, icmpLT_true
    ld hl, 0
    jr icmpLT_done
icmpLT_true:
    ld hl, 1
icmpLT_done:
    call pushHL
    jp vmLoop

op_ICMP_LE:
    call popHL
    ex de, hl
    call popHL
    or a
    sbc hl, de
    jp m, icmpLE_true
    jr z, icmpLE_true
    ld hl, 0
    jr icmpLE_done
icmpLE_true:
    ld hl, 1
icmpLE_done:
    call pushHL
    jp vmLoop

op_ICMP_GT:
    call popHL
    ex de, hl
    call popHL
    or a
    sbc hl, de
    jp p, icmpGT_pos
    ld hl, 0
    jr icmpGT_done
icmpGT_pos:
    jr z, icmpGT_false
    ld hl, 1
    jr icmpGT_done
icmpGT_false:
    ld hl, 0
icmpGT_done:
    call pushHL
    jp vmLoop

op_ICMP_GE:
    call popHL
    ex de, hl
    call popHL
    or a
    sbc hl, de
    jp p, icmpGE_true
    ld hl, 0
    jr icmpGE_done
icmpGE_true:
    ld hl, 1
icmpGE_done:
    call pushHL
    jp vmLoop

op_ICMP_EQ:
    call popHL
    ex de, hl
    call popHL
    or a
    sbc hl, de
    jr z, icmpEQ_true
    ld hl, 0
    jr icmpEQ_done
icmpEQ_true:
    ld hl, 1
icmpEQ_done:
    call pushHL
    jp vmLoop

op_ICMP_NE:
    call popHL
    ex de, hl
    call popHL
    or a
    sbc hl, de
    jr nz, icmpNE_true
    ld hl, 0
    jr icmpNE_done
icmpNE_true:
    ld hl, 1
icmpNE_done:
    call pushHL
    jp vmLoop

op_IFEQ:
    call popHL
    ld a, h
    or l
    call fetchByte
    jp nz, vmLoop
    call signExtendA_HL
    ld de, (vmPC)
    add hl, de
    ld (vmPC), hl
    jp vmLoop

op_GOTO:
    call fetchByte
    call signExtendA_HL
    ld de, (vmPC)
    add hl, de
    ld (vmPC), hl
    jp vmLoop

op_LOAD_THIS:
    ld hl, frameLocals
    ld e, (hl)
    inc hl
    ld d, (hl)
    ex de, hl
    call pushHL
    jp vmLoop

op_GETFIELD:
    call fetchByte
    call popHL
    call fieldAddr
    ld e, (hl)
    inc hl
    ld d, (hl)
    ex de, hl
    call pushHL
    jp vmLoop

op_PUTFIELD:
    call fetchByte
    push af
    call popHL
    push hl
    pop af
    call fieldAddr
    ex de, hl
    call popHL
    ld a, l
    ld (de), a
    inc de
    ld a, h
    ld (de), a
    jp vmLoop

op_INVOKEVIRTUAL:
    call fetchByte
    call pushFrame
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    ld de, classMethods
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    ex de, hl
    ld (vmPC), hl
    ld hl, opStack + 128
    ld (vmSP), hl
    jp vmLoop

op_RETURN:
    call popFrame
    jp vmLoop

op_IRETURN:
    call popHL
    push hl
    call popFrame
    pop hl
    call pushHL
    jp vmLoop

op_NEW:
    call fetchByte
    call bumpAlloc
    call pushHL
    jp vmLoop

op_SYSCALL:
    call fetchByte
    call popHL
    jp vmLoop

op_HALT:
    ret

; ============================================================
; Helper functions
; ============================================================

fetchByte:
    push hl
    ld hl, (vmPC)
    ld a, (hl)
    inc hl
    ld (vmPC), hl
    pop hl
    ret

pushHL:
    push bc
    push af
    ld bc, (vmSP)
    dec bc
    dec bc
    ld (vmSP), bc
    ld a, l
    ld (bc), a
    inc bc
    ld a, h
    ld (bc), a
    pop af
    pop bc
    ret

popHL:
    push bc
    push af
    ld bc, (vmSP)
    ld a, (bc)
    ld l, a
    inc bc
    ld a, (bc)
    ld h, a
    inc bc
    ld (vmSP), bc
    pop af
    pop bc
    ret

signExtendA_HL:
    ld l, a
    ld h, 0
    bit 7, a
    jr z, signExt_done
    ld h, 0xFF
signExt_done:
    ret

localSlotAddr:
    add a, a
    ld l, a
    ld h, 0
    ld de, frameLocals
    add hl, de
    ret

fieldAddr:
    inc hl
    inc hl
    add a, a
    ld e, a
    ld d, 0
    add hl, de
    ret

bumpAlloc:
    ld l, a
    ld h, 0
    add hl, hl
    inc hl
    inc hl
    push de
    ld de, (arenaPtr)
    push de
    add hl, de
    ex de, hl
    ld hl, (arenaTop)
    or a
    sbc hl, de
    jr c, oom
    pop hl
    ld (arenaPtr), de
    pop de
    ret

oom:
    pop hl
    pop de
    ld hl, 0
    ret

pushFrame:
    push af
    push hl
    push de
    ld a, (frameDepth)
    cp MAX_FRAMES
    jr nc, frameOverflow
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    ld d, h
    ld e, l
    add hl, de
    ld de, frameStack
    add hl, de
    ld de, (vmPC)
    ld (hl), e
    inc hl
    ld (hl), d
    inc hl
    ld de, frameLocals
    ld (hl), e
    inc hl
    ld (hl), d
    inc hl
    ld a, (frameDepth)
    inc a
    ld (frameDepth), a
    push hl
    ld hl, frameLocals
    ld de, frameLocals + 1
    ld bc, 31
    ld (hl), 0
    ldir
    pop hl
frameOverflow:
    pop de
    pop hl
    pop af
    ret

popFrame:
    push af
    push hl
    push de
    ld a, (frameDepth)
    or a
    jr z, noFrame
    dec a
    ld (frameDepth), a
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    ld d, h
    ld e, l
    add hl, de
    ld de, frameStack
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    inc hl
    ld (vmPC), de
    inc hl
    inc hl
    ld hl, opStack + 128
    ld (vmSP), hl
noFrame:
    pop de
    pop hl
    pop af
    ret

; ============================================================
; mul16 — HL = HL * DE (low 16 bits of result)
; ============================================================
mul16:
    push bc
    ld b, h
    ld c, l
    ld hl, 0
    ld a, 16
mul16_loop:
    add hl, hl
    rl e
    rl d
    jr nc, mul16_skip
    add hl, bc
mul16_skip:
    dec a
    jr nz, mul16_loop
    pop bc
    ret

; ============================================================
; div16 — HL = HL / DE (integer, returns 0 on div-by-zero)
; ============================================================
div16:
    ld a, d
    or e
    ret z
    push bc
    ld b, h
    ld c, l
    ld hl, 0
    ld a, 16
div16_loop:
    rl c
    rl b
    adc hl, hl
    or a
    sbc hl, de
    jr nc, div16_setbit
    add hl, de
    jr div16_nextbit
div16_setbit:
    inc c
div16_nextbit:
    dec a
    jr nz, div16_loop
    ld h, b
    ld l, c
    pop bc
    ret

; ============================================================
; Dispatch table — 256 word entries
; ============================================================
dispatchTable:
    .dw op_NOP, op_ICONST, op_ILOAD, op_ISTORE
    .dw op_IADD, op_ISUB, op_IMUL, op_IDIV
    .dw op_ICMP_LT, op_ICMP_LE, op_ICMP_GT, op_ICMP_GE
    .dw op_ICMP_EQ, op_ICMP_NE, op_IFEQ, op_GOTO
    .dw op_GETFIELD, op_PUTFIELD, op_INVOKEVIRTUAL, op_RETURN
    .dw op_IRETURN, op_NEW, op_LOAD_THIS, op_SYSCALL
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_NOP
    .dw op_NOP, op_NOP, op_NOP, op_HALT