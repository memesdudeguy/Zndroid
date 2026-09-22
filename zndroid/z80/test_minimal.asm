; Minimal test - just draw "Hello" to see if drawing works
#include "kernel.inc"

    .db "KEXC"
    .db KEXC_ENTRY_POINT
    .dw start
    .db KEXC_STACK_SIZE
    .dw 20
    .db KEXC_NAME
    .dw appName
    .db KEXC_HEADER_END

appName:
    .db "Test", 0

start:
    pcall(getLcdLock)
    pcall(getKeypadLock)
    pcall(allocScreenBuffer)
    pcall(clearBuffer)

    ; Draw "Hello" at position (0,0)
    kld(hl, helloStr)
    ld de, 0
    pcall(drawStr)

    ; Push to LCD
    pcall(fastCopy)

    ; Wait for any key
.loop:
    pcall(flushKeys)
    pcall(waitKey)
    cp kMode
    jr nz, .loop

    ; Exit
    pcall(freeScreenBuffer)
    ret

helloStr:
    .db "Hello Zndroid", 0
