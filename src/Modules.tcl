# Modules.tcl: script to compile single module
# Copyright (C) 2019 CESNET z. s. p. o.
# Author(s): Jakub Cabal <cabal@cesnet.cz>
#           Vladislav Valek <valekv@cesnet.cz>
#
# SPDX-License-Identifier: BSD-3-Clause

# NOTE: For more information, visit the Parametrization section of the NDK-CORE documentation.

# convert input list to an array
array set ARCHGRP_ARR $ARCHGRP

# Paths to components
set ASYNC_RESET_BASE      "$OFM_PATH/comp/base/async/reset"
set ASYNC_OPEN_LOOP_BASE  "$OFM_PATH/comp/base/async/open_loop"
set PCIE_BASE             "$ENTITY_BASE/pcie"
set DMA_BASE              "$ENTITY_BASE/dma"
set CLOCK_GEN_BASE        "$ENTITY_BASE/clk_gen"
set SDM_CTRL_BASE         "$ENTITY_BASE/sdm_ctrl"
set MI_SPLITTER_BASE      "$OFM_PATH/comp/mi_tools/splitter_plus_gen"
set RESET_TREE_GEN_BASE   "$OFM_PATH/comp/base/misc/reset_tree_gen"
set MI_TEST_SPACE_BASE    "$OFM_PATH/comp/mi_tools/test_space"
set HWID_BASE             "$OFM_PATH/comp/base/misc/hwid"
set JTAG_OP_CTRL_BASE     "$ENTITY_BASE/jtag_op_ctrl"
set APPLICATION_CORE_BASE "$ENTITY_BASE/app"

# Packages
lappend PACKAGES "$OFM_PATH/comp/base/pkg/math_pack.vhd"
lappend PACKAGES "$OFM_PATH/comp/base/pkg/type_pack.vhd"
lappend PACKAGES "$ENTITY_BASE/combo_const_pkg.vhd"
lappend PACKAGES "$ENTITY_BASE/mi_addr_space_pkg.vhd"

set DMA_ARCH "EMPTY"

if {$ARCHGRP_ARR(DMA_TYPE) == 4} {
    set DMA_ARCH "CALYPTE"
}

lappend COMPONENTS [list "ASYNC_RESET"      $ASYNC_RESET_BASE      "FULL"                       ]
lappend COMPONENTS [list "ASYNC_OPEN_LOOP"  $ASYNC_OPEN_LOOP_BASE  "FULL"                       ]
lappend COMPONENTS [list "PCIE"             $PCIE_BASE             $ARCHGRP_ARR(PCIE_MOD_ARCH)  ]
lappend COMPONENTS [list "DMA"              $DMA_BASE              $DMA_ARCH                    ]
lappend COMPONENTS [list "CLOCK_GEN"        $CLOCK_GEN_BASE        $ARCHGRP_ARR(CLOCK_GEN_ARCH) ]
lappend COMPONENTS [list "SDM_CTRL"         $SDM_CTRL_BASE         $ARCHGRP_ARR(SDM_SYSMON_ARCH)]
lappend COMPONENTS [list "MI_SPLITTER"      $MI_SPLITTER_BASE      "FULL"                       ]
lappend COMPONENTS [list "RESET_TREE_GEN"   $RESET_TREE_GEN_BASE   "FULL"                       ]
lappend COMPONENTS [list "MI_TEST_SPACE"    $MI_TEST_SPACE_BASE    "FULL"                       ]
lappend COMPONENTS [list "HWID"             $HWID_BASE             $ARCHGRP_ARR(CLOCK_GEN_ARCH) ]
lappend COMPONENTS [list "JTAG_OP_CTRL"     $JTAG_OP_CTRL_BASE     $ARCHGRP_ARR(CLOCK_GEN_ARCH) ]
lappend COMPONENTS [list "APPLICATION_CORE" $APPLICATION_CORE_BASE $ARCHGRP_ARR(APP_CORE_ARCH)  ]

lappend MOD "$ENTITY_BASE/fpga_common.vhd"
lappend MOD "$ENTITY_BASE/DevTree.tcl"
