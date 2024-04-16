-- clk_gen_usp.vhd: CLK module for Xilinx UltraScale+ FPGAs
-- Copyright (C) 2022 CESNET z. s. p. o.
-- Author(s): Jakub Cabal <cabal@cesnet.cz>
--
-- SPDX-License-Identifier: BSD-3-Clause

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

use work.math_pack.all;
use work.type_pack.all;

library unisim;
use unisim.vcomponents.all;

architecture USP of COMMON_CLK_GEN is

    -- purpose: This function selects from the PLL_OUT_DIV_VECT generic the chosen division factor.
    -- It is necessary to choose this approcach because the width of PLL_OUT_DIV_VECT can be set
    -- dynamically whereas the amount of divider generics for MMCME4_BASE is fixed. This function
    -- returns the default values for those outputs of the MMCME4_BASE that are not used.
    function f_sanitize_div_fact (
        div_fact_idx : natural)
        return natural is
    begin
        if (div_fact_idx < CLK_WIDTH -1) then
            return PLL_OUT_DIV_VECT(div_fact_idx);
        end if;

        return 20;
    end function;

    signal clkfbout   : std_logic;
    signal clkout_int : std_logic_vector(6 downto 0);
begin

    assert (CLK_WIDTH >= 1 and CLK_WIDTH <= 7)
        report "COMMON_CLK_GEN(USP): unallowed configuration for CLK_WIDTH, the allowed range is from 1 to 7 (inclusively)"
        severity FAILURE;

    INIT_DONE_N <= '0';

    -- NOTE: CLKOUT 0-3 are High-Performance Clocks (UG572), the rest is not!
    mmcm_i : MMCME4_BASE
    generic map (
        BANDWIDTH        => "OPTIMIZED",
        DIVCLK_DIVIDE    => PLL_MASTER_DIV,
        CLKFBOUT_MULT_F  => PLL_MULT_F,
        CLKOUT0_DIVIDE_F => PLL_OUT0_DIV_F,
        CLKOUT1_DIVIDE   => f_sanitize_div_fact(0),
        CLKOUT2_DIVIDE   => f_sanitize_div_fact(1),
        CLKOUT3_DIVIDE   => f_sanitize_div_fact(2),
        CLKOUT4_DIVIDE   => f_sanitize_div_fact(3),
        CLKOUT5_DIVIDE   => f_sanitize_div_fact(4),
        CLKOUT6_DIVIDE   => f_sanitize_div_fact(5),
        CLKIN1_PERIOD    => REFCLK_PERIOD
    ) port map (
        CLKFBOUT  => clkfbout,
        CLKFBOUTB => open,
        CLKOUT0   => clkout_int(0),
        CLKOUT0B  => open,
        CLKOUT1   => clkout_int(1),
        CLKOUT1B  => open,
        CLKOUT2   => clkout_int(2),
        CLKOUT2B  => open,
        CLKOUT3   => clkout_int(3),
        CLKOUT3B  => open,
        CLKOUT4   => clkout_int(4),
        CLKOUT5   => clkout_int(5),
        CLKOUT6   => clkout_int(6),
        CLKFBIN   => clkfbout,
        CLKIN1    => REFCLK,
        LOCKED    => LOCKED,
        PWRDWN    => '0',
        RST       => ASYNC_RESET
    );

    clkout_buf_g: for clk_idx in 0 to (CLK_WIDTH -1) generate
        clkout_buf_i : BUFG
            port map (
                O => CLK_OUT_VECT(clk_idx),
                I => clkout_int(clk_idx)
            );
    end generate;
end architecture;
