# pblock_constr.xdc: Application specific constrains for the design
# Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
# Author(s): Vladislav Valek <vladislav.valek@stud.uni-heidelberg.de>
#
# SPDX-License-Identifier: Apache-2.0

add_cells_to_pblock [get_pblocks pblock_pcie_i] [get_cells -quiet cm_i/reset_tree_gen_i]
add_cells_to_pblock [get_pblocks pblock_pcie_i] [get_cells -quiet cm_i/jtag_op_ctrl_i]
add_cells_to_pblock [get_pblocks pblock_pcie_i] [get_cells -quiet cm_i/mi_test_space_i]
add_cells_to_pblock [get_pblocks pblock_pcie_i] [get_cells -quiet cm_i/app_i/barrel_proc_debug_core_i]
add_cells_to_pblock [get_pblocks pblock_pcie_i] [get_cells -quiet cm_i/app_i/dma_rx_mfb_asfifox_i]
add_cells_to_pblock [get_pblocks pblock_pcie_i] [get_cells -quiet cm_i/app_i/dma_tx_mfb_asfifox_i]
