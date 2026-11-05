set root [file normalize [file join [file dirname [info script]] ..]]
set dir [file join $root hardware fpai_demo_vivado.runs impl_1]
set temp [file join $root output disable_icap_status.tmp]
set status [file join $root output disable_icap_status.txt]
set_device JFMQL30TAI676H
if {[catch {increment_bit_cfg_v3 [file join $dir ai7030_edif_top.bit] [file join $dir ai7030_edif_top_disable_icap.bit] -disable_icap} msg]} {
 set f [open $temp w];puts $f FAIL;puts $f $msg;close $f
 file rename -force $temp $status;exit 1
}
set f [open $temp w];puts $f PASS;close $f
file rename -force $temp $status
puts V2_DISABLE_ICAP_PASS
exit
