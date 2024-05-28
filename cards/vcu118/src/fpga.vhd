-- fpga.vhd: VCU118  board top level entity and architecture
-- Copyright (C) 2023 CESNET z. s. p. o.
-- Author(s): Vladislav Válek <valekv@cesnet.cz>
--
-- SPDX-License-Identifier: BSD-3-Clause

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.combo_const.all;
use work.combo_user_const.all;

use work.math_pack.all;
use work.type_pack.all;

library unisim;
use unisim.vcomponents.IBUFDS;
use unisim.vcomponents.BUFG;

entity FPGA is
port (
    -- PCIe
    PCIE_SYSCLK_P       : in    std_logic;
    PCIE_SYSCLK_N       : in    std_logic;
    PCIE_SYSRST_N       : in    std_logic;
    PCIE_RX_P           : in    std_logic_vector(PCIE_LANES -1 downto 0);
    PCIE_RX_N           : in    std_logic_vector(PCIE_LANES -1 downto 0);
    PCIE_TX_P           : out   std_logic_vector(PCIE_LANES -1 downto 0);
    PCIE_TX_N           : out   std_logic_vector(PCIE_LANES -1 downto 0);

    -- 300/125 MHz external clock (for a specific frequency, refer to the constr/general.xdc file)
    REFCLK_P            : in    std_logic;
    REFCLK_N            : in    std_logic;

    STATUS_LEDS         : out std_logic_vector(1 downto 0)
);
end entity;

architecture FULL of FPGA is
    -- =============================================================================================
    -- MMCM settings:
    -- =============================================================================================
    -- Output frequency | D     | M     | O     | VCO_freq  |
    -- -----------------|-------|-------|-------|-----------|
    -- 300              | 5     | 63.0  | 5.25  | 1575      |
    -- 350              | 5     | 63.0  | 4.5   | 1575      |
    -- 400              | 5     | 64.0  | 4.0   | 1600      |
    -- 450              | 5     | 63.0  | 3.5   | 1575      |
    -- 500              | 5     | 62.5  | 3.125 | 1562.5    |

    constant MMCM_OUT_FREQ : natural := 350;

    function DeriveMasterDiv ( --D
        freq : natural)
        return natural is
    begin
        case freq is
            when 100 => return 5;
            when 150 => return 5;
            when 200 => return 5;
            when 250 => return 5;
            when 300 => return 5;
            when 350 => return 5;
            when 360 => return 5;
            when 370 => return 5;
            when 380 => return 5;
            when 390 => return 5;
            when 400 => return 5;
            when 420 => return 5;
            when 450 => return 5;
            when 500 => return 5;
            when others => return 0;
        end case;
    end function;

    function DeriveMasterMult ( --M
        freq : natural)
        return real is
    begin
        case freq is
            when 100 => return 64.0;
            when 150 => return 63.75;
            when 200 => return 64.0;
            when 250 => return 63.75;
            when 300 => return 63.0;
            when 350 => return 63.0;
            when 360 => return 63.0;
            when 370 => return 55.5;
            when 380 => return 57.0;
            when 390 => return 58.5;
            when 400 => return 64.0;
            when 420 => return 63.0;
            when 450 => return 63.0;
            when 500 => return 62.5;
            when others => return 0.0;
        end case;
    end function;

    function DeriveOutDiv ( --O
        freq : natural)
        return real is
    begin
        case freq is
            when 100 => return 16.0;
            when 150 => return 10.625;
            when 200 => return 8.0;
            when 250 => return 6.375;
            when 300 => return 5.25;
            when 350 => return 4.5;
            when 360 => return 4.375;
            when 370 => return 3.75;
            when 380 => return 3.75;
            when 390 => return 3.75;
            when 400 => return 4.0;
            when 420 => return 3.75;
            when 450 => return 3.5;
            when 500 => return 3.125;
            when others => return 0.0;
        end case;
    end function;
    -- =============================================================================================

    constant MISC_IN_WIDTH       : integer := 64;
    constant MISC_OUT_WIDTH      : integer := 64+1+1+1;
    constant DEVICE              : string  := "ULTRASCALE";

    signal sysclk_ibuf      : std_logic;
    signal sysclk_bufg      : std_logic;
    signal sysrst_cnt       : unsigned(4 downto 0) := (others => '0');
    signal sysrst           : std_logic := '1';

    signal boot_mi_rd       : std_logic;
    signal boot_mi_wr       : std_logic;
    signal boot_mi_drd      : std_logic_vector(31 downto 0);
    signal boot_mi_ardy     : std_logic;
    signal boot_mi_drdy     : std_logic;
    
    signal misc_in          : std_logic_vector(MISC_IN_WIDTH-1 downto 0) := (others => '0');
    signal misc_out         : std_logic_vector(MISC_OUT_WIDTH-1 downto 0);

begin
    sysclk_ibuf_i : IBUFDS
    port map (
        I  => REFCLK_P,
        IB => REFCLK_N,
        O  => sysclk_ibuf
    );

    sysclk_bufg_i : BUFG
    port map (
        I => sysclk_ibuf,
        O => sysclk_bufg
    );

    -- reset after power up
    process(sysclk_bufg)
    begin
        if rising_edge(sysclk_bufg) then
            if (sysrst_cnt(sysrst_cnt'high) = '0') then
                sysrst_cnt <= sysrst_cnt + 1;
            end if;
            sysrst <= not sysrst_cnt(sysrst_cnt'high);
        end if;
    end process;

    boot_mi_ardy <= boot_mi_rd or boot_mi_wr;
    boot_mi_drdy <= boot_mi_rd;
    boot_mi_drd  <= (others => '0');

    -- FPGA COMMON -------------------------------------------------------------
    cm_i : entity work.FPGA_COMMON
    generic map (
        USE_PCIE_CLK            => FALSE,

        CLK_COUNT               => 2,
        SYSCLK_PERIOD           => 8.0,
        PLL_MULT_F              => DeriveMasterMult(MMCM_OUT_FREQ),
        PLL_MASTER_DIV          => DeriveMasterDiv(MMCM_OUT_FREQ),
        PLL_OUT0_DIV_F          => DeriveOutDiv(MMCM_OUT_FREQ),
        PLL_OUT_DIV_VECT        => (others => 15),

        PCIE_CONS               => 1,
        PCIE_LANES              => PCIE_LANES,
        PCIE_CLKS               => PCIE_ENDPOINTS,
        PCIE_ENDPOINTS          => PCIE_ENDPOINTS,
        PCIE_ENDPOINT_TYPE      => PCIE_MOD_ARCH,
        PCIE_ENDPOINT_MODE      => PCIE_ENDPOINT_MODE,

        DMA_STREAMS             => PCIE_ENDPOINTS,
        DMA_RX_CHANNELS         => DMA_RX_CHANNELS,
        DMA_TX_CHANNELS         => DMA_TX_CHANNELS,

        HBM_CHANNELS            => 0,

        LED_COUNT               => 2,
        MISC_IN_WIDTH           => MISC_IN_WIDTH,
        MISC_OUT_WIDTH          => MISC_OUT_WIDTH,

        DEVICE                  => DEVICE,
        BOARD                   => CARD_NAME)
    port map(
        SYSCLK                  => sysclk_bufg,
        SYSRST                  => sysrst,

        PCIE_SYSCLK_P(0)        => PCIE_SYSCLK_P,
        PCIE_SYSCLK_N(0)        => PCIE_SYSCLK_N,
        PCIE_SYSRST_N(0)        => PCIE_SYSRST_N,
        PCIE_RX_P               => PCIE_RX_P,
        PCIE_RX_N               => PCIE_RX_N,
        PCIE_TX_P               => PCIE_TX_P,
        PCIE_TX_N               => PCIE_TX_N,

        HBM_REFCLK_P            => '1',
        HBM_REFCLK_N            => '0',
        HBM_CATTRIP             => open,

        STATUS_LEDS             => STATUS_LEDS,

        PCIE_CLK                => open,
        PCIE_RESET              => open,

        BOOT_MI_CLK             => open,
        BOOT_MI_RESET           => open,
        BOOT_MI_DWR             => open,
        BOOT_MI_ADDR            => open,
        BOOT_MI_RD              => boot_mi_rd,
        BOOT_MI_WR              => boot_mi_wr,
        BOOT_MI_BE              => open,
        BOOT_MI_DRD             => boot_mi_drd,
        BOOT_MI_ARDY            => boot_mi_ardy,
        BOOT_MI_DRDY            => boot_mi_drdy,

        -- NOTE: currently unused, but can be used
        MISC_IN                 => misc_in,
        MISC_OUT                => misc_out
    );
end architecture;
