
setupBitmapMode
    
    rts

;x contains the column
;lineNr the textline (1-25)
displayPage
    ; write address to zeropage. was modified by html-parsing
    lda #<screen_prep
    sta address_vram
    lda #>screen_prep
    sta address_vram+1

    lda #$c0
    sta screensize
    lda #$3
    sta screensize+1
    
    lda #0
    sta offset_vram
    tay
    tax

-   ldy offset_vram
    lda (address_vram),y
    ;convert to charset entry
    sec
    sbc #32
    pha
    
    ;vmp takes y as HB, a as LB of destination-address
    ldy #0
    txa
    jsr vmp

    dec screensize
    bne +
    dec screensize+1
    bmi ++

+   inx
    cpx #39
    bne +
    ; colcount reached, do linebreak
    ldx #0

+   inc offset_vram
    bne -
    inc address_vram+1
    jmp -

++  rts

lineNr  !byte 0
;colcount   !byte 0
screensize !word 960

!source "src/vdcbasic.asm"