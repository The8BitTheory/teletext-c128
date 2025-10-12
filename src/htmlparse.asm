;the following is 6502 assembly, using the acme syntax

address_html = $fb
address_vram = $fd

; ------------------
; ard-text
; ---------------
; div can be ignored -> just skip until >
; </div> leads to linebreak
; all other end-tags "/"" can be ingored -> just skip until >
; <span get fgX and bgX, ignore all other attributes
; <nobr can be ignored
; <img src attribute leads to next output character
; > always leads to character-parsing mode


parseHtml
    ldy #0
    sty offset_html
    sty offset_html+1
    sty offset_vram
    sty offset_vram+1

;parse the first character
findNextTag
    jsr readNextByte
    
    cmp #$3c ; <
    bne +
    jmp parseTag   ; handle characters until '>' is found

+   cmp #$26 ; &
    bne +
    jsr parseSpecialCharacter ; output according to special char will happen

+   jsr bsout ; if a regular character is found, put it on the screen

    jmp findNextTag

parseTag:
    jsr readNextByte

    cmp #$2f ; /
    bne +
    jmp parseEndTag

+   sta current_tag

    cmp #'d';
    bne +
    jmp parseTagDiv

    ; this is only valid if a tag-name was parsed before. but we'll just go with that for now
    ; should be handled inside the specific tag routines (ie for div, for span, etc)
;+   cmp #$20 ; space
;    bne +
;    jmp parseAttribute

    ; should be handled inside the specific tag routines
;+   cmp #$3e ; >
;    bne +
;    jmp findNextTag

+   cmp  #$61 ; a
    bne +
    jmp parseTagLink

+   cmp #'s'
    bne +
    jmp parseTagSpan

+   cmp #'n'
    bne +
    jmp parseTagNobr

+   cmp #'i'
    bne +
    jmp parseTagImg

    ;ignore all other tags and go until the end
+   jsr skipUntilTagEnd
    jmp parseTag

parseEndTag:

    ; clear current_tag information, so we don't run into any side-effects
    ; .a contains '/' at this point
    lda current_tag
    pha
    lda #0
    sta current_tag
    pla

    ;d screen address to next line
    cmp #$64 ; d
    beq parse_end_tag_d

    ;a mark end of link
    cmp #$61 ; a
    beq parse_end_tag_a

    ;ignore all other characters. skip 
    jsr skipUntilTagEnd
    jmp findNextTag

skipUntilTagEnd:
    lda #$3e ; >
    sta skip_until
    jsr skipUntilCharacter
    rts

parseTagLink:
    jsr skipUntilTagEnd
    jmp findNextTag

parseTagImg
    jsr skipUntilTagEnd
    jmp findNextTag

parseTagNobr
    jsr skipUntilTagEnd ; skip until <nobr> is complete
    jmp findNextTag

parseTagDiv
    jsr skipUntilTagEnd
    jmp findNextTag

parseTagSpan
    jsr skipUntilTagEnd
    jmp findNextTag

parse_end_tag_d:
    lda #$d
    jsr bsout

    ;set screen address to next line
    ldx scanline
    clc
    lda screen_line_offsets,x
    adc offset_vram
    bcc +
    inc offset_vram+1

+   inc scanline
    jsr skipUntilTagEnd
    rts

parse_end_tag_a:
    ;todo: mark end of link
    jsr skipUntilTagEnd
    jmp findNextTag
    
; this increases read address until the specified character is reached
;  after that, we continue regular text parsing, which might immediately
;  come up with the next non-text data, of course.
skipUntilCharacter:
    jsr readNextByte

    cmp skip_until
    bne skipUntilCharacter

    rts


parseSpecialCharacter:
    jsr readNextByte
 
    cmp #'n' ; n
    bne +
    lda #' '
    jmp doneSpecialCharacterHandling

+   cmp #'a' ; a
    bne +
    ;lda 'ä'
    jmp doneSpecialCharacterHandling

+   cmp #'A' ; A
    bne +
    ;lda 'Ä'
    jmp doneSpecialCharacterHandling

+   cmp #'o' ; o
    bne +
    ;lda 'ö'
    jmp doneSpecialCharacterHandling

+   cmp #'O' ; O
    bne +
    ;lda 'Ö'
    jmp doneSpecialCharacterHandling

+   cmp #'u' ; u
    bne +
    ;lda 'ü'
    jmp doneSpecialCharacterHandling

+   cmp #'U' ; U
    bne +
    ;lda 'Ü'
    jmp doneSpecialCharacterHandling

+   cmp #'s' ; s
    bne +
    ;lda 'ß'
    jmp doneSpecialCharacterHandling

+   cmp #'g' ; g
    bne +
    lda #'>'
    jmp doneSpecialCharacterHandling

+   cmp #'l' ; l
    bne +
    lda #'<'
    jmp doneSpecialCharacterHandling

;   no known sequence. just skip
+   lda #$3b ; ;
    sta skip_until
    jmp skipUntilCharacter


doneSpecialCharacterHandling
    pha
    lda #';' ; ;
    sta skip_until
    jsr skipUntilCharacter
    pla
    rts
    

skipUntilQuote
    lda #'"'    ; load quote "
    jsr skipUntilCharacter
    jmp findNextTag

parseAttribute:

    rts

parseAttribute_class:
    rts

parseAttribute_src:
    rts


parseDone:
    rts


readNextByte
    dec wic64_response_size
    bne +
    dec wic64_response_size+1
    bpl +

    rts

+   lda (address_html),y
    iny
    bne +
    inc address_html+1

+   rts


    
screen_line_offsets !word 0,80,160,240,320,400,480,560,640,720,800,880,960,1040,1120,1200,1280,1360,1440,1520,1600,1680,1760,1840,1920

color_fg    !byte 0
color_bg    !byte 0
current_tag !byte 0
skip_until  !byte 0
offset_html !word 0
offset_vram !word 0
scanline    !byte 0

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

