# core_conf.tcl: Core parameters for NDK which can be set customly by the user
# Copyright (C) 2022 CESNET z. s. p. o.
# Author(s): Jakub Cabal <cabal@cesnet.cz>
#            Vladislav Valek <valekv@cesnet.cz>
#
# SPDX-License-Identifier: BSD-3-Clause

# ------------------------------------------------------------------------------
# Application core parameters:
# ------------------------------------------------------------------------------
# Valid options are: TEST, FULL, EMPTY
set APP_CORE_ARCH "FULL"

# ------------------------------------------------------------------------------
# PCIe parameters (not all combinations work):
# ------------------------------------------------------------------------------
# PCIe Generation (possible values: 3):
# 3 = PCIe Gen3
set PCIE_GEN           $env(PCIE_GEN)
# PCIe endpoints (possible values: 1, 2, 4):
# 1 = 1x PCIe x16 in one slot or 1x PCIe x8 in one slot
set PCIE_ENDPOINTS     $env(PCIE_ENDPOINTS)
# PCIe endpoint mode (possible values: 0, 1, 2):
# 0 = 1x16 lanes
# 2 = 1x8 Low-latenxy
set PCIE_ENDPOINT_MODE $env(PCIE_ENDPOINT_MODE)

# ------------------------------------------------------------------------------
# DMA parameters:
# ------------------------------------------------------------------------------
# Various DMA types
#  0 = no DMA module (empty architecture)
#  4 = DMA Calypte/ JetStream 2.0
set DMA_TYPE $env(DMA_TYPE)
# Total number of DMA channels in whole FW
set DMA_RX_CHANNELS       16
set DMA_TX_CHANNELS       2
# NOTE: TBD feature
# In blocking mode, packets are dropped only when the RX DMA channel is off (default).
# In non-blocking mode, packets are dropped whenever they cannot be sent.
set DMA_RX_BLOCKING_MODE true
# Widths of pointers for data (determines the size of hardware buffers)
set DMA_TX_DATA_PTR_W 13

# ------------------------------------------------------------------------------
# Miscellaneous:
# ------------------------------------------------------------------------------
# The amount of HBM channels
set HBM_CHANNELS 0

# ------------------------------------------------------------------------------
# Debug features
# ------------------------------------------------------------------------------
#   -- Xilinx Virtual Cable: Debug Hub over PCI extended config space (as VSEC),
#      available on Xilinx UltraScale+.
#   -- Intel JTAG-Over-Protocol IP, available on all supported Intel FPGAs.
set VIRTUAL_DEBUG_ENABLE   false
# Enables the GEN_LOOP_SWITCH component for debugging and testing
set DMA_GEN_LOOP_EN        false
# Enables debug probes and counters in the DMA Module (Medusa)
set DMA_DEBUG_ENABLE       false
# Enables debug probes and counters in the PCIe Module (PCIe Core arch: USP and P-Tile)
set PCIE_CORE_DEBUG_ENABLE false
# Enables debug probes in the PCIe Module (PCIe Ctrl)
set PCIE_CTRL_DEBUG_ENABLE false

# ------------------------------------------------------------------------------
# Mandatory project parameters
# ------------------------------------------------------------------------------
set PROJECT_NAME    "NDK_CALYPTE_DEMO"
set PROJECT_VARIANT "${PCIE_ENDPOINTS}EPm${PCIE_ENDPOINT_MODE}"
set PROJECT_VERSION [exec cat $COMBO_BASE/VERSION]
