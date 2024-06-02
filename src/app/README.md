<!-- Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI) -->
<!-- SPDX-License-Identifier: CC-BY-4.0 -->

# Application Core Architecture

The custom components that can benefit from the communication infrastructure
should be placed as a subcomponent of the `APPLICATION_CORE` (this directory).
The [entity](../../src/app/application_core_ent.vhd) needs to remain the same.
When opening this file, the generic parameters passed from the top of the
hierarchy can be observed as well as available ports like MFB interfaces in both
directions, the MI interface for configuration and reading of status information
and the connection to a clock tree. 

The application core is the user-defined set of components that can be
integrated to the FPGA platform on a specific card or universally among all of
the available platforms. The `APPLICATION_CORE` has a split entity and
architecture which allows to develop custom architectures while the entity
remains the same. Currently, multiple architectures are supported with different
features:

| Name  | Description                                                                                                                                                                                                           |
|:-----:|:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| EMPTY | No functionality, output signals are set to default values. This is used mainly for a testing of the communication infrastructure.                                                                                    |
| TEST  | A simple architecture for testing the platform containing the insertion of counter values to the passing data from/to DMA. There is also an HBM IP with memory tester that checks the functionality of the HBM stack. |

Whenever you need to use multiple clocks, a clock-domain crossing needs to be
added because the MFB interface is clocked to the same clock as the DMA engine
(For this purpose, look into the `MFB_ASFIFOX` component inside the `OFM`
repository).

## Adding a new architecture

1. Create an architecture HDL file (the recommended naming scheme for a source
   file is `application_core_<your_name>_arch.vhd`).
2. Add this architecture to the `Modules.tcl` file as a local source (recall
   that local sources are contained within the *MOD* list). Specify the new
   branch within if statements to distinguist your source files from the others.
3. Add subcomponents of the new architecture as external components (recall that
   these belong to the *COMPONENTS* list) in the `Modules.tcl`. Note that each
   remote component that is referenced needs to have its own `Modules.tcl`.
4. Change the type of the architecture to your specific name with the
   `APP_CORE_ARCH` parameter inside
   [/config/core_conf.tcl](../../config/core_conf.tcl).
5. Finished! Now you can build the FPGA design with the defined architecture.

## Adding a new component to the FPGA platform

1. Create a subdirectory in this directory (`/src/app/`) with
   the name of your choice (usually same as the name of the component;
   lowercase, underscore-separated names are recommended).
2. Create design files according to the template in
   `/tutorials/new_component/template/` (VHDL entities as well as
   Verilog/SystemVerilog modules are supported) in that subdirectory.
3. Add instance of this subcomponent to one of the architectures provided or
   create a new architecture.
4. Add this subcomponent as an external component to the `/src/app/Modules.tcl`
   file. 
5. Finished! Now you can build the FPGA design with the new component.
