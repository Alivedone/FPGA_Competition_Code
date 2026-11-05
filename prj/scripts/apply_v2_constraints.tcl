# Project Mode PLACE_DESIGN pre-hook, after vendor opt/DCP merging hooks.
set v2root [file normalize [file join [file dirname [info script]] ..]]
source [file join $v2root rtl v2_cdc.xdc]
