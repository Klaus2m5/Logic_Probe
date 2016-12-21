This is a logic probe featuring an ATTINY26

The logic probe uses the ADC to detect proper logic levels with ~10k samples per
second. Short pulses or high frequency changes may not be detected this way.
Therefore level changes are detected by the INT0 input in toggle mode. At 8MHz
pulses longer than 125ns can be detected.

3 LEDs signal high and low logic levels and detected level changes or pulses.
The pulse LED stays lit for 100ms after the last pulse edge was detected.

A magnetic transducer makes logic levels and level changes or pulses audible.
A steady low = 650 Hz, a steady high = 1750 Hz, a level change only = 1100Hz.
A low with high pulses warbles with 650 Hz and 1100 Hz. A high with low pulses
warbles with 1750 Hz and 1100 Hz.