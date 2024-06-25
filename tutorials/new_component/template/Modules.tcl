# Modules.tcl: modules of the UPDOWN_CNTR
# Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
# Author(s): Vladislav Valek <vladislawalek@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

set GEN_AND_BASE "$OFM_PATH/comp/base/logic/and"
set GEN_MOD_BASE "$OFM_PATH/comp/base/logic/or"

lappend COMPONENTS [list "GEN_AND" $GEN_AND_BASE "FULL" ]
lappend COMPONENTS [list "GEN_OR"  $GEN_MOD_BASE "FULL" ]

lappend MOD "$ENTITY_BASE/updown_cntr.vhd"

lappend PACKAGES "$OFM_PATH/comp/base/pkg/math_pack.vhd"
# lappend PACKAGES "$OFM_PATH/comp/base/pkg/type_pack.vhd"
