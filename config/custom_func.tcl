
proc target_filelist { {filename "filelist.tcl"} } {
    puts "Hi, this is target_filelist!"

    global SYNTH_FLAGS HIERARCHY

    parray SYNTH_FLAGS
    parray HIERARCHY

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
