;
;
;   L o g i c   P r o b e
;
; signals logic levels and pulse edges via LEDs and sound
;
; Copyright (C) 2016  Klaus Dormann
;
; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;
; contact info at http://2m5.de or email K@2m5.de
;
; Version: 21.12.2016 - completed testing
;          22.12.2016 - fixed probe precharge for TTL level
;
; ATTINY26 fuse settings (if other than default):
;   internal oscillator 8MHz - modify osccal in code!
;
; related docs:
;   circuit diagram
;
; description of hardware:
;   porta0:2   LEDs active low (a0 = high, a1 = low, a2 = pulse)
;   porta6     precharge probe (high = CMOS 50%, Hi-Z = TTL 1.4V)
;   porta7     level switch input (open = CMOS, closed = TTL)
;   portb3     audio frequency output (oc1b)
;   portb6     probe input (adc9, int0)
;
; Changes:
;   21.12.2016 original version
 
      .NOLIST
      .INCLUDE "tn26def.inc"
      .INCLUDE "sam.inc"
      .LIST
                   
;
; reserved registers
;
; 0x00 non immediate
.DEF  ls          =r4         ; # of low samples since last audio output
.DEF  hs          =r5         ; # of high samples since last audio output
.DEF  csf         =r6         ; current state frequency
; 0x10 immediate
.DEF  a           =r16        ; immediate GPR
.DEF  pa          =r17        ; port A shadow, a7=switch pullup, a0:a2=LEDs
.DEF  et          =r18        ; 8ms units while edge detector LED is on
; 0x18 immediate word
                              ; none

;
; ******************* RESET ****************
;
      ldi   a,ramend          ;set Stack-Pointer
      out   sp,a
; *** modify value to be loaded to osccal according to device signature ***
      ldi   a,0xa2            ;internal oscillator calibration value 8 MHz
      out   osccal,a
      ldi   a,4               ;timer 0 ~ 8ms (ck/256)
      out   tccr0,a
      ldi   a,(1<<ctc1)|7     ;timer 1 sound freq. by ctc, ck/64 
      out   tccr1b,a
      ldi   a,1               ;toggle sound on bottom
      out   ocr1b,a
      ldi   a,0b1000          ;sound out on pb3
      out   ddrb,a
      ldi   a,0b111           ;LEDs on port a0:a2
      out   ddra,a
      ldi   pa,0x80           ;switch pullup on a7, all LEDs on
      out   porta,pa
      ldi   et,124            ;wait 1 second while all LEDs are on
      do       LED_test
         do       LED_timer
            in    a,tifr            ;8ms expired?
            andi  a,(1<<tov0)
         loopeq   LED_timer
         out   tifr,a            ;clear tov0
         dec   et
      loopne   LED_test
      ldi   pa,0x87           ;switch pullup on a7, all LEDs off
      out   porta,pa
                              ;ADC (probe level detector)
      ldi   a,(1<<adlar)|9    ;ADCref=AVcc, ADCH=8 bit, input=ADC9 (port b6)
      out   admux,a
      ldi   a,(1<<aden)|(1<<adsc)|(1<<adfr)|6 ;ADC start free run with 125 kHz
      out   adcsr,a
      ldi   a,1               ;INT0 on level change (probe edge detector)
      out   mcucr,a
      clr   csf               ;clear registers to inactive state
      clr   ls
      clr   hs
      clr   et
;
; ****************** Main Program ************
;
      do    main
; ADC - check level and drive high and low LEDs
;       register # of samples qualifying as high or low
         sbis  adcsr,adif     ;ADC conversion complete?
         ifs   adc_complete
            in    a,adch         ;conversion upper 8 bits
            sbi   adcsr,adif     ;allow next conversion (free running)
            sbr   pa,0b01000011  ;clear level LEDs (undefined), set CMOS (pa6)
            sbis  pina,7         ;cmos/ttl levels?
            ifs   adc_cmos
               cpi   a,77        ;<=30% = low
               iflo  adc_cmoslow
                  cbr   pa,0b010    ;low LED on
                  inc   ls          ;register low sample
               else  adc_cmoslow
                  cpi   a,178       ;>=70% = high
                  ifsh  adc_cmoshigh
                     cbr   pa,0b001    ;high LED on
                     inc   hs          ;register high sample
                  end   adc_cmoshigh
               end   adc_cmoslow
               sbi   ddra,6      ;set CMOS mode probe precharge (50%)
            else  adc_cmos
               cpi   a,41        ;<=0.8V = low
               iflo  adc_ttllow
                  cbr   pa,0b010    ;low LED on
                  inc   ls          ;register low sample
               else  adc_ttllow
                  cpi   a,102       ;>=2v = high
                  ifsh  adc_ttlhigh
                     cbr   pa,0b001    ;high LED on
                     inc   hs          ;register high sample
                  end   adc_ttlhigh
               end   adc_ttllow
               cbr   pa,(1<<6)      ;set TTL mode probe precharge (1.4V)
               cbi   ddra,6
            end   adc_cmos
            out   porta,pa       ;set LEDs according to logic state
         end   adc_complete
; 8ms timer 0 - check 100ms pulse LED on timer
;               drive timer 1 sound output control
         in    a,tifr         ;8ms timer?
         andi  a,(1<<tov0)
         ifne  timer8
            out   tifr,a         ;clear flag
            tst   et             ;edge timer expired?
            ifne  edge_timer
               dec   et             ;edge timer countdown
               ifeq  edge_LED_off
                  sbr   pa,0b100       ;pulse LED off
                  out   porta,pa
               end   edge_LED_off
            end   edge_timer
            mov   a,et        ;any edges or logic levels detected?
            or    a,hs
            or    a,ls
            ifne  audio_actv
               cp    hs,ls       ;more high or more low?
               ifsh  audio_high
                  tst   hs          ;only edges?
                  ifeq  audio_edge
                     ldi   a,0x70      ;1109Hz (C#6) pulse
                  else  audio_edge
                     ldi   a,0x46      ;1760Hz (A6) high
                  end   audio_edge
               else  audio_high
                  ldi   a,0xbd      ;659Hz (E5) low
               end   audio_high
               clr   ls             ;reset sample counts
               clr   hs
               cp    a,csf          ;on steady state
               ifeq_and steady_pulse
               tst   et             ;and pulse
               ifne     steady_pulse
                  ldi   a,0x70         ;1109Hz (C#6) pulse
               end      steady_pulse
               mov   csf,a          ;save current state
               out   ocr1c,a        ;set frequency
               ldi   a,(1<<com1b0)  ;oc1b (pb3) = toggle (=sound)  
            else  audio_actv
               clr   csf
               ldi   a,(2<<com1b0)  ;oc1b (pb3) = clear (=silent)
            end   audio_actv
            out   tccr1a,a       ;set OC1A (pb1)
         end   timer8
; INT0 - drive pulse LED and on timer
         in    a,gifr         ;pulse edge detected?
         andi  a,(1<<intf0)
         ifne  edge_detect
            out   gifr,a         ;clear flag
            ldi   et,12          ;~100 ms
            cbr   pa,0b100       ;pulse LED on
            out   porta,pa
         end   edge_detect
      loop  main
