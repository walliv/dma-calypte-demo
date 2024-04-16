# Makefile: Makefile for Alveo U55C
# Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
# Author(s): Vladislav Valek <vladislav.valek@stud.uni-heidelberg.de>
#
# SPDX-License-Identifier: Apache-2.0

COMBO_BASE=../../..
CARD_BASE=..
APP_CONF=app_conf.tcl
OUTPUT_NAME=alveo-u55c-dma-demo

# ------------------------------------------------------------------------------
# PCIe parameters (not all combinations work):
# ------------------------------------------------------------------------------
# Supported combinations for this card:
# TODO: 1x PCIe Gen3 x16 -- PCIE_ENDPOINT_MODE=0 (Normal latency)
# 1x PCIe Gen3 x8  -- PCIE_ENDPOINT_MODE=2 (Low-latency)
# TODO: 1x PCIe Gen3 x8  -- PCIE_ENDPOINT_MODE=3 (Normal latency)
#
# PCIe Generation:
# 3 = PCIe Gen3
PCIE_GEN=3
# PCIe endpoints:
# 1 = 1x PCIe x8/x16 in one slot
PCIE_ENDPOINTS=1
# ------------------------------------------------------------------------------

DMA_TYPE=4

.PHONY: all 100g1 50g1ll 50g1

all: 50g1ll

# TODO:
# 100g1: PCIE_ENDPOINT_MODE=0
# 100g1: OUTPUT_NAME := alveo-u55c-dma-demo-100g1
# 100g1: build

50g1ll: PCIE_ENDPOINT_MODE=2
50g1ll: OUTPUT_NAME:=alveo-u55c-dma-demo-50g1ll
50g1ll: build

# TODO:
# 50g1: PCIE_ENDPOINT_MODE=3
# 50g1: OUTPUT_NAME:=alveo-u55c-dma-demo-50g1
# 50g1: build

include ../../card.mk
