
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

    lda #147      ; clear screen
    jsr bsout

    lda #$d ;cr - go to second line for output (first line is for user input and feedback)
    jsr bsout
    
    lda #39
    sta colcount

    ldy #0

-   lda (address_vram),y
    jsr bsout

    dec screensize
    bne +
    dec screensize+1
    bmi ++

+   dec colcount
    bne +
    ; colcount reached, do linebreak
    lda #$d
    jsr bsout
    lda #27
    jsr bsout
    lda #'J'
    jsr bsout
    lda #39
    sta colcount

+   iny
    bne -
    inc address_vram+1
    jmp -

++  rts

colcount   !byte 39
screensize !word 960