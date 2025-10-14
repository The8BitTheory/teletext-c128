; include the wic64 header file containing the macro definitions

!source "wic64.h"

k_primm = $ff7d
k_getin = $eeeb
;k_pokebank = $02af  ;.a=value to write, .x=bank, .y=offset from address in $02b9
;strout = $B47C
bsout = $ffd2

address_html = $fb
address_vram = $fd


;data_response = $2400

; -- parsing only text, skipping over graphic characters (textmode)
;slow:127
;fast:69

; -- with graphic character parsing (textmode)
;slow vdc:389
;fast vdc:102
;slow vic:156

; vdc charset: 16x8 pixels per character. 640x200 resolution. top-line: user input
; 40x24 characters text screen (960 bytes)
; 40x24 bytes attribute ram (960 bytes)
; -- 

*= $1c01
    !byte $11,$1c,$e9,$07,$fe,$25,$3a,$9e,$37,$31,$38,$38,$3a,$fe,$26,$00,$00,$00

*= $1c14

main:
; disable basic rom. bank 0, kernal and I/O enabled
    lda #%00001110
    sta $ff00

;    jsr k_primm
;!pet "Detecting and querying firmware",0
    jsr detectAndFirmware
;    jsr k_primm
;!pet "Querying IP",0
    jsr getIp

    ; set vdc to 64k of vram. reg 28 OR 16
    ldx #28
    jsr vdc_reg_X_to_A
    ora #16
    jsr A_to_vdc_reg_X

    ; set bitmap mode on: reg 25 OR 128
    ldx #25
    jsr vdc_reg_X_to_A
    ora #128
    jsr A_to_vdc_reg_X

    ; set nr of refresh cycles to zero: reg 36=0
    ldx #36
    lda #0
    jsr A_to_vdc_reg_X

    ; copy charset to vram
    ; source address in RAM
    lda #<charset
    sta arg1
    lda #>charset
    sta arg1+1

    ; target address in VRAM ($e000 - at 56 kb)
    lda #0
    sta arg2
    lda #$e0
    sta arg2+1

    lda #<charset_size
    sta arg3
    lda #>charset_size
    sta arg3+1

    jsr rtv

; setup charset for vmp
    lda arg2
    sta arg1
    lda arg2+1
    sta arg1+1

    lda #2
    sta arg2

    lda #9
    sta arg3

    jsr vcs

; clear screen-ram
    jsr remember_mem_conf
    ; set parameters: vram address, value, byte count to fill
    lda #0
    sta arg1
    sta arg1+1

    sta arg2
    sta arg2+1
    
    ; 16000 bytes to fill
    lda #$80
    sta arg3+1
    lda #$03
    sta arg3

    ldy arg3+1
    jsr vmf_execute

    ; 16000,$0f,2000
    jsr remember_mem_conf
    lda #$80
    sta arg1+1
    lda #$03
    sta arg1

    lda #$0f
    sta arg2+1
    lda #0
    sta arg2

    lda #$d0
    sta arg3+1
    lda #$7
    sta arg3

    ldy arg3+1
    jsr vmf_execute

    jsr requestPage

endOfProgram
    lda #%00000000
    sta $ff00

    ; set vdc to 16k of vram. reg 28 AND 239
    ldx #28
    jsr vdc_reg_X_to_A
    and #%11101111
    jsr A_to_vdc_reg_X

    ; set bitmap mode off: reg 25 AND 127
    ldx #25
    jsr vdc_reg_X_to_A
    and #%01111111
    jsr A_to_vdc_reg_X

    lda #5
    jsr bsout

    lda #147      ; clear screen
    jsr bsout

    rts

getIp
    +wic64_execute request, response        ; send request and receive the response
    bcs timeout                             ; carry set => timeout occurred
    bne error                               ; zero flag clear => error status code in accumulator
    
    lda response
    beq +

    jsr k_primm
; reserve 16 bytes of memory for the response
response: !fill 16, $ea
    
    lda #$0d
    jsr bsout
    ;lda #$0a
    ;jsr bsout

+   rts

requestPage:
    +wic64_execute orf_request, data_response
    bcs timeout
    bne error

    lda #<data_response
    sta address_html
    lda #>data_response
    sta address_html+1

    lda #<screen_prep
    sta address_vram
    lda #>screen_prep
    sta address_vram+1

    jsr parseHtml
    jsr displayPage

    jmp handleInputClear

timeout:
    jsr k_primm
    !pet "?timeout error", $00
    rts

error:
    ; get the error message of the last request
    +wic64_execute status_request, status_response
    bcs timeout

    jsr k_primm
; reserve 40 bytes of memory for the status message
status_response: !fill 40, 0
    rts

detectAndFirmware
    +wic64_detect                           ; detect wic64 device and firmware
    bcs device_not_present                  ; carry set => wic64 not present or unresponsive
    lda wic64_status
    bne legacy_firmware                     ; zero flag clear => legacy firmware detected
    rts

device_not_present:                         ; print appropriate error message...
    jsr k_primm
    !pet "?device not present or unresponsive error", $00
    rts

legacy_firmware:
    jsr k_primm
    !pet "?legacy firmware error", $00
    rts

handleInputClear
    lda #19 ;home
    jsr bsout

handleInput
    jsr k_getin
    ldx digit
    cmp minInput,x ; first digit needs to be 1-9, 2nd and 3rd can be 0-9
    bcc handleInput
    cmp #'9'+1
    bcc evalInput
    cmp #'X'
    bne handleInput
    jmp endOfProgram

evalInput
    ;store digit to input
    ldx digit
    sta input,x
    ; increase digit
    inc digit

    jsr bsout

    ; if max digit reached (3rd digit), bring cursor to start of line and do request
    ldx digit
    cpx #3
    bne handleInput

    ldx #0
    stx digit
    lda #$d
    jsr bsout
;    lda #27
;    jsr bsout
;    lda #'J'
;    jsr bsout
    lda #147      ; clear screen
    jsr bsout

    jmp requestPage


; define request to get the current ip address
request !byte "R", WIC64_GET_IP, $00, $00

; define the request for the status message
status_request: !byte "R", WIC64_GET_STATUS_MESSAGE, $01, $00, $01

orf_request:    !byte "R",WIC64_HTTP_GET, <orf_url_size, >orf_url_size
;orf_url:        !text "https://afeeds.orf.at/teletext/api/v2/mobile/channels/orf1/pages/100"
orf_url:        !text "https://www.ard-text.de/page_only.php?page="
input           !text '1','0','0'
orf_url_size = * - orf_url

digit           !byte 0
minInput        !byte '1','0','0'

; include the actual wic64 routines
!source "wic64.asm"
!source "src/htmlparse.asm"
!source "src/vdcdisplay.asm"

;$24c7 - 9415

screen_prep !byte 0

;$2cc7 - 11463
data_response = screen_prep+2048


charset
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$fc,$7f,$fc,$7f,$fc,$7f,$fc,$7f,$ff,$ff
!byte $fc,$7f,$ff,$ff,$ff,$ff,$ff,$ff,$83,$83,$e3,$e3,$8f,$8f,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$e3,$8f,$e3,$8f,$00,$01,$e3,$8f
!byte $e3,$8f,$00,$01,$e3,$8f,$e3,$8f,$ff,$ff,$fc,$7f,$80,$03,$1c,$71
!byte $1c,$7f,$c0,$01,$1c,$71,$80,$01,$fc,$7f,$ff,$ff,$ff,$ff,$83,$e3
!byte $39,$87,$82,$1f,$f8,$41,$e1,$9c,$c7,$c1,$ff,$ff,$ff,$ff,$ff,$ff
!byte $c0,$1f,$cf,$9f,$c2,$3f,$e0,$3f,$8f,$83,$80,$11,$ff,$ff,$ff,$ff
!byte $ff,$ff,$fc,$1f,$ff,$1f,$fc,$7f,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$fc,$1f,$f0,$ff,$f1,$ff,$f1,$ff,$f0,$ff,$fc,$1f
!byte $ff,$ff,$ff,$ff,$ff,$ff,$f8,$3f,$ff,$0f,$ff,$8f,$ff,$8f,$ff,$0f
!byte $f8,$3f,$ff,$ff,$ff,$ff,$ff,$ff,$9c,$73,$84,$43,$e0,$0f,$f0,$1f
!byte $c0,$07,$8c,$63,$fc,$7f,$ff,$ff,$ff,$ff,$ff,$ff,$fc,$7f,$fc,$7f
!byte $c0,$07,$fc,$7f,$fc,$7f,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$f8,$7f,$fc,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$e0,$07,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$f8,$7f,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$e3,$ff,$c3,$ff,$0f,$fc,$3f,$f0,$ff,$c3,$ff,$c7,$ff
!byte $ff,$ff,$e0,$03,$c3,$e1,$c3,$e1,$c3,$e1,$c3,$e1,$c3,$e1,$e0,$03
!byte $ff,$ff,$ff,$ff,$fe,$1f,$e0,$1f,$fe,$1f,$fe,$1f,$fe,$1f,$fe,$1f
!byte $fe,$1f,$ff,$ff,$ff,$ff,$e0,$03,$c7,$e1,$ff,$e1,$ff,$03,$f8,$3f
!byte $e1,$ff,$c0,$01,$ff,$ff,$ff,$ff,$c0,$03,$ff,$e1,$ff,$e1,$fc,$03
!byte $ff,$f1,$ff,$e1,$c0,$03,$ff,$ff,$ff,$ff,$ff,$c1,$ff,$07,$fc,$1f
!byte $f0,$7f,$c3,$e1,$c0,$01,$ff,$e1,$ff,$ff,$ff,$ff,$c0,$03,$c7,$ff
!byte $c7,$ff,$c0,$03,$ff,$f1,$c7,$c1,$f0,$07,$ff,$ff,$ff,$ff,$ff,$1f
!byte $fc,$3f,$f0,$ff,$c0,$07,$c3,$e1,$c3,$e1,$e0,$07,$ff,$ff,$ff,$ff
!byte $00,$01,$ff,$c3,$ff,$87,$fe,$1f,$f8,$7f,$e1,$ff,$c3,$ff,$ff,$ff
!byte $ff,$ff,$f8,$0f,$c3,$e1,$c3,$e1,$f0,$07,$e3,$e3,$c3,$e1,$f0,$07
!byte $ff,$ff,$ff,$ff,$e0,$03,$c7,$f1,$c7,$f1,$e0,$01,$ff,$0f,$fc,$3f
!byte $f8,$7f,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$f8,$7f,$f8,$7f,$ff,$ff
!byte $ff,$ff,$f8,$7f,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$f8,$7f,$f8,$7f
!byte $ff,$ff,$ff,$ff,$f8,$7f,$fc,$ff,$ff,$ff,$ff,$e1,$ff,$07,$f8,$3f
!byte $c1,$ff,$f0,$7f,$fe,$0f,$ff,$c1,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $c0,$03,$ff,$ff,$c0,$03,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$87,$ff
!byte $e0,$ff,$fc,$1f,$ff,$83,$fe,$0f,$f0,$7f,$83,$ff,$ff,$ff,$ff,$ff
!byte $e0,$0f,$c7,$e3,$c7,$c3,$ff,$0f,$fc,$3f,$f8,$7f,$ff,$ff,$f8,$7f
!byte $ff,$ff,$e0,$03,$87,$f1,$18,$11,$11,$91,$11,$91,$18,$01,$87,$ff
!byte $e0,$03,$ff,$ff,$f8,$3f,$e1,$0f,$87,$c3,$1f,$f1,$00,$01,$1f,$f1
!byte $1f,$f1,$ff,$ff,$ff,$ff,$80,$07,$8f,$e1,$8f,$f1,$80,$07,$8f,$e1
!byte $8f,$e1,$80,$07,$ff,$ff,$ff,$ff,$f0,$03,$c3,$f1,$8f,$ff,$8f,$ff
!byte $8f,$ff,$c3,$f1,$f0,$03,$ff,$ff,$ff,$ff,$80,$0f,$8f,$e3,$8f,$f1
!byte $8f,$f1,$8f,$f1,$8f,$e3,$80,$0f,$ff,$ff,$ff,$ff,$80,$01,$8f,$ff
!byte $8f,$ff,$80,$0f,$8f,$ff,$8f,$ff,$80,$01,$ff,$ff,$ff,$ff,$80,$01
!byte $8f,$ff,$8f,$ff,$80,$1f,$8f,$ff,$8f,$ff,$8f,$ff,$ff,$ff,$ff,$ff
!byte $c0,$03,$8f,$f1,$8f,$ff,$8f,$ff,$8f,$01,$8f,$f1,$c0,$03,$ff,$ff
!byte $ff,$ff,$8f,$f1,$8f,$f1,$8f,$f1,$80,$01,$8f,$f1,$8f,$f1,$8f,$f1
!byte $ff,$ff,$ff,$ff,$c0,$03,$fc,$7f,$fc,$7f,$fc,$7f,$fc,$7f,$fc,$7f
!byte $c0,$03,$ff,$ff,$ff,$ff,$ff,$f1,$ff,$f1,$ff,$f1,$ff,$f1,$ff,$f1
!byte $8f,$f1,$c0,$03,$ff,$ff,$ff,$ff,$8f,$c1,$8f,$0f,$8c,$3f,$81,$ff
!byte $80,$3f,$8f,$07,$8f,$e1,$ff,$ff,$ff,$ff,$8f,$ff,$8f,$ff,$8f,$ff
!byte $8f,$ff,$8f,$ff,$8f,$ff,$80,$01,$ff,$ff,$ff,$ff,$87,$e1,$81,$81
!byte $88,$11,$8c,$71,$8f,$f1,$8f,$f1,$8f,$f1,$ff,$ff,$ff,$ff,$87,$f1
!byte $83,$f1,$80,$f1,$8c,$31,$8f,$01,$8f,$c1,$8f,$f1,$ff,$ff,$ff,$ff
!byte $c0,$03,$8f,$f1,$8f,$f1,$8f,$f1,$8f,$f1,$8f,$f1,$c0,$03,$ff,$ff
!byte $ff,$ff,$80,$03,$8f,$f1,$8f,$f1,$80,$03,$8f,$ff,$8f,$ff,$8f,$ff
!byte $ff,$ff,$ff,$ff,$c0,$03,$8f,$f1,$8f,$f1,$8f,$f1,$8f,$f1,$8f,$11
!byte $c0,$03,$ff,$c7,$ff,$ff,$80,$03,$8f,$f1,$8f,$f1,$80,$03,$8e,$1f
!byte $8f,$83,$8f,$e1,$ff,$ff,$ff,$ff,$c0,$03,$87,$ff,$8f,$ff,$c0,$03
!byte $ff,$f1,$ff,$f1,$c0,$03,$ff,$ff,$ff,$ff,$00,$01,$fc,$7f,$fc,$7f
!byte $fc,$7f,$fc,$7f,$fc,$7f,$fc,$7f,$ff,$ff,$ff,$ff,$8f,$f1,$8f,$f1
!byte $8f,$f1,$8f,$f1,$8f,$f1,$8f,$f1,$c0,$03,$ff,$ff,$ff,$ff,$1f,$f1
!byte $1f,$f1,$8f,$e3,$c7,$c7,$f1,$1f,$f8,$3f,$fc,$7f,$ff,$ff,$ff,$ff
!byte $1f,$f1,$1f,$f1,$1c,$71,$1c,$71,$10,$11,$83,$83,$8f,$e3,$ff,$ff
!byte $ff,$ff,$1f,$f1,$c3,$87,$f0,$1f,$fc,$7f,$f0,$1f,$c3,$87,$1f,$f1
!byte $ff,$ff,$ff,$ff,$1f,$f1,$8f,$e3,$c3,$87,$f0,$1f,$fc,$7f,$fc,$7f
!byte $fc,$7f,$ff,$ff,$ff,$ff,$80,$01,$ff,$c3,$ff,$0f,$fc,$7f,$e1,$ff
!byte $c7,$ff,$80,$01,$ff,$ff,$ff,$ff,$f8,$3f,$f9,$ff,$f9,$ff,$f9,$ff
!byte $f9,$ff,$f9,$ff,$f9,$ff,$f8,$3f,$ff,$ff,$3f,$ff,$8f,$ff,$e3,$ff
!byte $f8,$ff,$fe,$3f,$ff,$8f,$ff,$e3,$ff,$f9,$ff,$ff,$f8,$3f,$ff,$3f
!byte $ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$ff,$3f,$f8,$3f,$fe,$ff,$f8,$3f
!byte $e1,$0f,$87,$c3,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$01
!byte $ff,$ff,$8f,$ff,$e3,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$07,$ff,$e3,$00,$03,$1f,$e3
!byte $c0,$01,$ff,$ff,$ff,$ff,$1f,$ff,$1f,$ff,$10,$07,$0f,$e3,$1f,$e3
!byte $1f,$e3,$00,$07,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$c0,$03,$0f,$ff
!byte $1f,$ff,$8f,$ff,$e0,$03,$ff,$ff,$ff,$ff,$ff,$e3,$ff,$e3,$80,$23
!byte $1f,$c3,$1f,$e3,$1f,$e3,$80,$03,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $80,$03,$1f,$c3,$00,$03,$0f,$ff,$80,$07,$ff,$ff,$ff,$ff,$f0,$03
!byte $e3,$ff,$e3,$ff,$00,$1f,$e3,$ff,$e3,$ff,$e3,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$80,$07,$1f,$87,$1f,$87,$80,$07,$ff,$c7,$80,$0f
!byte $ff,$ff,$1f,$ff,$1f,$ff,$10,$07,$0f,$e3,$1f,$e3,$1f,$e3,$1f,$e3
!byte $ff,$ff,$ff,$ff,$e1,$ff,$ff,$ff,$e1,$ff,$f1,$ff,$f1,$ff,$f1,$ff
!byte $80,$3f,$ff,$ff,$ff,$ff,$ff,$87,$ff,$ff,$fe,$07,$ff,$c7,$ff,$c7
!byte $ff,$c7,$1f,$c7,$80,$0f,$ff,$ff,$1f,$ff,$1f,$ff,$1e,$07,$00,$7f
!byte $01,$ff,$1c,$1f,$1f,$87,$ff,$ff,$ff,$ff,$80,$ff,$f8,$ff,$f8,$ff
!byte $f8,$ff,$f8,$ff,$f8,$ff,$00,$07,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $00,$83,$1c,$71,$1c,$71,$1c,$71,$1c,$71,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$10,$07,$0f,$e3,$1f,$e3,$1f,$e3,$1f,$e3,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$80,$07,$1f,$e3,$1f,$e3,$1f,$e3,$80,$07,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$00,$0f,$0f,$c7,$0f,$c7,$00,$0f,$1f,$ff
!byte $1f,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$80,$07,$1f,$87,$1f,$87,$80,$07
!byte $ff,$c7,$fe,$03,$ff,$ff,$ff,$ff,$ff,$ff,$18,$03,$03,$ff,$1f,$ff
!byte $1f,$ff,$1f,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$80,$07,$1f,$ff
!byte $80,$03,$ff,$e3,$80,$07,$ff,$ff,$ff,$ff,$e3,$ff,$e3,$ff,$00,$1f
!byte $e3,$ff,$e3,$ff,$e3,$ff,$f0,$03,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $1f,$e3,$1f,$e3,$1f,$c3,$1f,$83,$80,$23,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$0f,$e1,$c7,$c7,$f3,$9f,$f8,$3f,$fc,$7f,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$1f,$f1,$1c,$71,$0c,$61,$c4,$47,$e3,$8f,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$07,$c1,$e0,$0f,$f8,$1f,$c3,$87,$0f,$e1
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$0f,$c3,$c7,$0f,$f0,$3f,$f8,$7f
!byte $f1,$ff,$e3,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$03,$fc,$1f,$f0,$ff
!byte $87,$ff,$00,$03,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff
!byte $00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff,$00,$ff,$00,$ff
!byte $00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff,$00
!byte $ff,$00,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00
!byte $00,$00,$00,$00,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff
!byte $ff,$ff,$00,$ff,$00,$ff,$00,$ff,$ff,$00,$ff,$00,$ff,$00,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00
!byte $ff,$ff,$ff,$ff,$ff,$ff,$00,$00,$00,$00,$00,$00,$ff,$00,$ff,$00
!byte $ff,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00
!byte $00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$00,$7f,$00,$7f,$00,$7f
!byte $00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff,$00
!byte $ff,$00,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff,$00,$ff
!byte $00,$ff,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff
!byte $00,$ff,$00,$ff,$ff,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff
!byte $00,$ff,$00,$ff,$00,$ff,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff
!byte $ff,$ff,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff
!byte $00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff
!byte $00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$ff,$00,$ff,$00
!byte $ff,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00
!byte $00,$00,$00,$00,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff,$00,$ff,$00,$00,$ff,$00,$ff
!byte $00,$ff,$00,$ff,$00,$ff,$00,$ff,$ff,$00,$ff,$00,$ff,$00,$00,$ff
!byte $00,$ff,$00,$ff,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00
!byte $00,$ff,$00,$ff,$00,$ff,$00,$00,$00,$00,$00,$00,$ff,$00,$ff,$00
!byte $ff,$00,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00
!byte $00,$00,$00,$00,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff
!byte $00,$00,$00,$00,$00,$00,$00,$ff,$00,$ff,$00,$ff,$ff,$00,$ff,$00
!byte $ff,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$00,$ff,$00,$ff,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$00,$ff,$00,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff,$00
!byte $ff,$00,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00
!byte $ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$00,$ff,$00,$ff,$00,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff
!byte $00,$ff,$00,$ff,$ff,$00,$ff,$00,$ff,$00,$00,$ff,$00,$ff,$00,$ff
!byte $00,$ff,$00,$ff,$00,$ff,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00
!byte $ff,$00,$00,$ff,$00,$ff,$00,$ff,$ff,$00,$ff,$00,$ff,$00,$00,$00
!byte $00,$00,$00,$00,$00,$ff,$00,$ff,$00,$ff,$ff,$00,$ff,$00,$ff,$00
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00
!byte $ff,$00,$00,$ff,$00,$ff,$00,$ff,$ff,$00,$ff,$00,$ff,$00,$ff,$00
!byte $ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00
!byte $ff,$00,$ff,$00,$ff,$00,$00,$00,$00,$00,$00,$00,$ff,$00,$ff,$00
!byte $ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00
!byte $00,$00,$00,$00,$ff,$00,$ff,$00,$ff,$00,$00,$7f,$00,$7f,$00,$7f
!byte $00,$00,$00,$00,$00,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00
!byte $ff,$00,$00,$00,$00,$00,$00,$00,$ff,$00,$ff,$00,$ff,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$00,$ff,$00,$ff,$00
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00,$00,$00
!byte $00,$00,$00,$7f,$00,$7f,$00,$7f,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00
!byte $00,$00,$00,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$ff,$ff,$ff,$ff,$ff
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff
!byte $ff,$ff,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff
!byte $00,$ff,$00,$ff,$00,$00,$00,$00,$00,$00,$00,$ff,$00,$ff,$00,$ff
!byte $00,$ff,$00,$ff,$00,$ff,$00,$00,$00,$00,$00,$00,$ff,$00,$ff,$00
!byte $ff,$00,$00,$ff,$00,$ff,$00,$ff,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$ff,$00,$ff,$00,$ff,$00,$00,$00,$00,$00,$00
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$00,$ff,$00,$ff,$00,$00,$00,$00,$00
!byte $00,$00,$00,$ff,$00,$ff,$00,$ff,$ff,$00,$ff,$00,$ff,$00,$00,$00
!byte $00,$00,$00,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00,$ff,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$00,$ff,$00
!byte $ff,$00,$00,$00,$00,$00,$00,$00,$ff,$ff,$ff,$ff,$ff,$ff,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7f,$00,$7f,$00,$7f
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$ff,$00,$ff,$00
!byte $ff,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff
!byte $ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81,$ff,$81
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff
!byte $ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$81,$ff
!byte $81,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $81,$ff,$81,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $81,$ff,$81,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81,$ff,$81,$ff
!byte $ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81,$ff,$81,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$81,$ff
!byte $81,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff
!byte $81,$ff,$81,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81,$ff,$81
!byte $ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81,$ff,$81,$ff
!byte $ff,$ff,$81,$81,$81,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$81,$ff,$81,$ff
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$81,$ff,$81,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $81,$ff,$81,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$81,$ff,$81,$ff
!byte $ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$81,$ff,$81
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff
!byte $ff,$81,$ff,$81,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81,$ff,$81
!byte $ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$81,$ff,$81,$ff
!byte $ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$81,$ff,$81
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$81,$81
!byte $81,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$ff,$ff
!byte $ff,$ff,$81,$81,$81,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$ff
!byte $ff,$ff,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $81,$ff,$81,$ff,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$81,$ff,$81,$ff
!byte $ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81,$81,$81,$81,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81,$81,$81,$81
!byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$81,$81
!byte $81,$81,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$ff,$81,$ff,$81,$ff,$ff,$ff,$81,$ff,$81
!byte $ff,$ff,$81,$81,$81,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$81,$ff,$81,$ff
!byte $ff,$ff,$81,$81,$81,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$ff,$81
!byte $ff,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff
!byte $81,$81,$81,$81,$ff,$ff,$81,$81,$81,$81,$ff,$ff,$81,$81,$81,$81
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00
charset_size = * - charset


