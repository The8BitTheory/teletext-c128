; include the wic64 header file containing the macro definitions

!source "wic64.h"

k_primm = $ff7d
;k_pokebank = $02af  ;.a=value to write, .x=bank, .y=offset from address in $02b9
;strout = $B47C
bsout = $ffd2

data_response = $2400

*= $1c01
    !byte $11,$1c,$e9,$07,$fe,$25,$3a,$9e,$37,$31,$38,$38,$3a,$fe,$26,$00,$00,$00

*= $1c14

main:
; disable basic rom. bank 0, kernal and I/O enabled
    lda #%00001110
    sta $ff00

    jsr detectAndFirmware

    jsr getIp

    +wic64_execute orf_request, data_response
    bcs timeout
    bne error

    lda #<data_response
    sta $fb
    lda #>data_response
    sta $fc

    lda #14 ; lower case charset
    jsr bsout

    jsr parseHtml

;    ldy #0
;-   lda ($fb),y
;    jsr bsout
;    dec wic64_response_size
;    bne +
;    dec wic64_response_size+1
;    bmi .done

;+   iny
;    bne -
;    inc $fc
;    jmp -

.done
    lda #%00000000
    sta $ff00

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

; define request to get the current ip address
request !byte "R", WIC64_GET_IP, $00, $00

; define the request for the status message
status_request: !byte "R", WIC64_GET_STATUS_MESSAGE, $01, $00, $01

orf_request:    !byte "R",WIC64_HTTP_GET, <orf_url_size, >orf_url_size
;orf_url:        !text "https://afeeds.orf.at/teletext/api/v2/mobile/channels/orf1/pages/100"
orf_url:        !text "https://www.ard-text.de/page_only.php?page=101"
orf_url_size = * - orf_url

;data_response: !fill 2048,0


; include the actual wic64 routines
!source "wic64.asm"
!source "src/htmlparse.asm"