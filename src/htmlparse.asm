;the following is 6502 assembly, using the acme syntax

address_html = $fb
address_vram = $fd

parseHtml
    ldy #0
    sty offset_html
    sty offset_html+1
    sty offset_vram
    sty offset_vram+1

;parse the first character
parse_text:
    lda (address_html),y
    iny
    
    cmp #$3c ; <
    beq parse_tag

    cmp #$26 ; &
    beq parse_special_character

    jmp write_character

parse_tag:
    lda (address_html),y
    iny

    cmp #$2f ; /
    beq parse_end_tag

    ; this is only valid if a tag-name was parsed before. but we'll just go with that for now
    cmp #$20 ; space
    bne +
    jmp parse_attribute

+   cmp #$3e ; >
    beq parse_text

    cmp  #$61 ; a
    bne +
    jmp parse_link

    ;ignore all other characters
+   jmp parse_tag

parse_end_tag:
    lda (address_html),y
    iny

    ;d screen address to next line
    cmp #$64 ; d
    beq parse_end_tag_d

    ;a mark end of link
    cmp #$61 ; a
    beq parse_end_tag_a

    ;ignore all other characters. skip 

parse_end_tag_end:
    lda #$3e ; >
    sta skip_until
    jsr skip_until_character
    jmp parse_text

parse_end_tag_d:
    ;set screen address to next line
    ldx scanline
    clc
    lda screen_line_offsets,x
    adc offset_vram
    bcc +
    inc offset_vram+1

+   inc scanline
    jmp parse_end_tag_end

parse_end_tag_a:
    ;todo: mark end of link
    jmp parse_end_tag_end
    
skip_until_character:
    lda (address_html),y
    iny

    cmp skip_until
    bne skip_until_character

    rts

parse_special_character:
    lda (address_html),y
    iny

    cmp 'n' ; n
    bne +
    lda ' '
    jmp write_character

+   cmp 'a' ; a
    bne +
    ;lda 'ä'
    jmp write_character

+   cmp 'A' ; A
    bne +
    ;lda 'Ä'
    jmp write_character

+   cmp 'o' ; o
    bne +
    ;lda 'ö'
    jmp write_character

+   cmp 'O' ; O
    bne +
    ;lda 'Ö'
    jmp write_character

+   cmp 'u' ; u
    bne +
    ;lda 'ü'
    jmp write_character

+   cmp 'U' ; U
    bne +
    ;lda 'Ü'
    jmp write_character

+   cmp 's' ; s
    bne +
    ;lda 'ß'
    jmp write_character

+   cmp 'g' ; g
    bne +
    lda '>'
    jmp write_character

+   cmp 'l' ; l
    bne +
    lda '<'
    jmp write_character

parse_special_character_end:
    ;ignore all other &; sections
+   
    ;skip until ;
    lda #$3b ; ;
    jsr skip_until_character
    jmp parse_text

parse_attribute:

    rts

parse_attribute_class:
    rts

parse_attribute_src:
    rts

parse_link:
    rts

write_character:
    jsr bsout
    jmp parse_text

    
screen_line_offsets !word 0,80,160,240,320,400,480,560,640,720,800,880,960,1040,1120,1200,1280,1360,1440,1520,1600,1680,1760,1840,1920

color_fg !byte 0
color_bg !byte 0
parse_mode !byte 0
skip_until !byte 0
offset_html !word 0
offset_vram !word 0
scanline !byte 0

; special characters
; nbsp
; auml
; Auml
; ouml
; Ouml
; uuml
; Uuml
; szlig
; gt
; lt

