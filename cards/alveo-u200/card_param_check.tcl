# card_param_check.tcl: Card specific parameters and parameter check
# Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
#
# SPDX-License-Identifier: Apache-2.0

set CARD_NAME "ALVEO_U200"
# Achitecture of Clock generator
set CLOCK_GEN_ARCH "USP"
# Achitecture of PCIe module
set PCIE_MOD_ARCH "USP"
# Achitecture of SDM/SYSMON module
set SDM_SYSMON_ARCH "USP_IDCOMP"
# Boot controller type
set BOOT_TYPE 0

# ------------------------------------------------------------------------------
# Checking of parameter compatibility
# ------------------------------------------------------------------------------
if {!(($PCIE_ENDPOINTS == 1 && $PCIE_GEN == 3 && $PCIE_ENDPOINT_MODE == 0) ||
      ($PCIE_ENDPOINTS == 1 && $PCIE_GEN == 3 && $PCIE_ENDPOINT_MODE == 2)) } {
    error "Incompatible PCIe configuration: PCIE_ENDPOINTS = $PCIE_ENDPOINTS, PCIE_GEN = $PCIE_GEN, PCIE_ENDPOINT_MODE = $PCIE_ENDPOINT_MODE!
Allowed PCIe configurations:
- 1xGen3x16  -- PCIE_GEN=3, PCIE_ENDPOINTS=1, PCIE_ENDPOINT_MODE=0
- 1xGen3x8LL -- PCIE_GEN=3, PCIE_ENDPOINTS=1, PCIE_ENDPOINT_MODE=2"
}

if {!($HBM_CHANNELS == 0)} {
    error "This card does not have a HBM memory modules."
}
