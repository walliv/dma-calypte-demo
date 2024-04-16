# bootstrap.tcl: Initializes all parameters for a chosen design by sourcing necessary
# configuration files
# Copyright (C) 2022 CESNET, z. s. p. o.
# Author(s): Vladislav Valek <valekv@cesnet.cz>
#
# SPDX-License-Identifier: BSD-3-Clause

set OUTPUT_NAME   $env(OUTPUT_NAME)
set OFM_PATH      $env(OFM_PATH)
set COMBO_BASE    $env(COMBO_BASE)
set FIRMWARE_BASE $env(FIRMWARE_BASE)
set CARD_BASE     $env(CARD_BASE)
set CORE_BASE     $env(CORE_BASE)

set CORE_CONF        $COMBO_BASE/config/core_conf.tcl
set CORE_PARAM_CHECK $COMBO_BASE/config/core_param_check.tcl

set CARD_PARAM_CHECK $CARD_BASE/card_param_check.tcl

set APP_CONF $env(APP_CONF)

# Source files for generation of VHDL package and
# module collecting script
source $OFM_PATH/build/VhdlPkgGen.tcl
source $OFM_PATH/build/Shared.tcl

# Initialize VHDL package
VhdlPkgBegin

# Source CORE user configurable parameters
source $CORE_CONF

# Source application user configurable parameters
if {$APP_CONF ne ""} {
    source $APP_CONF
}

# Run parameter check on a specific card
source $CARD_PARAM_CHECK

# Run parameter check on a whole design and generate VHDL package
source $CORE_PARAM_CHECK

# Source main build files
source $COMBO_BASE/config/Vivado.inc.tcl
