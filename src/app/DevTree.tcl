# DevTree.tcl: contains procedures that generate nodes to the Device Tree of the FPGA
# design
# Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
# Author(s): Vladislav Valek <vladislav.valek@stud.uni-heidelberg.de>
#
# SPDX-License-Identifier: Apache-2.0

proc dts_application {base generics} {
    array set GENERICS $generics

    set hbm_channels  $GENERICS(HBM_CHANNELS)
    set app_core_arch $GENERICS(APP_CORE_ARCH)

    set ret ""
    append ret "application {"

    if {$app_core_arch == "TEST"} {

        if {$hbm_channels > 0} {
            set hbm_tester_base $base
            append ret [dts_hbm_tester "hbm_tester" $hbm_tester_base]
        }
    } elseif {$app_core_arch == "FULL"} {
        append ret [dts_multicore_debug_core 0 $base 4]
    }

    append ret "};"
    return $ret
}

proc dts_multicore_debug_core {index base reg_size} {
	set ret ""
	append ret "multicore_debug_core$index {"
    append ret "compatible = \"ziti,minimal,multicore_debug_core\";"
	append ret "reg = <$base $reg_size>;"
    append ret "};"
	return $ret
}
