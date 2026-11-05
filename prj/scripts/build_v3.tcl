set root [file normalize [file join [file dirname [info script]] ..]]
set mode [lindex $argv 0]
if {$mode eq ""} {set mode validate}
if {$mode ni {validate synth build}} {error "Expected validate|synth|build"}
file mkdir [file join $root output]
open_project [file join $root hardware lss_hsrv3.xpr]
set_property ip_repo_paths [list [file join $root hardware {PS_AI IP}]] [current_project]
update_ip_catalog
if {![llength [get_files -quiet *lss_v2_bridge.sv]]} {add_files [file join $root rtl lss_v2_bridge.sv]}
if {![llength [get_files -quiet *v2_cdc.xdc]]} {add_files -fileset constrs_1 [file join $root rtl v2_cdc.xdc]}
set_property USED_IN_SYNTHESIS false [get_files *v2_cdc.xdc]
set_property PROCESSING_ORDER LATE [get_files *v2_cdc.xdc]
set_property top ai7030_edif_top [get_filesets sources_1]
set_property source_mgmt_mode All [current_project]
# Two optional hook files are absent in the vendor snapshot. Remove only these
# nonexistent entries; keep all supplied FMSH transformation/implementation hooks.
foreach q [get_files -quiet [list *implementation_place_pre.tcl *implementation_place_post.tcl]] {if {![file exists $q]} {remove_files $q}}
foreach prop {STEPS.PLACE_DESIGN.TCL.PRE STEPS.PLACE_DESIGN.TCL.POST} {
 set value [get_property $prop [get_runs impl_1]]
 if {$value ne "" && ![file exists $value]} {set_property $prop {} [get_runs impl_1]}
}
set_property STEPS.PLACE_DESIGN.TCL.PRE [file join $root scripts apply_v2_constraints.tcl] [get_runs impl_1]
update_compile_order -fileset sources_1
set bd [get_files -quiet *ps_ai.bd]
open_bd_design $bd
validate_bd_design
save_bd_design
generate_target all $bd
set wrappers [make_wrapper -files $bd -top]
if {[llength $wrappers]!=1} {error "Expected one PS wrapper"}
file copy -force [lindex $wrappers 0] [file join $root hardware rtl ps_ai_wrapper.sv]
close_bd_design [get_bd_designs]
set fp [open [file join $root output integration_validation.txt] w]
puts $fp "BD_VALIDATED=1"
puts $fp "SINGLE_MIG=1"
puts $fp "SOURCE=[get_files *lss_v2_bridge.sv]"
close $fp
if {$mode ne "validate"} {
 reset_run synth_1
 launch_runs synth_1 -jobs 4
 wait_on_run synth_1
 if {![string match "*Complete*" [get_property STATUS [get_runs synth_1]]]} {error "Synthesis failed"}
}
if {$mode eq "build"} {
 launch_runs impl_1 -to_step write_bitstream -jobs 4
 wait_on_run impl_1
 if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {error "Implementation failed"}
}
if {$mode eq "build"} {set f [open [file join $root output build_completed_v3.txt] w];puts $f "V3_FRESH_BUILD_COMPLETE";close $f}
puts "V3_PROJECT_${mode}_PASS"
close_project
