# Modules.tcl: script that lists all different modules that are instantiated in various configuration of
# the APPLICATION_CORE
# Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
# Author(s): Vladislav Valek <vladislav.valek@stud.uni-heidelberg.de>
#
# SPDX-License-Identifier: Apache-2.0

# Path to source files
set MFB_PIPE_BASE    "$OFM_PATH/comp/mfb_tools/flow/pipe"
set HBM_TESTER_BASE  "$OFM_PATH/comp/mem_tools/debug/hbm_tester"
set MFB_ASFIFOX_BASE "$OFM_PATH/comp/mfb_tools/storage/asfifox"
set MI_ASYNC_BASE    "$OFM_PATH/comp/mi_tools/async"

# Packages
lappend PACKAGES "$OFM_PATH/comp/base/pkg/math_pack.vhd"
lappend PACKAGES "$OFM_PATH/comp/base/pkg/type_pack.vhd"

# Select specific group of source files according to the architecture type
if {$ARCHGRP == "TEST"} {
    lappend COMPONENTS [list "MFB_PIPE"   $MFB_PIPE_BASE   "FULL" ]
    lappend COMPONENTS [list "HBM_TESTER" $HBM_TESTER_BASE "FULL" ]

    lappend MOD "$ENTITY_BASE/application_core_test_arch.vhd"

} elseif {$ARCHGRP == "EMPTY"} {

    lappend MOD "$ENTITY_BASE/application_core_empty_arch.vhd"

} elseif {$ARCHGRP == "FULL"} {

    lappend COMPONENTS [list "MFB_ASFIFOX"     $MFB_ASFIFOX_BASE "FULL" ]
    lappend COMPONENTS [list "MI_ASYNC"        $MI_ASYNC_BASE    "FULL" ]

    lappend MOD "$ENTITY_BASE/barrel_proc_debug_core.vhd"
    lappend MOD "$ENTITY_BASE/application_core_full_arch.vhd"

    lappend SRCS(CONSTR_VIVADO) "$ENTITY_BASE/pblock_constr.xdc"
}

lappend MOD "$ENTITY_BASE/application_core_ent.vhd"
lappend MOD "$ENTITY_BASE/DevTree.tcl"
