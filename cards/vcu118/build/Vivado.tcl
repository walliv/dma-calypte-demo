# Vivado.tcl: Vivado tcl script to compile whole FPGA design
# Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
# Author(s): Vladislav Valek <vladislav.valek@stud.uni-heidelberg.de>
#
# SPDX-License-Identifier: Apache-2.0

# Source configuration files(populates all variables from env)
source $env(COMBO_BASE)/config/bootstrap.tcl

# ------------------------------------------------------------------------------
# Design parameters
# ------------------------------------------------------------------------------
# Create only a Vivado project for further design flow driven from Quartus GUI
# "0" ... full design flow in command line
# "1" ... project composition only for further design flow in GUI
set SYNTH_FLAGS(PROJ_ONLY) "0"
# Just synthesis (unless PROJ_ONLY is set to 1)
# "0" ... Run whole design process
# "1" ... only perform design synthesis
set SYNTH_FLAGS(SYNTH_ONLY) "0"
# Name of the top level entity
set SYNTH_FLAGS(MODULE)    "FPGA"
# Part name
set SYNTH_FLAGS(FPGA)      "xcvu9p-flga2104-2L-e"
# Configuration interface type (TBD: not used yet)
set SYNTH_FLAGS(MCS_IFACE) "SPIx8"
# Name of a card
set SYNTH_FLAGS(BOARD)     $CARD_NAME

# ------------------------------------------------------------------------------
# Optimization directives for synthesis/implementation
#
# Project mode:     Specific name of a directive
# Non-project mode: Specific name of a directive OR a string of switches
# ------------------------------------------------------------------------------
# Synthesis directive (synth_design command)
# set SYNTH_FLAGS(SYNTH_DIRECTIVE) ""
# Post-synthesis optimization (opt_design command)
set SYNTH_FLAGS(SOPT_DIRECTIVE)  "Explore"
# Placer (place_design command)
set SYNTH_FLAGS(PLACE_DIRECTIVE) "Explore"
# Post-place power optimization (power_opt_design command) only enable or disable, i.e. no directive
# set SYNTH_FLAGS(PPLACE_POWER_OPT_DIRECTIVE) false
# Post-place physical optimization (phys_opt_design command)
# set SYNTH_FLAGS(PPLACE_PHYS_OPT_DIRECTIVE) ""
# Router (route_design command)
set SYNTH_FLAGS(ROUTE_DIRECTIVE) "Explore"
# Post-route physical optimization (phys_opt_design command)
# set SYNTH_FLAGS(PROUTE_PHYS_OPT_DIRECTIVE)  ""

# ------------------------------------------------------------------------------
# Constant propagation to submodules
# ------------------------------------------------------------------------------
# Propagating card constants to the Modules.tcl files of the underlying components.
set CARD_ARCHGRP(CORE_BASE)          $CORE_BASE
set CARD_ARCHGRP(PCIE_ENDPOINT_MODE) $PCIE_ENDPOINT_MODE

# make lists from associative arrays
set CARD_ARCHGRP_L [array get CARD_ARCHGRP]
set CORE_ARCHGRP_L [array get CORE_ARCHGRP]

# concatenate lists to be handed as a part of the ARCHGRP to the TOPLEVEL
set ARCHGRP_ALL [concat $CARD_ARCHGRP_L $CORE_ARCHGRP_L]

# ------------------------------------------------------------------------------
# Adding components and constrains
# ------------------------------------------------------------------------------
# Add top level entity to the hierarchy of the components
lappend HIERARCHY(COMPONENTS) [list "TOPLEVEL" $CARD_BASE/src $ARCHGRP_ALL]
# Add constrains for a current card
lappend SYNTH_FLAGS(CONSTR) "$CARD_BASE/constr/general.xdc"
lappend SYNTH_FLAGS(CONSTR) "$CARD_BASE/constr/pcie.xdc"

# ------------------------------------------------------------------------------
# Call main function which handle targets
# ------------------------------------------------------------------------------
nb_main
