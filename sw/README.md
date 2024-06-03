<!-- Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI) -->
<!-- SPDX-License-Identifier: CC-BY-4.0 -->

# Software tools

This folder contains useful software tools to interact with the FPGA design or
the development tools. Some dependencies may be required to run the given
scripts (see below). If you want to modify these files for your
application, it is advised to copy them to the `src/app` directory, where
application specific files are located, and files in the current directory as a
reference where comments serve for documentation purposes.

| Name               | Description                                                | Dependiencies                        |
|--------------------|------------------------------------------------------------|--------------------------------------|
| `gls_mod.py`       | Measures data throughput for different packet lengths      | nfb-framework package                |
| `pkt_receive.c`    | Simple reception of data from the FPGA on the host         | nfb-framework package                |
| `pkt_transmit.c`   | Simple packet transmission from the host to the FPGA       | nfb-framework package                |
| `program_fpga.tcl` | Programming of the FPGA device on the PCIe card using JTAG | Vivado tools (Lab Edition or higher) |

> [!NOTE]
> For more information about how to run/compile, check the required file.
