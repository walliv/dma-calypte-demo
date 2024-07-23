# custom_func.tcl: Platform specific procedures required at some stages of a build
# Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
# Author(s): Vladislav Valek <vladislav.valek@stud.uni-heidelberg.de>
#
# SPDX-License-Identifier: Apache-2.0

# This procedure creates a TCL script that list all the source files in the design and
# puts a Vivado commands to add them during build. This list is writen to an output file.
proc target_filelist { {filename "filelist.tcl"} } {
    global SYNTH_FLAGS HIERARCHY

    set NB_FILELIST [AddInputFiles SYNTH_FLAGS HIERARCHY EvalFileDevTree_paths ""]

    foreach gen_file $SYNTH_FLAGS(NB_GENERATED_FILES) {
        eval target_generate_file [SimplPath [lindex $gen_file 0]]
    }

    set library "work"
    set content "# This is an automatically generated file.\n"
    append content "# You can regenerate it using \"make filelist\".\n\n"

    foreach item $NB_FILELIST {

        array set opt [lassign $item fname]
        set fext [file extension $fname]

        if {! ($opt(TYPE) == "COMPONENT" || $opt(TYPE) == "DEVTREE")} {
            puts "Adding: $fname"
            parray opt
        }

        if {$opt(TYPE) == ""} { # A file is a normal HDL source file

            if {$fext == ".vhd" || $fext == ".vhdl"} {
                append content "read_vhdl -library $library -vhdl2008 $fname\n"
            } elseif { $FEXT == ".v" } {
                append content "read_verilog -library $library $fname\n"
            } elseif { $FEXT == ".sv" || $FEXT == ".svp" } {
                append content "read_verilog -library $library -sv $fname\n"
            }

        } elseif {$opt(TYPE) == "CONSTR_VIVADO" && $fext == ".xdc"} { # A file is a constraint file
            append content "read_xdc $fname\n"

            if {[info exists opt(SCOPED_TO_REF)]} {
                append content "set_property SCOPED_TO_REF $opt(SCOPED_TO_REF) \[get_files [file tail $fname]\]\n"
            }
            if {[info exists opt(PROCESSING_ORDER)]} {
                append content "set_property PROCESSING_ORDER $opt(PROCESSING_ORDER) \[get_files [file tail $fname]\]\n"
            }
            if {[info exists opt(USED_IN)]} {
                append content "set_property USED_IN $opt(USED_IN) \[get_files \[file tail $FNAME\]\]\n"
            }

        } elseif {$opt(TYPE) == "VIVADO_IP_XACT"} { # A file is an IP defined by the XCI file
            append content "read_ip $fname\n"
            append content "generate_target all \[get_files $fname\]\n"
        } elseif {$opt(TYPE) == "VIVADO_BD"} { # A file is a Block Diagram
            append content "read_bd $fname\n"
            append content "generate_target all \[get_files $fname\] -force\n"
        }

        if {$opt(TYPE) != "COMPONENT"} {
            foreach {param_name param_value} [array get opt] {
                if {$param_name == "VIVADO_SET_PROPERTY"} {
                    append content "set_property $param_value \[get_files [file tail $fname]\]\n"
                }
            }
        }

        unset opt
    }

    file delete "DevTree_paths.txt"
    nb_file_update $filename $content
}

# This method iterates throug IP generation scripts included in the current platform.
# 1. ip_comps_arr - is a list containing the base_names of the script files and the cathegory of files
#                   which it belongs to
# 2. ip_modify_base - is a path to the script for IP generation
# 3. archgrp - is the list of parameters passed down the hierarchy for the modules
proc process_ip_scripts {ip_comps_arr ip_modify_base archgrp} {
    upvar 1 MOD local_mods

    foreach ip_comp $ip_comps_arr {
        set script [lindex $ip_comp 1]
        set comp   [lindex $ip_comp 2]
        set modify [lindex $ip_comp 4]

        # adjust paths
        lset archgrp [expr [lsearch $archgrp IP_BUILD_DIR]+1] $ip_modify_base

        set params_l [concat $archgrp "IP_COMP_NAME" $comp "IP_EXT_BASE" $ip_modify_base]
        if {$modify == 1} {
            lappend local_mods [list "$ip_modify_base/$script.ip.tcl" TYPE "VIVADO_TCL" PHASE { "ADD_FILES" "IP_MODIFY" } VARS [list IP_PARAMS_L $params_l]]
        }
    }
}
