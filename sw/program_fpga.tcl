#!/bin/env -S vivado -mode batch -notrace -source
#
# program_fpga.tcl: Script for programming the FPGA device via JTAG using Vivado
# Hardware manager
# Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
# Author(s): Vladislav Valek <vladislav.valek@stud.uni-heidelberg.de>
#
# SPDX-License-Identifier: Apache-2.0

# How to run:
#
# vivado -mode batch -source <path_to_this_file>
#
# The path can also be relative from the current location in the terminal.

# --------------------------------------------------------------------------------
# Parameters to check on machines other than nct-valek:
# --------------------------------------------------------------------------------
# These are available targets on the specific machine and has to be checked if
# the platform (e.g. the machine a card is running on) has the correct names of
# targets
set target_names {"xcvu9p_0" "xcu200_0"}
# These are the names of programming cables fro each target. Normally, each
# target has a separete programming cable thus they are mapped 1-to-1 between
# target_names and cable_names
set cable_names {"*/xilinx_tcf/Digilent/*" "*/xilinx_tcf/Xilinx/*"}

# --------------------------------------------------------------------------------
# Look for available files in the current repository
# --------------------------------------------------------------------------------
# This uses globing for programming files, possibly more suffixes can be added
if [catch {set bitFiles [glob *.bit]} fid] {
    puts stderr "No programming file found in the current folder!\n$fid"
    exit 1
}

set numFiles [llength $bitFiles]

# If there are no files, then end the script
if {$numFiles == 0} {
    puts "Error: no .bit files in the current directory."
    exit 1

# If there is only one file, just go on with that
} elseif {$numFiles == 1} {
    set chosenFile [lindex $bitFiles 0]

# If there are multiple programming files, initialize the interactive mode and
# choose from available files
} else {
    puts "Multiple .bit files found:"
    set count 1
    foreach file $bitFiles {
        puts "$count: $file"
        incr count
    }

    # Prompt user to choose a file
    set validInput 0
    while {!$validInput} {
        puts -nonewline "Enter the number of the file you want to choose: "
        flush stdout
        gets stdin userChoice

        # Check if the input is a valid number within range
        if {[regexp {^[0-9]+$} $userChoice] && $userChoice > 0 && $userChoice <= $numFiles} {
            set chosenFile [lindex $bitFiles [expr {$userChoice - 1}]]
            set validInput 1
        } else {
            puts "Invalid choice. Please enter a number between 1 and $numFiles."
        }
    }
}

# --------------------------------------------------------------------------------
# Choose from the available targets
# --------------------------------------------------------------------------------
set target_num 0

set target_count [llength $target_names]

# Choose the target interactively if there is more than one target
if {$target_count > 1} {
    puts "Choose the target:"
    set count 1
    foreach target $target_names {
        puts "$count: $target"
        incr count
    }

    while {!$target_num} {
        puts -nonewline "Enter the number of the target you want to choose: "
        flush stdout
        gets stdin userChoice

        # Check if the input is a valid number within range
        if {[regexp {^[0-9]+$} $userChoice] && $userChoice > 0 && $userChoice <= $target_count} {
            set chosenTarget [lindex $target_names [expr {$userChoice - 1}]]
            set chosenCable [lindex $cable_names [expr {$userChoice - 1}]]
            set target_num 1
        } else {
            puts "Invalid choice. Please enter a number between 1 and $target_count."
        }
    }

# If there is only one target, then go with that by default and do not open the prompt
} else {
    set chosenTarget [lindex $target_names 0]
    set chosenCable [lindex $cable_names 0]
}

# --------------------------------------------------------------------------------
# Programming the device using Vivado Hardware Manager
# --------------------------------------------------------------------------------
# Open the Hardware manager and disconnect all existing hw_server connections
open_hw_manager
catch {disconnect_hw_server nct-valek.ziti.uni-heidelberg.de:3121}

# Connect to the hw_server on remote machine and open the programming bridge
connect_hw_server -url nct-valek.ziti.uni-heidelberg.de:3121
current_hw_target [get_hw_targets $chosenCable]
# Set JTAG frequency to 15 MHz (only used for programming so it can be lower)
set_property PARAM.FREQUENCY 15000000 [get_hw_targets $chosenCable]

# Opens the target under the programming bridge
open_hw_target

# Selects an FPGA chip
current_hw_device [lindex [get_hw_devices $chosenTarget] 0]
refresh_hw_device -update_hw_probes false [lindex [get_hw_devices $chosenTarget] 0]

# Probe files (ILA's .ltx files) can be specified too
set_property PROBES.FILE {} [get_hw_devices $chosenTarget]
set_property FULL_PROBES.FILE {} [get_hw_devices $chosenTarget]
set_property PROGRAM.FILE "$chosenFile" [get_hw_devices $chosenTarget]

# Send the bitstream to the device and refresh
program_hw_devices [get_hw_devices $chosenTarget]
refresh_hw_device [lindex [get_hw_devices $chosenTarget] 0]

# Close everything and exit
close_hw_target
disconnect_hw_server nct-valek.ziti.uni-heidelberg.de:3121
close_hw_manager

exit 0
