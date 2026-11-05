set root [file normalize [file join [file dirname [info script]] ..]]
if {![file exists [file join $root output build_completed_v3.txt]]} {error "A fresh V3 build is required; inherited V2 results are not new signoff"}
open_project [file join $root hardware lss_hsrv3.xpr]
if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {error "Implementation incomplete"}
open_run impl_1
# Re-read the final scoped CDC constraints before signoff. These are timing
# exceptions/bounds only; no case analysis or logic modification is applied.
source [file join $root rtl v2_cdc.xdc]
set v2checks [list \
 [get_pins -quiet U0_ps_ai_peripheral/u_lss_v2_bridge/ack_g1_reg/D] \
 [get_pins -quiet U0_ps_ai_peripheral/u_lss_v2_bridge/cmd_h1_reg/D] \
 [get_pins -quiet U0_ps_ai_peripheral/u_lss_v2_bridge/ready_g1_reg/D] \
 [get_cells -quiet -hier -regexp {.*u_lss_v2_bridge/cfg_(src|dst|w)_reg\[[0-9]+\]}] \
 [get_cells -quiet -hier -regexp {.*u_lss_v2_bridge/(src|dst|total)_reg\[[0-9]+\]}] \
 [get_cells -quiet -hier -regexp {.*u_lss_v2_bridge/(read_bytes|write_bytes|verify_bytes|code)_reg\[[0-9]+\]}] \
 [get_cells -quiet -hier -regexp {.*u_lss_v2_bridge/(read_gp|write_gp|verify_gp|code_gp|error_gp)_reg(\[[0-9]+\])?}]]
foreach objects $v2checks {if {![llength $objects]} {error "Missing V2 CDC timing objects"}}
set cfgpath [get_timing_paths -from [lindex $v2checks 3] -to [lindex $v2checks 4] -delay_type max -max_paths 1]
set resultpath [get_timing_paths -from [lindex $v2checks 5] -to [lindex $v2checks 6] -delay_type max -max_paths 1]
if {![llength $cfgpath] || ![llength $resultpath]} {error "V2 bundled-data paths are not timed; check overriding exceptions"}
set cfgslack [get_property SLACK $cfgpath]
set resultslack [get_property SLACK $resultpath]
set out [file join $root output]
foreach pattern {U0_ps_ai_peripheral/frame_to_ps_inst0* U0_ps_ai_peripheral/frame_trans_inst0* U0_ps_ai_peripheral/u_vtc*} {
 if {[llength [get_cells -quiet -hier -filter "NAME =~ $pattern"]]} {error "Video cell remains in routed design: $pattern"}
}
foreach pattern {HDMI* FMC_HPC* rx_gtx_full_reset} {
 if {[llength [get_ports -quiet $pattern]]} {error "Removed board port still present: $pattern"}
}
if {![llength [get_cells -quiet -hier -filter {NAME =~ U0_ps_ai_peripheral/u_system_ctrl*}]]} {error "Independent system control missing"}
set f [open [file join $out video_removal_signoff.txt] w]
puts $f "NO_VIDEO_INSTANCES=1"
puts $f "NO_HDMI_SDI_TOP_PORTS=1"
puts $f "SYSTEM_CTRL_PRESENT=[llength [get_cells -quiet -hier -filter {NAME =~ U0_ps_ai_peripheral/u_system_ctrl*}]]"
puts $f "TOP_PORT_OBJECTS=[llength [get_ports]]"
close $f
report_utilization -hierarchical -file [file join $out utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing_summary.rpt]
report_drc -file [file join $out drc.rpt]
report_utilization -file [file join $out utilization.rpt]
report_cdc -details -file [file join $out cdc.rpt]
report_exceptions -file [file join $out timing_exceptions.rpt]
report_route_status -file [file join $out route_status.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set errors [llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]
set f [open [file join $out signoff.txt] w]
puts $f "WNS=$wns";puts $f "WHS=$whs";puts $f "DRC_ERRORS=$errors";close $f
set f [open [file join $out cdc_signoff.txt] w]
puts $f "CFG_DATA_SLACK=$cfgslack";puts $f "RESULT_DATA_SLACK=$resultslack";close $f
if {$cfgslack eq "" || $resultslack eq "" || $cfgslack<0 || $resultslack<0} {error "V2 bundled-data delay bounds failed"}
if {$wns eq "" || $whs eq "" || $wns<0 || $whs<0 || $errors!=0} {error "V2 timing/DRC release gate failed"}
write_checkpoint -force [file join $out lss_hsrv3_signoff.dcp]
set bit [file join [get_property DIRECTORY [get_runs impl_1]] ai7030_edif_top_disable_icap.bit]
if {![file exists $bit]} {error "Missing vendor disable-ICAP bitstream"}
file copy -force $bit [file join $out lss_hsrv3_disable_icap.bit]
puts V3_SIGNOFF_PASS
close_project
