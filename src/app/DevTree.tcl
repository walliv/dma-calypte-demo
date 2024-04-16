# DevTree.tcl: contains procedures that generate nodes to the Device Tree of the FPGA
# design
# Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
# Author(s): Vladislav Valek <vladislav.valek@stud.uni-heidelberg.de>
#
# SPDX-License-Identifier: Apache-2.0

proc dts_application {base generics} {
    array set GENERICS $generics

    set app_core_arch $GENERICS(APP_CORE_ARCH)

    set ret ""
    append ret "application {"

    append ret "};"
    return $ret
}
