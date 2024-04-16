# Modules.tcl: script to compile card
# Copyright (C) 2023 CESNET z. s. p. o.
# Author(s): Jakub Cabal <cabal@cesnet.cz>
#
# SPDX-License-Identifier: BSD-3-Clause

# converting input list to associative array
array set ARCHGRP_ARR $ARCHGRP

# Paths

set FPGA_COMMON_BASE         "$ARCHGRP_ARR(CORE_BASE)"
set BOOT_CTRL_BASE           "$ARCHGRP_ARR(CORE_BASE)/boot_ctrl"
set AXI_QSPI_FLASH_CTRL_BASE "$ARCHGRP_ARR(CORE_BASE)/axi_quad_flash_controller"

# Components
lappend COMPONENTS [list "FPGA_COMMON"         $FPGA_COMMON_BASE         $ARCHGRP ]
lappend COMPONENTS [list "BOOT_CTRL"           $BOOT_CTRL_BASE           "FULL"   ]
lappend COMPONENTS [list "AXI_QSPI_FLASH_CTRL" $AXI_QSPI_FLASH_CTRL_BASE "FULL"   ]

# IP sources
lappend MOD "$ENTITY_BASE/ip/axi_quad_spi/axi_quad_spi_0.xci"

if {$ARCHGRP_ARR(PCIE_ENDPOINT_MODE) == 2} {
    lappend MOD "$ENTITY_BASE/ip/pcie4_uscale_plus/x8_low_latency/pcie4_uscale_plus.xci"
} else {
    lappend MOD "$ENTITY_BASE/ip/pcie4_uscale_plus/x16/pcie4_uscale_plus.xci"
}

if {$ARCHGRP_ARR(VIRTUAL_DEBUG_ENABLE)} {
    lappend MOD "$ENTITY_BASE/ip/xvc_vsec/xvc_vsec.xci"
}

lappend MOD "$ENTITY_BASE/ip/hbm/hbm_ip.xci"

# Top-level
lappend MOD "$ENTITY_BASE/fpga.vhd"
