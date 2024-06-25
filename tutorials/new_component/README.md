<!-- Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI) -->
<!-- SPDX-License-Identifier: CC-BY-4.0 -->

# Tutorial: Creating custom component

This section is an advanced one and an interested programmer should first learn
to be a user of the platform through existing tools before he starts to develop
something on his own. However, this tutorial works out of the box and if only
synthesis of simple components is required it is possible to begin right now.
The FPGA platform can be extended by adding subcomponents to the
`APPLICATION_CORE`, usually through specific architecture (for more, see
[/src/app/readme.md](../../src/app/readme.md)). 

The files in `template/` are supplied as the simplest example of a working
subcomponent that could be a part of a hierarchy. A detailed commentary to each
file is provided in the `template_commentary/` directory. 

| Name of the file  | Is necessary?        | Description                                                                                                          |
|:-----------------:|:--------------------:|:---------------------------------------------------------------------------------------------------------------------|
| `updown_cntr.vhd` | YES                  | A demonstrative HDL design file with some instances of subcomponents                                                 |
| `Modules.tcl`     | YES                  | Specification of subcomponents of the HDL file that puts this file to the hierarchy of sources on the FPGA platform. |
| `synth/Makefile`  | NO (but recommended) | Simple Makefile to run a synthesis of the component.                                                                 |

