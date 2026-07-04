package require ::quartus::project
package require ::quartus::flow

set base_dir [pwd]

# Project files Quartus stamps with the running toolchain's version metadata
# (QUARTUS_VERSION / LAST_QUARTUS_VERSION) on open/close. The tracked copies are
# kept at 21.1 so both 21.1 and 25.1 build from one tree; snapshot them before the
# flow and restore byte-for-byte after, so a 25.1 build never dirties git.
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

# -force: when the revision database was last written by a different Quartus
# version (e.g. switching between 21.1 and 25.1), project_open errors unless
# allowed to overwrite that database. The db lives under gitignored build output
# and is regenerated every compile, so overwriting it is safe and required for
# dual-version builds.
# Run the compile flow + STA inside a catch so the restore below ALWAYS runs,
# even when the flow fails. project_open re-stamps the guarded files the moment
# it opens them, so an aborted compile (the common dev case) would otherwise
# leave them dirty — defeating the snapshot guard on exactly the failure path it
# exists for. The status is re-raised at the end so quartus_sh -t still exits
# non-zero on a real failure (CI must keep failing).
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

# Restore the tracked project files to their pre-build state (the committed,
# version-neutral 21.1 copies in a clean tree). Runs on success AND failure.
# Placed after the STA report, which reopens the project (sta_custom_report.tcl)
# and re-stamps the version metadata again — so this must run after it.
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
