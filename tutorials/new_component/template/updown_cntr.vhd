-- updown_cntr.vhd: An automatically reversible binary counter
-- Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
-- Author(s): Vladislav Valek <vladislawalek@gmail.com>
--
-- SPDX-License-Identifier: CERN-OHL-P-2.0

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.math_pack.all;

-- This component provides a counter with configurable length that counts up upon restart and
-- automatically reverses its counting direction (froom UP to DOWN and vice versa) upon reaching its
-- maximum value (when counting upwards) or minimum value (when counting down).
entity UPDOWN_CNTR is
    generic (
        -- Bit length of a counter
        LENGTH  : natural := 32);
    port (
        CLK             : in  std_logic;
        RESET           : in  std_logic;
        -- Initial value of the counter after reset
        CNTR_INIT       : in  std_logic_vector(LENGTH -1 downto 0);
        -- Output value of a counter
        CNTR_OUT        : out std_logic_vector(LENGTH -1 downto 0);
        -- Set to 1 if CNTR_OUT reaches the minimum value
        MIN_VAL_REACHED : out std_logic;
        -- Set to 1 if CNTR_OUT reaches the maximum value
        MAX_VAL_REACHED : out std_logic);
end entity;

architecture FULL of UPDOWN_CNTR is
    constant CNTR_MAX_VAL : unsigned (LENGTH -1 downto 0) := (others => '1');

    type cntr_state_t is (S_CNT_UP, S_CNT_DOWN);
    signal cntr_state_pst : cntr_state_t := S_CNT_UP;
    signal cntr_state_nst : cntr_state_t := S_CNT_UP;

    signal cntr_val_pst : unsigned(LENGTH -1 downto 0);
    signal cntr_val_nst : unsigned(LENGTH -1 downto 0);

    signal minval_reached_n_int : std_logic;
begin

cntr_reg_p : process (CLK) is
begin
    if (rising_edge(CLK)) then
        if (RESET = '1') then
            cntr_state_pst <= S_CNT_UP;
            cntr_val_pst   <= unsigned(CNTR_INIT);
        else
            cntr_state_pst <= cntr_state_nst;
            cntr_val_pst   <= cntr_val_nst;
        end if;
    end if;
end process;

cntr_nst_logic_p : process (all) is
begin
    cntr_state_nst <= cntr_state_pst;
    cntr_val_nst   <= cntr_val_pst;

    case cntr_state_pst is
        when S_CNT_UP =>
            cntr_val_nst <= cntr_val_pst + 1;

            if (cntr_val_pst = (CNTR_MAX_VAL -1)) then
                cntr_state_nst <= S_CNT_DOWN;
            end if;

        when S_CNT_DOWN =>
            cntr_val_nst <= cntr_val_pst - 1;

            if (cntr_val_pst = to_unsigned(1, LENGTH -1)) then
                cntr_state_nst <= S_CNT_UP;
            end if;
    end case;
end process;

maxval_and_i : entity work.GEN_AND
    generic map (
        AND_WIDTH => LENGTH)
    port map (
        DI => std_logic_vector(cntr_val_pst),
        DO => MAX_VAL_REACHED);

minval_or_i : entity work.GEN_OR
    generic map (
        OR_WIDTH => LENGTH)
    port map (
        DI => std_logic_vector(cntr_val_pst),
        DO => minval_reached_n_int);

MIN_VAL_REACHED <= not minval_reached_n_int;
CNTR_OUT        <= std_logic_vector(cntr_val_pst);

end architecture;
