# Modules.tcl: script that lists all different modules that are instantiated in various configuration of
# the APPLICATION_CORE
# Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
# Author(s): Vladislav Valek <vladislav.valek@stud.uni-heidelberg.de>
#
# SPDX-License-Identifier: Apache-2.0

# Packages
lappend PACKAGES "$OFM_PATH/comp/base/pkg/math_pack.vhd"
lappend PACKAGES "$OFM_PATH/comp/base/pkg/type_pack.vhd"

lappend MOD "$ENTITY_BASE/application_core_empty_arch.vhd"
lappend MOD "$ENTITY_BASE/application_core_ent.vhd"
lappend MOD "$ENTITY_BASE/DevTree.tcl"
