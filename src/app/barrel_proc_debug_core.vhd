-- barrel_proc_debug_core.vhd: For debugging the traffic coming through MFB
-- Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
-- Author(s): Vladislav Valek  <xvalek14@vutbr.cz>
--
-- SPDX-License-Identifier: CERN-OHL-P-2.0

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Note:

use work.math_pack.all;
use work.type_pack.all;

library unisim;
use unisim.vcomponents.BUFG;

entity BARREL_PROC_DEBUG_CORE is
    generic(
        -- Width of MI bus
        MI_WIDTH : natural := 32
        );
    port(
        -- =======================================================================
        -- CLOCK AND RESET
        -- =======================================================================
        CLK   : in std_logic;
        RESET : in std_logic;

        RESET_OUT : out std_logic;

        -- =====================================================================
        -- MI interface for SW access
        -- =====================================================================
        MI_ADDR : in  std_logic_vector(MI_WIDTH-1 downto 0);
        MI_DWR  : in  std_logic_vector(MI_WIDTH-1 downto 0);
        MI_BE   : in  std_logic_vector(MI_WIDTH/8-1 downto 0);
        MI_RD   : in  std_logic;
        MI_WR   : in  std_logic;
        MI_DRD  : out std_logic_vector(MI_WIDTH-1 downto 0);
        MI_ARDY : out std_logic;
        MI_DRDY : out std_logic
        );
end entity;

architecture FULL of BARREL_PROC_DEBUG_CORE is

    -- =============================================================================================
    -- Reset FSM
    -- =============================================================================================
    signal rst_fsm_trigg : std_logic;
    type rst_fsm_state_t is (IDLE, RESET_COUNTING);
    signal rst_pst  : rst_fsm_state_t := IDLE;
    signal rst_nst  : rst_fsm_state_t := IDLE;
    signal rst_cntr_pst : unsigned(6 downto 0);
    signal rst_cntr_nst : unsigned(6 downto 0);

    signal rst_int : std_logic;
    signal rst_int_reg : std_logic;
    signal rst_int_reg_1 : std_logic;
    signal rst_int_reg_2 : std_logic;
    signal rst_int_reg_3 : std_logic;
    --signal rst_int_reg_4 : std_logic;
    --signal rst_int_reg_5 : std_logic;

    attribute DONT_TOUCH                    : boolean;
    attribute DONT_TOUCH of rst_int_reg     : signal is true;
    attribute DONT_TOUCH of rst_int_reg_1   : signal is true;
    attribute DONT_TOUCH of rst_int_reg_2   : signal is true;
    attribute DONT_TOUCH of rst_int_reg_3   : signal is true;
    --attribute KEEP of rst_int_reg_4   : signal is true;
    --attribute KEEP of rst_int_reg_5   : signal is true;
    -- attribute mark_debug                           : string;
    -- attribute mark_debug of rst_fsm_trigg        : signal is "true";
    -- attribute mark_debug of rst_pst        : signal is "true";
    -- attribute mark_debug of rst_cntr_pst        : signal is "true";
    -- attribute mark_debug of MI_ADDR        : signal is "true";
    -- attribute mark_debug of MI_DWR        : signal is "true";
    -- attribute mark_debug of MI_RD        : signal is "true";
    -- attribute mark_debug of MI_WR        : signal is "true";
    -- attribute mark_debug of MI_DRDY        : signal is "true";
begin

    MI_ARDY <= MI_RD or MI_WR;
    MI_DRD  <= (others => '0');
    MI_DRDY <= MI_RD;

    -- =============================================================================================
    -- Resetting FSM
    -- =============================================================================================
    rst_fsm_trigg <= '1' when (MI_WR = '1' and MI_ADDR(1 downto 0) = std_logic_vector(to_unsigned(16#00#,2)) and MI_DWR(0) = '1') else '0';

    reset_fsm_state_reg : process (CLK) is
    begin
        if (rising_edge(CLK)) then
            if (RESET = '1') then
                rst_pst      <= IDLE;
                rst_cntr_pst <= (others => '0');
                rst_int_reg  <= '1';
            else
                rst_pst      <= rst_nst;
                rst_cntr_pst <= rst_cntr_nst;
                rst_int_reg  <= rst_int;
            end if;
        end if;
    end process;

    reset_fsm_nst_logic : process (all) is
    begin
        rst_nst      <= rst_pst;
        rst_cntr_nst <= rst_cntr_pst;

        rst_int <= '0';

        case rst_pst is
            when IDLE =>

                if (rst_fsm_trigg = '1') then
                    rst_cntr_nst <= (others => '0');
                    rst_nst      <= RESET_COUNTING;
                end if;

            when RESET_COUNTING =>
                rst_int      <= '1';
                rst_cntr_nst <= rst_cntr_pst + 1;

                if (rst_cntr_pst = 60) then
                    rst_nst <= IDLE;
                end if;
        end case;
    end process;
    
    process (CLK) is
    begin
        if (rising_edge(CLK)) then
                rst_int_reg_1  <= rst_int_reg;
                rst_int_reg_2  <= rst_int_reg_1;
                rst_int_reg_3  <= rst_int_reg_2;
                --rst_int_reg_4  <= rst_int_reg_3;
                --rst_int_reg_5  <= rst_int_reg_4;
        end if;
    end process;
    RESET_OUT <= rst_int_reg_3;

    --mi_rst_buf_i : BUFG
    --port map (
    --    O => RESET_OUT,
    --    I => rst_int_reg_5
    --);
end architecture;
