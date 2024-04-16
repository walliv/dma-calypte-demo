<!-- Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI) -->
<!-- SPDX-License-Identifier: CC-BY-4.0 -->

# AMD Alveo U200

Card information:

- Vendor: AMD/Xilinx
- Name: Alveo U200
- Ethernet ports: 2x QSFP28 (not used)
- PCIe conectors: Edge connector
- [FPGA Card Website](https://www.xilinx.com/products/boards-and-kits/alveo/u200.html)

FPGA specification:

- FPGA part number: `xcu200-fsgd2104-2-e` (basically the same as VU9P)
- Ethernet Hard IP: CMAC (100G Ethernet, not used)
- PCIe Hard IP (up to PCIe Gen3 x16)

## NDK firmware support

PCIe cores that are supported in the NDK firmware:

- PCIE4 primitive
- See the `build/Makefile` file for supported PCIe configurations.

Makefile targets for building the NDK firmware (a.k.a. command for building the design):

- Use `make 50g1ll` command for firmware with 50 Gbps low-latency PCIe (default).

Support for booting the NDK firmware using the nfb-boot tool:

- NO, use JTAG (see below).

## Programming the device

1. Buld the firmware using `make` as described above (*Generate bitstream* using Vivado GUI flow)
2. Connect USB cable to the JTAG interface of the card
3. Open Hardware manager in Vivado (build on 2022.2)
4. Program the device with the generated `*.bit` file

For more information, refer to the [Programming and debugging
manual](https://docs.xilinx.com/r/2022.2-English/ug908-vivado-programming-debugging/Opening-the-Hardware-Manager?tocId=x0two8P7pmYkinePAp~Scg)
of the Vivado

> [!NOTE]
> To build the NDK firmware for this card, you must have the Xilinx Vivado
> installed, including a valid license.
