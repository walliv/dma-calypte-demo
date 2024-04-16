-- mi_addr_space_pkg.vhd: Package with MI address space definition
-- Copyright (C) 2021 CESNET z. s. p. o.
-- Author(s): Jakub Cabal <cabal@cesnet.cz>
--
-- SPDX-License-Identifier: BSD-3-Clause

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.math_pack.all;
use work.type_pack.all;

package mi_addr_space_pack is

    -- Number of output MI ports
    constant MI_ADC_PORTS : natural := 8;

    -- Address Space definition
    constant MI_ADC_ADDR_BASE : slv_array_t(MI_ADC_PORTS-1 downto 0)(32-1 downto 0)
        := ( 0 => X"0000_0000", -- Test space (debug R/W registers)
             1 => X"0000_1000", -- SDM/SYSMON controller
             2 => X"0000_2000", -- BOOT controller
             3 => X"0000_3000", -- Debug GLS modules
             4 => X"0000_4000", -- Intel JTAG-over-protocol IP
             5 => X"0100_0000", -- DMA controller
             6 => X"0140_0000", -- PCIe Debug space
             7 => X"0200_0000");-- The application

    constant MI_ADC_PORT_TEST    : natural := 0;
    constant MI_ADC_PORT_SENSOR  : natural := 1;
    constant MI_ADC_PORT_BOOT    : natural := 2;
    constant MI_ADC_PORT_GENLOOP : natural := 3;
    constant MI_ADC_PORT_JTAG_IP : natural := 4;
    constant MI_ADC_PORT_DMA     : natural := 5;
    constant MI_ADC_PORT_PCI_DBG : natural := 6;
    constant MI_ADC_PORT_USERAPP : natural := 7;
end package;

package body mi_addr_space_pack is

end;
