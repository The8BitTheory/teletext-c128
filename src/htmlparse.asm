;the following is 6502 assembly, using the acme syntax


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
    sty screenline
    sty screencol
    sty offset_html
    sty offset_html+1
    sty offset_vram
    sty offset_vram+1
    sty current_color

; clear the vram output area
    lda #$20
    tax
-   sta screen_prep,x
    sta screen_prep+$100,x
    sta screen_prep+$200,x
    sta screen_prep+$300,x
    inx
    bne -

;parse the first character
findNextTag
    jsr readNextByte
    ldx eof
    beq +
    rts
    
+   cmp #$3c ; <
    bne +
    jmp parseTag   ; handle characters until '>' is found

+   cmp #$26 ; &
    bne +
    jsr parseSpecialCharacter ; output according to special char will happen

    cmp #13
    beq findNextTag

+   jsr outputCharacter ; if a regular character is found, put it on the screen

    jmp findNextTag

outputCharacter
    cmp #32         ;smaller than 32, skip
    bcc ++

;    cmp #128    ;larger than 127, skip
;    bcs ++

    pha

    ldy offset_vram    
    sta (address_vram),y

    lda address_vram+1
    clc
    adc #4
    sta address_vram+1

    lda current_color
    sta (address_vram),y

    lda address_vram+1
    sec
    sbc #4
    sta address_vram+1

    iny
    sty offset_vram
    bne +
    inc address_vram+1

+   pla
++  rts
    ;jmp bsout

parseTag:
    jsr readNextByte
    ldx eof
    beq +
    rts

+   cmp #$2f ; /
    bne +
    jmp parseEndTag

+   cmp #'d';
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

    jsr readNextByte

    ;d screen address to next line
    cmp #$64 ; d
    bne +
    jmp parse_end_tag_d

    ;a mark end of link
+   cmp #$61 ; a
    bne +
    jmp parse_end_tag_a

    ;ignore all other characters. skip 
+   jsr skipUntilTagEnd
    jmp findNextTag

skipUntilTagEnd:
    lda #$3e ; >
    sta skip_until
    jsr skipUntilCharacter
    rts

skipNrCharacters
-   jsr readNextByte
    dec skip_until
    bne -
    rts


skipUntilDigit:
    jsr readNextByte

    cmp #'9'+1
    bcs skipUntilDigit     ;larger than '9'. not a digit

    cmp #'0'
    bcc skipUntilDigit     ;smaller than '0'. not a digit

+   rts

parseTagLink:
    jsr skipUntilTagEnd
    jmp findNextTag

; the image tag is interesting because we get graphical characters from them
; eg <img src='./img/g1b70.gif'>
; or <img src='./img/g1sbl6f.gif'>
; where the g1 is graphic characters without spaces and b is black and 70 is the character
; (we might ignore the 'b' because it might be redundant from the parent span's class)
parseTagImg
    ; skip <img src='./img/g1b' -> 17 characters
    lda #17
    sta skip_until
    jsr skipNrCharacters

    cmp #'s'    ;separated graphics?
    beq .separateGraphics       ;not S means it's already a color. handle accordingly
    
    lda #160
    sta graphicsOffset
    jmp +

.separateGraphics
    lda #224
    sta graphicsOffset
    jsr readNextByte

; skip over color parsing.
; is redundant to parent span. saves us a lot of work
; skipUntilDigit works b/c graphic characters are uniquely different to colors (0x20 to 0x7f)
+    jsr skipUntilDigit
;+   jsr parseColor  ; stores foregroundcolor. A contains next byte (after color) after this

    ; parse graphic character (from 0x20 to 0x7f or so)
    jsr parseGraphicCharacter

    jsr outputCharacter

    ; skip until '>'
    jsr skipUntilTagEnd
    jmp findNextTag


; graphic characters go from 0x20 to 0x7f, leaving out 0x40-0x5f
; we have 64 contiguous and 64 separated ones
; 000-127 are latin characters
; 128-191 are contiguous graphic characters
; 192-255 are separated graphic characters
; <img src="./img/g1sbl28.gif">
parseGraphicCharacter
    ;.A holds first graphics character (hex-string)

    ;left character: 2-3: subtract 48 ($30), shift left 4 times / 6-7: subtract 64 (and shift)
    ; eg 0x20 (32 dec) -> 128 or 192 (offset)
    ;  "2" -> dec(50)-dec(48)=2-2=0
    ;  "0" -> dec(48)-dec(48)=0
    ;  "9" -> dec(57)-dec(48)=9
    ;  "a" -> dec(65)-dec(55)=10
    ;  "f" -> dec(70)-dec(55)=15

    sec
    sbc #48
    asl
    asl
    asl
    asl
    sta currentChar

    ;right character: 0-f. subtract 48 or 64, then OR with shifted left character
    ;add 128 (OR 128) for contiguous, or 192 for separated graphics
    jsr readNextByte
    ; if 0-9 -> subtract 48
    cmp #'9'+1
    bcs +   ;larger than 9. goto a-f handling
    sec
    sbc #48
    jmp ++

    ; if a-f -> subtract 55
    ; don't compare. assume it must be a-f for now
+   ;cmp #'z'+1
    sec
    sbc #55
    
++  ora currentChar
    ;sta currentChar

    ; now, subtract $20 if smaller than $40, else subtract  $40 (larger than $60)
    cmp #$40
    bcs +       ; larger than $40
    sec
    sbc #$20
    jmp ++

+   sec
    sbc #$40

++  ;sta currentChar
    clc
    adc graphicsOffset
    sta currentChar

    rts

; ARD colors
; w=white   #87
; y=yellow  #89
; m=magenta #77
; c=cyan    #67
; r=red     #82
; g=green   #71
; b=black   #66
; bl=blue   #66,#76 -> 142
; $77/119    cmp #'w' #$f
; $79/121   cmp #'y' #$d
; $6d/109   cmp #'m' #$b
; $63/99   cmp #'c' #$7
; $72/114   cmp #'r' #$8
; $67/103   cmp #'g' #$4
; $62/98  'b' #$0
;          'bl'   #$2

; higher nybble: foreground
; lower nybble: background
parseColorIntoX
    cmp #'w'
    bne +
    ldx #$f
    bne parseColorDone

+   cmp #'y'
    bne +
    ldx #$d
    bne parseColorDone

+   cmp #'m'
    bne +
    ldx #$b
    bne parseColorDone

+   cmp #'c'
    bne +
    ldx #$7
    bne parseColorDone

+   cmp #'r'
    bne +
    ldx #$8
    bne parseColorDone

+   cmp #'g'
    bne +
    ldx #$4
    bne parseColorDone

+   cmp #'b'
    bne invalidColor
    ; we have to check whether it's 'b' or 'bl'
    jsr readNextByte

    cmp #'l'
    beq setBlue
    
    bne setBlack

invalidColor
    ldx #$e
    bne parseColorDone

setBlue
    jsr readNextByte

    ldx #$2
    bne parseColorDone

setBlack
    ldx #$0

parseColorDone
    rts
    

parseTagNobr
    jsr skipUntilTagEnd ; skip until <nobr> is complete
    jmp findNextTag

parseTagDiv
    jsr beginningOfNextLine

    jsr skipUntilTagEnd
    jmp findNextTag

beginningOfNextLine
    lda #27
    jsr bsout
    lda #'J'
    jsr bsout
    rts

parseTagSpan
    ; skip until class attribute (which currently always comes first)
    lda #'c'
    sta skip_until
    jsr skipUntilCharacter

    lda #9
    sta skip_until
    jsr skipNrCharacters
    
    ; foreground color first
    jsr parseColorIntoX
    txa
    asl
    asl
    asl
    asl
    
    ;clear upper nybble of current_color, so we can OR cleanly
    tax

    lda current_color
    and #%00001111
    sta current_color

    txa
    ora current_color
    sta current_color

    lda #'g'
    sta skip_until
    jsr skipUntilCharacter

    jsr readNextByte

    jsr parseColorIntoX
    
    lda current_color
    and #%11110000
    sta current_color
    
    txa
    ora current_color
    sta current_color
    
    jsr skipUntilTagEnd
    jmp findNextTag

parse_end_tag_d:

    ;set screen address to next line
;    ldx screenline
;    clc
;    lda screen_line_offsets,x
;    adc offset_vram
;    sta offset_vram
;    bcc +
;    inc offset_vram+1

;+   inc screenline
    jsr skipUntilTagEnd
    jmp findNextTag

parse_end_tag_a:
    ;todo: mark end of link
    jsr skipUntilTagEnd
    jmp findNextTag
    
; this increases read address until the specified character is reached
;  after that, we continue regular text parsing, which might immediately
;  come up with the next non-text data, of course.
skipUntilCharacter:
    jsr readNextByte
    ldx eof
    beq +
    rts

+   cmp skip_until
    bne skipUntilCharacter

    rts


parseSpecialCharacter:
    jsr readNextByte
    ldx eof
    beq +
    rts

; we found an ampersand again. not a valid sequence. just print ampersand
+   cmp #'&'
    bne +
    jsr outputCharacter
    jmp parseSpecialCharacter

+   cmp #'n' ; n
    bne +
    lda #' '
    jmp doneSpecialCharacterHandling

+   cmp #'a' ; a
    bne +
    lda #99+32
    jmp doneSpecialCharacterHandling

+   cmp #'A' ; A
    bne +
    lda #96+32
    jmp doneSpecialCharacterHandling

+   cmp #'o' ; o
    bne +
    lda #100+32
    jmp doneSpecialCharacterHandling

+   cmp #'O' ; O
    bne +
    lda #97+32
    jmp doneSpecialCharacterHandling

+   cmp #'u' ; u
    bne +
    lda #101+32
    jmp doneSpecialCharacterHandling

+   cmp #'U' ; U
    bne +
    lda #98+32
    jmp doneSpecialCharacterHandling

+   cmp #'s' ; s
    bne +
    lda #102+32
    jmp doneSpecialCharacterHandling

+   cmp #'g' ; g
    bne +
    lda #'>'
    jmp doneSpecialCharacterHandling

+   cmp #'l' ; l
    bne +
    lda #'<'
    jmp doneSpecialCharacterHandling

;   no known sequence. just output regularly
    clc
+   rts


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

    ; if end of data is reached, write 1 to x
    ldx #1
    jmp readDone

+   ldy offset_html
    lda (address_html),y
    
    iny
    sty offset_html
    bne +
    inc address_html+1
    ; end of data not reached, write 0 to x
+   ldx #0


readDone
    stx eof
    rts


    
screen_line_offsets !word 0,80,160,240,320,400,480,560,640,720,800,880,960,1040,1120,1200,1280,1360,1440,1520,1600,1680,1760,1840,1920

current_color   !byte $f
skip_until      !byte 0
offset_html     !word 0
offset_vram     !word 0
screenline      !byte 0
screencol       !byte 0
eof             !byte 0
graphicsOffset  !byte 0
currentChar     !byte 0

; ARD colors
; w=white   #87
; b=black   #66
; bl=blue   #66,#76 -> 142
; y=yellow  #89
; m=magenta #77
; c=cyan    #67
; r=red     #82
; g=green   #71

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

