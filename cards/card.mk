# card.mk: Makefile include
# Copyright (C) 2022 CESNET z. s. p. o.
# Author(s): Jakub Cabal <cabal@cesnet.cz>
# 			Vladislav Valek <valekv@cesnet.cz>
#
# SPDX-License-Identifier: BSD-3-Clause

# Mandatory parameters (needs to be set in user Makefile)
###############################################################################

# Load correct paths to build system
OFM_PATH:=$(COMBO_BASE)/src/ofm

# Optional parameters (can be changed in user Makefile)
###############################################################################

# Name for output files (rootname)
# This value is set as default in SYNTH_FLAGS(OUTPUT)
OUTPUT_NAME?=unknown-card

USER_ENV?=

# Private parameters (do not change these values in user Makefile)
###############################################################################
CORE_BASE:=$(COMBO_BASE)/src

NETCOPE_ENV = \
	OFM_PATH=$(OFM_PATH) \
	COMBO_BASE=$(COMBO_BASE) \
	FIRMWARE_BASE=$(COMBO_BASE) \
	CARD_BASE=$(CARD_BASE) \
	CORE_BASE=$(CORE_BASE) \
	APP_CONF=$(APP_CONF) \
	OUTPUT_NAME=$(OUTPUT_NAME) \
	PCIE_GEN=$(PCIE_GEN) \
    PCIE_ENDPOINTS=$(PCIE_ENDPOINTS) \
    PCIE_ENDPOINT_MODE=$(PCIE_ENDPOINT_MODE) \
    DMA_TYPE=$(DMA_TYPE) \
	$(USER_ENV)

include $(OFM_PATH)/build/Makefile.Vivado.inc
