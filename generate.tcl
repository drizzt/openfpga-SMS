package require ::quartus::project
package require ::quartus::flow

set base_dir [pwd]

# Quartus re-stamps QUARTUS_VERSION / LAST_QUARTUS_VERSION into these on open and
# close. The tracked copies stay at 21.1 so 21.1 and 25.1 build from one tree, so
# snapshot them here and restore them below.
set guarded_files {
    projects/sms_pocket.qpf
    projects/ap_core.qpf
    projects/ap_core.qsf
}
set snap_dir build_output/.proj_snapshot
file mkdir $snap_dir
foreach f $guarded_files {
    if {[file exists $f]} {
        file copy -force $f [file join $snap_dir [file tail $f]]
    }
}

# -force lets project_open overwrite a revision database written by the other
# Quartus version; it lives under gitignored build output and is rebuilt anyway.
# The catch is required, not cosmetic: project_open stamps the guarded files
# immediately, so an aborted compile still needs the restore below to run.
set build_status [catch {
    project_open -force -revision ap_core projects/sms_pocket.qpf
    set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL
    execute_flow -compile
    project_close

    # project_open changes cwd to the project directory; restore it
    cd $base_dir

    # Run custom STA report for detailed timing path analysis.
    # (sta_custom_report.tcl verifies its own report outputs.)
    file mkdir build_output/reports
    post_message "Running custom STA report..."
    if {[catch {qexec "quartus_sta -t scripts/sta_custom_report.tcl"} result]} {
        post_message -type warning "Custom STA report failed: $result"
    } else {
        post_message "Custom STA completed successfully."
    }
} build_error]

# The catch may have aborted with cwd still inside the project dir; reset it so
# the relative guarded/snapshot paths below resolve correctly.
cd $base_dir

# Restore the guarded files, on success and on failure alike. Must come after the
# STA report, which reopens the project and re-stamps the version metadata again.
foreach f $guarded_files {
    set snap [file join $snap_dir [file tail $f]]
    if {[file exists $snap]} {
        file copy -force $snap $f
    }
}

# Propagate a build/flow failure now that the files are restored, so quartus_sh
# -t exits non-zero for CI.
if {$build_status} {
    error $build_error
}
