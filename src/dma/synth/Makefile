# Makefile: to synthesize only this module
# Copyright (c) 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
# Author(s): Vladislav Valek <vladislav.valek@stud.uni-heidelberg.de>
#
# SPDX-License-Identifier: MIT

TOP_LEVEL_ENT=DMA
TOP_LEVEL_PATH=..

SYNTH=vivado

CLK_PORTS=MI_CLK USR_CLK
CLK_PERIOD=10.000 4.000

.PHONY: all
all: comp

include ../../ofm/build/Makefile
