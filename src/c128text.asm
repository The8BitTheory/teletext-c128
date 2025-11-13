; ASM Utility for the ARD Videotext Viewer for the C128 VDC
; written by Martin Goodwell in October 2025
; find the sourcecode at https://github.com/The8BitTheory/teletext-c128

; include the wic64 header file containing the macro definitions
wic64_include_enter_portal = 0
wic64_include_load_and_run = 0
wic64_optimize_for_size = 1

!source "wic64.h"

chrget = $0380
chrgot = $0386

b_skip_comma      = $795c ; if comma: skip, otherwise: syntax error
b_parse_uint8_to_X    = $87f4 ; read unsigned 8-bit value to X

k_primm = $ff7d
k_getin = $eeeb
;k_pokebank = $02af  ;.a=value to write, .x=bank, .y=offset from address in $02b9
;strout = $B47C
bsout = $ffd2

address_html = $fb
address_vram = $fd
dump_safe   = $b800

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

;*= $1c01
;    !byte $11,$1c,$e9,$07,$fe,$25,$3a,$9e,$37,$31,$38,$38,$3a,$fe,$26,$00,$00,$00

;*= $1c14
*= $3580

    jmp main
    jmp getIp
    jmp init
    jmp createTxtQr
    jmp getTime
    jmp copy
    jmp createCreditsQr

init:
    lda #0
    sta returnValue

    jsr k_primm
!pet "detecting and querying firmware",$d,$0
    jsr detectAndFirmware

getTime
    +wic64_execute time_request, time_response, 5

    lda #<time_response
    sta address_html
    lda #>time_response
    sta address_html+1

    lda #<screen_prep
    sta address_vram
    lda #>screen_prep
    sta address_vram+1

    lda returnValue
    
    rts

main:
    sta input
    stx input+1
    sty input+2

    ; do we have more parameters? ie the subpage
    jsr chrgot
    beq +

    jsr b_skip_comma
    jsr b_parse_uint8_to_X
    stx txt_subinput
    stx nav_subinput

    jsr b_skip_comma
    jsr b_parse_uint8_to_X
    stx txt_subinput+1
    stx nav_subinput+1

+   jsr clearResponseSize

; disable basic rom. bank 0, kernal and I/O enabled
    lda #%00001110
    sta $ff00

    ; if first digit of input has bit7 set, we request the nav-data of the page, not the page itself
    lda input
    bmi +
-   +wic64_execute txt_request, data_response, 5
    beq ++              ; != 0. no error
    jsr endOfProgram    ; =0 zero flag clear: error occurred. error code in .a
    lda #3
    sta returnValue
    rts

; write page string to request-url
+   and #%01111111  ; remove highest bit, leaves us with a valid page number
    sta input
    sta nav_page

    ldx #2
-   lda input,x
    sta nav_page,x
    dex
    bne -

    +wic64_execute nav_request, data_response, 5
    beq +               ; =0. no error    
    jsr endOfProgram    ; =!0 zero flag clear: error occurred. error code in .a
    lda #3
    sta returnValue
    rts

+   pha
    lda input
    ora #%10000000  ; restore value so we can check it again later
    sta input
    pla

++  jsr handleResponse

    lda input
    bpl +
    jsr parseNav
    jmp ++

+   jsr parseHtml

    ; response Size is needed so we can save to disk.
    ; if we have a problem, this should be zero
++  lda responseSize
    sta address_html
    lda responseSize+1
    sta address_html+1

endOfProgram
    lda #%00000000
    sta $ff00

    rts

getIp
    jsr k_primm
!pet "querying IP",$d,0

    +wic64_execute request, response, 5        ; send request and receive the response
    bcc +                   ; carry set means timeout. carry clear = no timeout
    dec timeoutRetry
    beq timeout
    jmp getIp                             ; carry set => timeout occurred
+   beq +
    jmp error                               ; zero flag clear => error status code in accumulator
    
+   lda response
    beq +

    jsr k_primm
; reserve 16 bytes of memory for the response
response: !fill 16, $ea
    
    lda #$0d
    jsr bsout

+   rts

handleResponse:
    
    lda wic64_response_size
    sta responseSize
    lda wic64_response_size+1
    sta responseSize+1

    lda #<data_response
    sta address_html
    lda #>data_response
    sta address_html+1

    lda #<screen_prep
    sta address_vram
    lda #>screen_prep
    sta address_vram+1

    rts


timeout:
    jsr k_primm
    !pet "?timeout error", $00
    lda #3
    sta timeoutRetry

    rts

error:
    ; get the error message of the last request
    +wic64_execute status_request, status_response
    bcs timeout

    jsr k_primm
; reserve 40 bytes of memory for the status message
status_response: !fill 40,$ea
    jsr k_primm
    !byte $d,$0

    jmp clearResponseSize

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

    lda #1
    sta returnValue

    rts

legacy_firmware:
    jsr k_primm
    !pet "?legacy firmware error", $00

    lda #2
    sta returnValue

    rts

clearResponseSize
    lda #0
    sta address_html
    sta address_html+1
    rts

createCreditsQr
    ldx #<credit_url
    stx z_location2
    ldx #>credit_url
    stx z_location2+1
    
    lda #credit_url_length
    sta contentLength
    jmp createQr

createTxtQr
    ; usually the output address for petscii-to-ascii conversion
    ; we only have ascii here anyways
    ; so this is where we can read the readily available URL from
    ldx #<qr_url
    stx z_location2
    ldx #>qr_url
    stx z_location2+1
    
    lda #qr_url_length
    sta contentLength

createQr
; disable basic rom and I/O. bank 0, kernal and I/O enabled
    lda #%00001111
    sta $ff00

    ldx #2
-   lda nav_page,x
    sta qr_page,x
    dex
    bpl -

    jsr startQrCodeGenerator
    pha

    lda #<qr_url
    sta $fb
    lda #>qr_url
    sta $fc

    jsr endOfProgram
    pla

    rts

checkForProblems
    ;check for timeout

    ;check for server error

    rts

copy
    ;copy 2048 bytes from address_vram to $b800 (dec 47104), 2kb below i/o space
    ; we only need 2024 bytes
    lda #%00001110
    sta $ff00

;set counter to 2024 (1024 for screen-ram, 1000 for color ram. we'll use the 24 in between wisely)
    lda #$e8
    sta counter
    lda #$07
    sta counter+1

    lda address_html
    sta tempStore
    lda address_html+1
    sta tempStore+1

    lda #<dump_safe
    sta address_html
    lda #>dump_safe
    sta address_html+1

    lda #<screen_prep
    sta address_vram
    lda #>screen_prep
    sta address_vram+1

    ldy #0
-   lda (address_vram),y
    sta (address_html),y
    dec counter
    bne ++
    dec counter+1
    bmi copyDone
++  iny
    bne -
    inc address_vram+1
    inc address_html+1
    jmp -



copyDone
    lda tempStore
    sta address_html
    lda tempStore+1
    sta address_html+1

    lda #<screen_prep
    sta address_vram
    lda #>screen_prep
    sta address_vram+1

    jmp endOfProgram

; define request to get the current ip address
request !byte "R", WIC64_GET_IP, $00, $00

; define the request for the status message
status_request: !byte "R", WIC64_GET_STATUS_MESSAGE, $01, $00, $01

txt_request:    !byte "R",WIC64_HTTP_GET, <txt_url_size, >txt_url_size
txt_url:        !text "https://www.ard-text.de/page_only.php?page="
input           !text '1','0','0'
txt_suburl      !text "&sub="
txt_subinput    !text '0','1'
txt_url_size = * - txt_url

nav_request:    !byte "R",WIC64_HTTP_GET, <nav_url_size, >nav_url_size
nav_url:        !text "https://www.ard-text.de/nav_only.php?page="
nav_page        !byte 0,0,0
nav_suburl      !text "&sub="
nav_subinput    !text '0','1'
nav_url_size = * - nav_url

qr_url          !text "https://www.ard-text.de/index.php?page="
qr_page         !byte 1,0,0
qr_url_length = *-qr_url

credit_url      !text "https://github.com/The8BitTheory/teletext-c128"
credit_url_length = *-credit_url

;orf_url:        !text "https://afeeds.orf.at/teletext/api/v2/mobile/channels/orf1/pages/100"



time_request    !byte "R", WIC64_GET_LOCAL_TIME, $00, $00
time_response   !fill 20,0

counter         !word 0
tempStore       !word 0
minInput        !byte '1','0','0'
timeoutRetry    !byte 3

; temp storage. will be written to $fb/$fc upon completion
responseSize    !word 0

; will use this to return status information to the basic program
; 0=ok
; 1=no wic64 found
; 2=firmware too old
; 3=http error
returnValue     !byte 0

; include the actual wic64 routines
!source "wic64.asm"
!source "src/htmlparse_ard.asm"
!source "src/qr.asm"

;$24c7 - 9415

screen_prep !byte 0

;$2cc7 - 11463
data_response = screen_prep+2048

