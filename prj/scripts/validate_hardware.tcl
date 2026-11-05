# Project Mode validation only. No synthesis, implementation or device access.
set root [file normalize [file join [file dirname [info script]] ..]]
set output [file join $root output]
file mkdir $output
open_project [file join $root hardware lss_hsrv3.xpr]
set_property ip_repo_paths [list [file join $root hardware {PS_AI IP}]] [current_project]
update_ip_catalog
set_property STEPS.PLACE_DESIGN.TCL.PRE [file join $root scripts apply_v2_constraints.tcl] [get_runs impl_1]
set_property top ai7030_edif_top [get_filesets sources_1]
set_property source_mgmt_mode All [current_project]
update_compile_order -fileset sources_1
set bd [get_files -quiet *ps_ai.bd]
if {[llength $bd]!=1} {error "Expected one PS block design"}
open_bd_design $bd
validate_bd_design -force
generate_target all $bd
close_bd_design [get_bd_designs]
update_compile_order -fileset sources_1
set expected [string tolower [file normalize [file join $root ..]]]
set f [open [file join $output active_project_files.tsv] w]
puts $f "path\tfile_type\texists\tinside_v3"
set missing 0
set outside 0
set count 0
foreach item [get_files -all] {
    set path [file normalize [get_property NAME $item]]
    set exists [file exists $path]
    set inside [expr {[string first "$expected/" [string tolower $path]] == 0}]
    puts $f "$path\t[get_property FILE_TYPE $item]\t$exists\t$inside"
    if {!$exists} {incr missing}
    if {!$inside} {incr outside}
    incr count
}
close $f
if {$missing || $outside} {error "V3 project file audit failed: missing=$missing outside=$outside"}
report_ip_status -file [file join $output ip_status.rpt]
set f [open [file join $output project_validation.txt] w]
puts $f "V3_PROJECT_VALIDATION_PASS"
puts $f "ACTIVE_FILES=$count"
puts $f "MISSING_FILES=$missing"
puts $f "OUTSIDE_V3_FILES=$outside"
puts $f "BD_VALIDATED=1"
puts $f "BD_FORCED=1"
puts $f "BD_PRODUCTS_GENERATED=1"
puts $f "PART=[get_property PART [current_project]]"
puts $f "TOP=[get_property top [get_filesets sources_1]]"
puts $f "FRESH_SYNTHESIS=0"
puts $f "BOARD_TESTED=0"
close $f
close_project
puts V3_HARDWARE_VALIDATION_PASS
