-- fpga.vhd: Alveo U55C board top level entity and architecture
-- Copyright (C) 2023 CESNET z. s. p. o.
-- Author(s): Jakub Cabal <cabal@cesnet.cz>
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
use unisim.vcomponents.BUFG;
use unisim.vcomponents.IBUFDS;
use unisim.vcomponents.ICAPE3;

entity FPGA is
port (
    -- 100 MHz external clocks 
    SYSCLK_P      : in    std_logic;
    SYSCLK_N      : in    std_logic;
    HBM_REFCLK_P  : in    std_logic;
    HBM_REFCLK_N  : in    std_logic;

    -- Alveo Satellite Controller (requires Alveo Card Management Solution IP)
    --MSP_GPIO       : in    std_logic_vector(3 downto 0);
    --MSP_UART_RXD   : in    std_logic;
    --MSP_UART_TXD   : out   std_logic;

    -- PCIe
    PCIE_SYSCLK_P : in    std_logic;
    PCIE_SYSCLK_N : in    std_logic;
    PCIE_SYSRST_N : in    std_logic;
    PCIE_RX_P     : in    std_logic_vector(PCIE_LANES -1 downto 0);
    PCIE_RX_N     : in    std_logic_vector(PCIE_LANES -1 downto 0);
    PCIE_TX_P     : out   std_logic_vector(PCIE_LANES -1 downto 0);
    PCIE_TX_N     : out   std_logic_vector(PCIE_LANES -1 downto 0);

    HBM_CATTRIP   : out   std_logic
);
end entity;

architecture FULL of FPGA is

    constant MISC_IN_WIDTH       : integer := 4;
    constant MISC_OUT_WIDTH      : integer := 4;
    constant DMA_MODULES         : integer := PCIE_ENDPOINTS;
    constant DMA_ENDPOINTS       : integer := PCIE_ENDPOINTS;
    constant DEVICE              : string  := "ULTRASCALE";

    signal sysclk_ibuf      : std_logic;
    signal sysclk_bufg      : std_logic;
    signal sysrst_cnt       : unsigned(4 downto 0) := (others => '0');
    signal sysrst           : std_logic := '1';
    
    signal boot_mi_clk      : std_logic;
    signal boot_mi_reset    : std_logic;
    signal boot_mi_addr     : std_logic_vector(32-1 downto 0);
    signal boot_mi_dwr      : std_logic_vector(32-1 downto 0);
    signal boot_mi_wr       : std_logic;
    signal boot_mi_rd       : std_logic;
    signal boot_mi_be       : std_logic_vector((32/8)-1 downto 0);
    signal boot_mi_ardy     : std_logic;
    signal boot_mi_drd      : std_logic_vector(32-1 downto 0);
    signal boot_mi_drdy     : std_logic;
    -- ICAPE3 Controller
    signal boot_reset       : std_logic;
    signal boot_clk         : std_logic;
    signal icap_avail       : std_logic;
    signal icap_csib        : std_logic;
    signal icap_rdwrb       : std_logic;
    signal icap_di          : std_logic_vector(32-1 downto 0);
    signal icap_do          : std_logic_vector(32-1 downto 0);
    -- AXI QSPI Flash Controller
    signal axi_spi_clk      : std_logic;
    signal axi_mi_addr_s    : std_logic_vector(8-1 downto 0);
    signal axi_mi_dwr_s     : std_logic_vector(32-1 downto 0);
    signal axi_mi_wr_s      : std_logic;
    signal axi_mi_rd_s      : std_logic;
    signal axi_mi_be_s      : std_logic_vector((32/8)-1 downto 0);
    signal axi_mi_ardy_s    : std_logic;
    signal axi_mi_drd_s     : std_logic_vector(32-1 downto 0);
    signal axi_mi_drdy_s    : std_logic;

    signal misc_in          : std_logic_vector(MISC_IN_WIDTH-1 downto 0) := (others => '0');
    signal misc_out         : std_logic_vector(MISC_OUT_WIDTH-1 downto 0);
begin

    sysclk_ibufds_i : IBUFDS
    port map (
        I  => SYSCLK_P,
        IB => SYSCLK_N,
        O  => sysclk_ibuf);

    sysclk_bufg_i : BUFG
    port map (
        I => sysclk_ibuf,
        O => sysclk_bufg);

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

    -- =========================================================================
    -- BOOT AND FLASH
    -- =========================================================================
    axi_spi_clk     <= misc_out(0); -- ~100 MHz
    boot_clk        <= misc_out(0); -- ~100 MHz
    boot_reset      <= misc_out(1);

    boot_ctrl_i : entity work.BOOT_CTRL
    generic map(
        ICAP_WBSTAR0 => X"01002000",
        ICAP_WBSTAR1 => X"01002000", --TODO
        DEVICE       => DEVICE,
        BOOT_TYPE    => 1)
    port map(
        MI_CLK        => boot_mi_clk,
        MI_RESET      => boot_mi_reset,
        MI_DWR        => boot_mi_dwr,
        MI_ADDR       => boot_mi_addr,
        MI_BE         => boot_mi_be,
        MI_RD         => boot_mi_rd,
        MI_WR         => boot_mi_wr,
        MI_ARDY       => boot_mi_ardy,
        MI_DRD        => boot_mi_drd,
        MI_DRDY       => boot_mi_drdy,

        BOOT_CLK      => boot_clk,
        BOOT_RESET    => boot_reset,

        BOOT_REQUEST  => open,
        BOOT_IMAGE    => open,

        ICAP_AVAIL    => icap_avail,
        ICAP_CSIB     => icap_csib,
        ICAP_RDWRB    => icap_rdwrb,
        ICAP_DI       => icap_di,
        ICAP_DO       => icap_do,

        BMC_MI_ADDR   => open,
        BMC_MI_DWR    => open,
        BMC_MI_WR     => open,
        BMC_MI_RD     => open,
        BMC_MI_BE     => open,
        BMC_MI_ARDY   => '0',
        BMC_MI_DRD    => (others => '0'),
        BMC_MI_DRDY   => '0',

        AXI_MI_ADDR   => axi_mi_addr_s,
        AXI_MI_DWR    => axi_mi_dwr_s,
        AXI_MI_WR     => axi_mi_wr_s,
        AXI_MI_RD     => axi_mi_rd_s,
        AXI_MI_BE     => axi_mi_be_s,
        AXI_MI_ARDY   => axi_mi_ardy_s,
        AXI_MI_DRD    => axi_mi_drd_s,
        AXI_MI_DRDY   => axi_mi_drdy_s);

    -- ICAPE3 CTRL
    icape3_i : ICAPE3
    generic map (
       DEVICE_ID         => X"76543210", -- only for SIM
       ICAP_AUTO_SWITCH  => "DISABLE",
       SIM_CFG_FILE_NAME => "NONE")
    port map (
       AVAIL   => icap_avail,
       O       => icap_do,
       PRDONE  => open,
       PRERROR => open,
       CLK     => boot_clk,
       CSIB    => icap_csib,
       I       => icap_di,
       RDWRB   => icap_rdwrb);

    axi_qspi_flash_i: entity work.axi_quad_flash_controller
    port map(
        -- clock and reset
        SPI_CLK      => axi_spi_clk,
        CLK          => boot_clk,
        RST          => boot_reset,

        -- MI32 protocol
        AXI_MI_ADDR => axi_mi_addr_s,
        AXI_MI_DWR  => axi_mi_dwr_s,
        AXI_MI_WR   => axi_mi_wr_s,
        AXI_MI_RD   => axi_mi_rd_s,
        AXI_MI_BE   => axi_mi_be_s,
        AXI_MI_ARDY => axi_mi_ardy_s,
        AXI_MI_DRD  => axi_mi_drd_s,
        AXI_MI_DRDY => axi_mi_drdy_s,

        -- STARTUP I/O signals
        CFGCLK      => open,
        CFGMCLK     => open,
        EOS         => open,
        PREQ        => open);

    -- =========================================================================
    -- FPGA COMMON
    -- =========================================================================
    cm_i : entity work.FPGA_COMMON
    generic map (
        USE_PCIE_CLK            => False,

        CLK_COUNT               => 2,
        SYSCLK_PERIOD           => 10.0,
        PLL_MULT_F              => 12.0,
        PLL_MASTER_DIV          => 1,
        PLL_OUT0_DIV_F          => 3.0,
        PLL_OUT_DIV_VECT        => (others => 12),

        PCIE_CONS               => 1,
        PCIE_LANES              => PCIE_LANES,
        PCIE_CLKS               => 1,
        PCIE_ENDPOINTS          => PCIE_ENDPOINTS,
        PCIE_ENDPOINT_TYPE      => PCIE_MOD_ARCH,
        PCIE_ENDPOINT_MODE      => PCIE_ENDPOINT_MODE,

        DMA_STREAMS             => PCIE_ENDPOINTS,
        DMA_RX_CHANNELS         => DMA_RX_CHANNELS,
        DMA_TX_CHANNELS         => DMA_TX_CHANNELS,

        HBM_CHANNELS            => HBM_CHANNELS,

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

        HBM_REFCLK_P            => HBM_REFCLK_P,
        HBM_REFCLK_N            => HBM_REFCLK_N,
        HBM_CATTRIP             => HBM_CATTRIP,

        STATUS_LEDS             => open,

        PCIE_CLK                => open,
        PCIE_RESET              => open,

        BOOT_MI_CLK             => boot_mi_clk,
        BOOT_MI_RESET           => boot_mi_reset,
        BOOT_MI_DWR             => boot_mi_dwr,
        BOOT_MI_ADDR            => boot_mi_addr,
        BOOT_MI_RD              => boot_mi_rd,
        BOOT_MI_WR              => boot_mi_wr,
        BOOT_MI_BE              => boot_mi_be,
        BOOT_MI_DRD             => boot_mi_drd,
        BOOT_MI_ARDY            => boot_mi_ardy,
        BOOT_MI_DRDY            => boot_mi_drdy,

        MISC_IN                 => misc_in,
        MISC_OUT                => misc_out);
end architecture;
