-- application_core_empty_arch.vhd: Empty architecture of the APPLICATION_CORE in case the core
-- needs to be disconnected.
-- Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
-- Author(s): Vladislav Valek <vladislav.valek@stud.uni-heidelberg.de>
--
-- SPDX-License-Identifier: CERN-OHL-P-2.0

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

architecture EMPTY of APPLICATION_CORE is
begin

    DMA_RX_MFB_META_PKT_SIZE <= (others => (others => '0'));
    DMA_RX_MFB_META_HDR_META <= (others => (others => '0'));
    DMA_RX_MFB_META_CHAN     <= (others => (others => '0'));

    DMA_RX_MFB_DATA    <= (others => (others => '0'));
    DMA_RX_MFB_SOF     <= (others => (others => '0'));
    DMA_RX_MFB_EOF     <= (others => (others => '0'));
    DMA_RX_MFB_SOF_POS <= (others => (others => '0'));
    DMA_RX_MFB_EOF_POS <= (others => (others => '0'));
    DMA_RX_MFB_SRC_RDY <= (others => '0');

    DMA_TX_MFB_DST_RDY <= (others => '1');

    MI_ARDY <= MI_RD or MI_WR;
    MI_DRD  <= x"DEAD_BEEF";
    MI_DRDY <= MI_RD;
end architecture;
