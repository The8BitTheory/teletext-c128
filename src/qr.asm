; qr-code generator
; parameters:
; - reads the location of the string to be encoded from a zeropage location (eg $fb/$fc)
;   the string must be zero-terminated (that saves us the need to provide string-length as a parameter)
; - bank of the string address
; returns: index of sprite-location, written to location of input parameter (64 byte intervals)

; this is the version for the mega65 introdisk #4
; it renders to sprite data and parameters required might be different to other use-cases

; example:
; poke $fb,00:poke $fc,$7c : rem input string location $7c00 
; poke $fd,$f0:poke $fe,$01: rem output sprite index $01f0 (496 dec -> 31744 in bank 0)
; SYS qr,0,$fb,$fd : rem read input string from bank 0, $fb-$fc, and write to sprite-index


target = "c128"
  
  nr_patterns = 1
  max_version = 3
  knows_primm = 1
  
  ;$02-$8f are supposed to be basic-only addresses. it should be save to preserve and restore this area

  z_location  = $fb     ;$fb-$fc for storing indexed addresses
  z_location2 = $fd     ;$fd-$fe for storing indexed addresses
  
  z_temp      = $bf     ;-- stored in m_zpa4
  z_counter1  = $b0     ;ENDCHR   -- stored in m_zpa1
  z_counter2  = $a3     ;VERCK    -- stored in m_zpa2
  z_zp4       = $a4

startQrCodeGenerator
;    cli
    jsr qrinit
    bcs .too_long
    bcc +
    
m_maskbit    !byte 2
    
+   jsr bytes_to_stream
    jsr calc_xor_masks
    jsr rs
    jsr write_patterns
    jsr stream_to_module

    jsr renderspr

    ;recover zeropage values
    lda m_zpa1
    sta z_counter1
    lda m_zpa1+1
    sta z_counter1+1
    
    lda m_zpa2
    sta z_counter2
    lda m_zpa2+1
    sta z_counter2+1
    
    lda m_zpa4
    sta z_temp
    lda m_zpa4+1
    sta z_temp+1
    
    ldx #1
-   lda m_zp4,x
    sta z_zp4,x
    dex
    bne -

    lda m_zpal
    sta z_location
    lda m_zpal+1
    sta z_location+1

    lda m_zpal2
    sta z_location2
    lda m_zpal2+1
    sta z_location2+1

    lda size
;    sta z_location2+1
    ; z_location points to the runtime data
    ldx m_l3   ;these are set in renderspr.a
;    stx z_location
    ldy m_l3+1
;    sty z_location+1
    
;    sei
    rts
    
    ;content too long
.too_long
    lda #0
    sei
    rts
         
size            !byte 0   ;size of one axis-length of the final matrix
contentLength   !byte 0   ;size of the provided URL, also used when writing the "compressed" matrix in render2.a
inputBank       !byte 0
spriteOut       !word 0,0
eccLength       !byte 0   ;nr of ecc bytes to generate  
streamLength    !byte 0 
matrixSize      !byte 0,0 ;size of the matrix in modules (1 byte per module)
rsDivisorOffset !byte 0
m_xpos          !byte 0
m_ypos          !byte 0
m_zpa1          !word 0,0
m_zpa2          !word 0,0
m_zpa4          !word 0,0
m_zp4           !word 0,0 ;used to preserve and recover zero-page addresses
m_zpal          !word 0
m_zpal2         !word 0

!source "src/common.a"

!source "src/qrinit.a"
;!source "src/p2a.a"           ; reads petscii bytes from z_location and writes ascii to z_location2 (which is matrix-start)
!source "src/bytes2stream.a"    ; reads ascii from z_location2 and writes into datastream at z_location (=data+matrix_size)
                            ; z_counter1 holds the right offset for rs.a to continue using it.
!source "src/masks.a"           ; this clears the matrix memory area and calculates all the xor-masks
!source "src/rs.a"              ; reads content bytes from datastream (z_location) and writes ecc bytes to 
                            ; z_location2(=z_location + z_counter1)
!source "src/patterns.a"        ; this writes timing, alignment, finder patterns etc.
!source "src/stream2module.a"

!source "src/renderspr.a"

;data = screen_prep
data = data_response
;data    !byte 0