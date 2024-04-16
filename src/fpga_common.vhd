-- fpga_common.vhd: Common top level architecture
-- Copyright (C) 2023 CESNET z. s. p. o.
-- Author(s): Jakub Cabal <cabal@cesnet.cz>
--            Vladislav Valek <valekv@cesnet.cz>
--
-- SPDX-License-Identifier: BSD-3-Clause

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.combo_const.all;
use work.combo_user_const.all;

use work.math_pack.all;
use work.type_pack.all;
use work.pcie_meta_pack.all;
use work.mi_addr_space_pack.all;

entity FPGA_COMMON is
generic (
    -- Switch CLK_GEN ref clock to clk_pci, default SYSCLK
    USE_PCIE_CLK            : boolean := false;

    -- The amount of internal clocks. There are always at least one clock to drive the MI
    -- configuration bus
    CLK_COUNT      : natural := 2;
    -- System clock period in ns
    -- PCIE clock period in ns if USE_PCIE_CLK is used
    SYSCLK_PERIOD   : real    := 10.0;
    -- Settings of the MMCM
    -- Multiply factor of main clock (Xilinx: 2-64)
    PLL_MULT_F      : real    := 12.0;
    -- Division factor of main clock (Xilinx: 1-106)
    PLL_MASTER_DIV  : natural := 3;
    -- Output clock dividers (Xilinx: 1-128)
    PLL_OUT0_DIV_F   : real    := 3.0;
    PLL_OUT_DIV_VECT : n_array_t(0 to maximum(0, CLK_COUNT -2)) := (others => 20);

    -- Number of PCIe connectors present on board
    PCIE_CONS               : natural := 1;
    -- Number of PCIe lanes per connector
    PCIE_LANES              : natural := 16;
    -- Number of PCIe clocks per connector (useful for bifurcation)
    PCIE_CLKS               : natural := 1;
    -- Number of instantiated PCIe endpoints
    PCIE_ENDPOINTS          : natural := 1;
    -- Connected PCIe endpoint type: P_TILE, R_TILE, USP
    PCIE_ENDPOINT_TYPE      : string  := "R_TILE";
    -- Connected PCIe endpoint mode: 0 = 1x16 lanes, 1 = 2x8 lanes
    PCIE_ENDPOINT_MODE      : natural := 0;

    -- Number of instantiated DMA modules
    DMA_STREAMS             : natural := 1;
    -- Number of DMA channels per DMA module
    DMA_RX_CHANNELS         : natural := 4;
    DMA_TX_CHANNELS         : natural := 4;

    -- The amount of HBM channels
    HBM_CHANNELS            : natural := 0;

    -- The amount of status LEDs
    LED_COUNT               : natural := 4;
    MISC_IN_WIDTH           : natural := 0;
    MISC_OUT_WIDTH          : natural := 0;

    -- Type of FPGA device: "ULTRASCALE", "AGILEX", "STRATIX10"
    DEVICE                  : string := "AGILEX";
    BOARD                   : string := "400G1"
);
port (
    SYSCLK                  : in std_logic;
    SYSRST                  : in std_logic;

    -- PCIe interface
    PCIE_SYSCLK_P           : in  std_logic_vector(PCIE_CONS*PCIE_CLKS-1 downto 0);
    PCIE_SYSCLK_N           : in  std_logic_vector(PCIE_CONS*PCIE_CLKS-1 downto 0);
    PCIE_SYSRST_N           : in  std_logic_vector(PCIE_CONS-1 downto 0);
    PCIE_RX_P               : in  std_logic_vector(PCIE_CONS*PCIE_LANES-1 downto 0);
    PCIE_RX_N               : in  std_logic_vector(PCIE_CONS*PCIE_LANES-1 downto 0);
    PCIE_TX_P               : out std_logic_vector(PCIE_CONS*PCIE_LANES-1 downto 0);
    PCIE_TX_N               : out std_logic_vector(PCIE_CONS*PCIE_LANES-1 downto 0);

    HBM_REFCLK_P            : in  std_logic;
    HBM_REFCLK_N            : in  std_logic;
    HBM_CATTRIP             : out std_logic;

    STATUS_LEDS             : out   std_logic_vector(LED_COUNT -1 downto 0);

    PCIE_CLK                : out std_logic;
    PCIE_RESET              : out std_logic;

    BOOT_MI_CLK             : out std_logic;
    BOOT_MI_RESET           : out std_logic;
    BOOT_MI_DWR             : out std_logic_vector(31 downto 0);
    BOOT_MI_ADDR            : out std_logic_vector(31 downto 0);
    BOOT_MI_RD              : out std_logic;
    BOOT_MI_WR              : out std_logic;
    BOOT_MI_BE              : out std_logic_vector(3 downto 0);
    BOOT_MI_DRD             : in  std_logic_vector(31 downto 0) := (others => '0');
    BOOT_MI_ARDY            : in  std_logic := '0';
    BOOT_MI_DRDY            : in  std_logic := '0';

    -- Misc interface, board specific
    MISC_IN                 : in    std_logic_vector(MISC_IN_WIDTH-1 downto 0) := (others => '0');
    MISC_OUT                : out   std_logic_vector(MISC_OUT_WIDTH-1 downto 0)
);
end entity;

-- ----------------------------------------------------------------------------
--                        Architecture Declaration
-- ----------------------------------------------------------------------------

architecture FULL of FPGA_COMMON is

    function f_pcie_mfb_regions_calc (PCIE_DIR : string) return natural is
        variable pcie_mfb_regions : natural;
    begin
        pcie_mfb_regions := 0;

        if (PCIE_ENDPOINT_MODE = 0) then -- x16
            pcie_mfb_regions := 2; --1x512b AXI
        elsif (PCIE_ENDPOINT_MODE = 2) then --x8
            pcie_mfb_regions := 1; --1x256b AXI
        end if;

        if (PCIE_DIR="RC") then -- USP RC support up to 4 TLP in word
            pcie_mfb_regions := pcie_mfb_regions*2;
        end if;

        return pcie_mfb_regions;
    end function;

    function f_get_usr_mfb_region_size return natural is
    begin
        if (PCIE_ENDPOINT_MODE = 0) then
            return 8;
        else
            return 4;
        end if;
    end function;

    constant HEARTBEAT_CNT_W : natural := 27;
    constant RESET_WIDTH     : natural := 10;
    constant FPGA_ID_WIDTH   : natural := tsel(DEVICE="ULTRASCALE", 96, 64);
    constant MI_WIDTH        : integer := 32;
    constant HDR_META_WIDTH  : integer := 12;

    constant DMA_MFB_REGIONS     : natural := 1;
    constant DMA_MFB_REGION_SIZE : natural := f_get_usr_mfb_region_size;
    constant DMA_MFB_BLOCK_SIZE  : natural := 8;  -- Number of items in block
    constant DMA_MFB_ITEM_WIDTH  : natural := 8;  -- Width of one item in bits

    -- DMA MFB RQ parameters
    constant DMA_RQ_MFB_REGIONS       : natural := f_pcie_mfb_regions_calc("RQ");
    constant DMA_RQ_MFB_REGION_SIZE   : natural := 1;
    constant DMA_RQ_MFB_BLOCK_SIZE    : natural := 8;
    constant DMA_RQ_MFB_ITEM_WIDTH    : natural := 32;

    -- DMA MFB RC parameters
    constant DMA_RC_MFB_REGIONS     : natural := f_pcie_mfb_regions_calc("RC");
    constant DMA_RC_MFB_REGION_SIZE : natural := 1;
    constant DMA_RC_MFB_BLOCK_SIZE  : natural := 4;
    constant DMA_RC_MFB_ITEM_WIDTH  : natural := 32;

    constant DMA_CQ_MFB_REGIONS     : natural := f_pcie_mfb_regions_calc("CQ");
    constant DMA_CQ_MFB_REGION_SIZE : natural := DMA_RQ_MFB_REGION_SIZE;
    constant DMA_CQ_MFB_BLOCK_SIZE  : natural := DMA_RQ_MFB_BLOCK_SIZE;
    constant DMA_CQ_MFB_ITEM_WIDTH  : natural := DMA_RQ_MFB_ITEM_WIDTH;

    constant DMA_CC_MFB_REGIONS     : natural := f_pcie_mfb_regions_calc("CC");
    constant DMA_CC_MFB_REGION_SIZE : natural := DMA_RC_MFB_REGION_SIZE;
    -- this remains the same as RQ interface beacuse on straddling option enabled, the core supports
    -- only two TLPs on CC interface
    constant DMA_CC_MFB_BLOCK_SIZE  : natural := DMA_RQ_MFB_BLOCK_SIZE;
    constant DMA_CC_MFB_ITEM_WIDTH  : natural := DMA_RC_MFB_ITEM_WIDTH;

    -- =============================================================================================
    -- Clock management
    --
    -- The internal clocking comes from different sources:
    --      1) from external oscillator on ref_clk_in signal
    --      2) from COMMON_CLK_GEN on clk_vector (every bit in this vector has its own group of
    --      reset signals on rst_vector_deser)
    --      3) from PCIE entity on clk_pci where each PCIe endpoint has its own separate clock
    -- =============================================================================================
    -- Indexes of clocks in clk_vector and rst_vector_deser signals
    constant USR_CLK_IDX     : natural := 0;
    constant MI_CLK_IDX      : natural := 1;

    -- clk_gen reference clock
    signal ref_clk_in                    : std_logic;
    signal ref_rst_in                    : std_logic;

    signal init_done_n                   : std_logic;
    signal pll_locked                    : std_logic;
    signal global_reset                  : std_logic;
    signal clk_vector                    : std_logic_vector(CLK_COUNT -1 downto 0);
    signal rst_vector                    : std_logic_vector(CLK_COUNT*RESET_WIDTH -1 downto 0);
    signal rst_vector_deser              : slv_array_t(CLK_COUNT -1 downto 0)(RESET_WIDTH-1 downto 0);

    signal clk_pci                       : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal rst_pci                       : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);

    -- =============================================================================================
    -- Status interface
    -- =============================================================================================
    signal pcie_link_up                  : std_logic_vector(PCIE_ENDPOINTS-1 downto 0) := (others => '0');
    signal xilinx_dna                    : std_logic_vector(95 downto 0);
    signal xilinx_dna_vld                : std_logic;
    signal intel_chip_id                 : std_logic_vector(63 downto 0);
    signal intel_chip_id_vld             : std_logic;
    signal fpga_id                       : std_logic_vector(FPGA_ID_WIDTH-1 downto 0);
    signal fpga_id_vld                   : std_logic := '0';
    signal pcie_fpga_id                  : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(FPGA_ID_WIDTH-1 downto 0);

    -- =============================================================================================
    -- MI interconnect
    -- =============================================================================================
    -- from MTC in the PCIE module
    signal mi_dwr_mtc                    : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(31 downto 0);
    signal mi_addr_mtc                   : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(31 downto 0);
    signal mi_be_mtc                     : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(3 downto 0);
    signal mi_rd_mtc                     : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal mi_wr_mtc                     : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal mi_drd_mtc                    : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(31 downto 0);
    signal mi_ardy_mtc                   : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal mi_drdy_mtc                   : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);

    -- split MI interface to each board device from MTC
    signal mi_adc_dwr                    : slv_array_t     (MI_ADC_PORTS-1 downto 0)(32-1 downto 0);
    signal mi_adc_addr                   : slv_array_t     (MI_ADC_PORTS-1 downto 0)(32-1 downto 0);
    signal mi_adc_be                     : slv_array_t     (MI_ADC_PORTS-1 downto 0)(32/8-1 downto 0);
    signal mi_adc_rd                     : std_logic_vector(MI_ADC_PORTS-1 downto 0);
    signal mi_adc_wr                     : std_logic_vector(MI_ADC_PORTS-1 downto 0);
    signal mi_adc_drd                    : slv_array_t     (MI_ADC_PORTS-1 downto 0)(32-1 downto 0);
    signal mi_adc_ardy                   : std_logic_vector(MI_ADC_PORTS-1 downto 0);
    signal mi_adc_drdy                   : std_logic_vector(MI_ADC_PORTS-1 downto 0);

    -- separate MI interface for DMA to also account multiple PCIE_ENDPOINTS
    -- the DMA for the Endpoint 0 connects to the mi_master_splitter_i but higher-index endpoints
    -- are connected directly to the MTC without further splitting.
    signal dma_mi_dwr                    : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(31 downto 0);
    signal dma_mi_addr                   : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(31 downto 0);
    signal dma_mi_be                     : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(3 downto 0);
    signal dma_mi_rd                     : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal dma_mi_wr                     : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal dma_mi_drd                    : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(31 downto 0);
    signal dma_mi_ardy                   : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal dma_mi_drdy                   : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);

    -- =============================================================================================
    -- DMA <---> PCIE core interface
    -- =============================================================================================
    signal dma_rq_mfb_data               : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_RQ_MFB_REGIONS*DMA_RQ_MFB_REGION_SIZE*DMA_RQ_MFB_BLOCK_SIZE*DMA_RQ_MFB_ITEM_WIDTH-1 downto 0);
    signal dma_rq_mfb_meta               : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_RQ_MFB_REGIONS*PCIE_RQ_META_WIDTH -1 downto 0);
    signal dma_rq_mfb_sof                : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_RQ_MFB_REGIONS-1 downto 0);
    signal dma_rq_mfb_eof                : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_RQ_MFB_REGIONS-1 downto 0);
    signal dma_rq_mfb_sof_pos            : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_RQ_MFB_REGIONS*max(1,log2(DMA_RQ_MFB_REGION_SIZE))-1 downto 0);
    signal dma_rq_mfb_eof_pos            : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_RQ_MFB_REGIONS*max(1,log2(DMA_RQ_MFB_REGION_SIZE*DMA_RQ_MFB_BLOCK_SIZE))-1 downto 0);
    signal dma_rq_mfb_src_rdy            : std_logic_vector(DMA_STREAMS-1 downto 0);
    signal dma_rq_mfb_dst_rdy            : std_logic_vector(DMA_STREAMS-1 downto 0);

    signal dma_rc_mfb_data               : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_RC_MFB_REGIONS*DMA_RC_MFB_REGION_SIZE*DMA_RC_MFB_BLOCK_SIZE*DMA_RC_MFB_ITEM_WIDTH-1 downto 0);
    signal dma_rc_mfb_sof                : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_RC_MFB_REGIONS-1 downto 0);
    signal dma_rc_mfb_eof                : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_RC_MFB_REGIONS-1 downto 0);
    signal dma_rc_mfb_sof_pos            : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_RC_MFB_REGIONS*max(1,log2(DMA_RC_MFB_REGION_SIZE))-1 downto 0);
    signal dma_rc_mfb_eof_pos            : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_RC_MFB_REGIONS*max(1,log2(DMA_RC_MFB_REGION_SIZE*DMA_RC_MFB_BLOCK_SIZE))-1 downto 0);
    signal dma_rc_mfb_src_rdy            : std_logic_vector(DMA_STREAMS-1 downto 0);
    signal dma_rc_mfb_dst_rdy            : std_logic_vector(DMA_STREAMS-1 downto 0);

    signal dma_cq_mfb_data               : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_CQ_MFB_REGIONS*DMA_CQ_MFB_REGION_SIZE*DMA_CQ_MFB_BLOCK_SIZE*DMA_CQ_MFB_ITEM_WIDTH-1 downto 0);
    signal dma_cq_mfb_meta               : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_CQ_MFB_REGIONS*PCIE_CQ_META_WIDTH -1 downto 0);
    signal dma_cq_mfb_sof                : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_CQ_MFB_REGIONS-1 downto 0);
    signal dma_cq_mfb_eof                : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_CQ_MFB_REGIONS-1 downto 0);
    signal dma_cq_mfb_sof_pos            : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_CQ_MFB_REGIONS*max(1,log2(DMA_CQ_MFB_REGION_SIZE))-1 downto 0);
    signal dma_cq_mfb_eof_pos            : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_CQ_MFB_REGIONS*max(1,log2(DMA_CQ_MFB_REGION_SIZE*DMA_CQ_MFB_BLOCK_SIZE))-1 downto 0);
    signal dma_cq_mfb_src_rdy            : std_logic_vector(DMA_STREAMS-1 downto 0);
    signal dma_cq_mfb_dst_rdy            : std_logic_vector(DMA_STREAMS-1 downto 0);

    signal dma_cc_mfb_data               : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_CC_MFB_REGIONS*DMA_CC_MFB_REGION_SIZE*DMA_CC_MFB_BLOCK_SIZE*DMA_CC_MFB_ITEM_WIDTH-1 downto 0);
    signal dma_cc_mfb_meta               : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_CC_MFB_REGIONS*PCIE_CC_META_WIDTH -1 downto 0);
    signal dma_cc_mfb_sof                : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_CC_MFB_REGIONS-1 downto 0);
    signal dma_cc_mfb_eof                : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_CC_MFB_REGIONS-1 downto 0);
    signal dma_cc_mfb_sof_pos            : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_CC_MFB_REGIONS*max(1,log2(DMA_CC_MFB_REGION_SIZE))-1 downto 0);
    signal dma_cc_mfb_eof_pos            : slv_array_t(DMA_STREAMS-1 downto 0)(DMA_CC_MFB_REGIONS*max(1,log2(DMA_CC_MFB_REGION_SIZE*DMA_CC_MFB_BLOCK_SIZE))-1 downto 0);
    signal dma_cc_mfb_src_rdy            : std_logic_vector(DMA_STREAMS-1 downto 0);
    signal dma_cc_mfb_dst_rdy            : std_logic_vector(DMA_STREAMS-1 downto 0);

    -- =============================================================================================
    -- DMA <---> Application core interface
    -- =============================================================================================
    signal app_dma_rx_mfb_meta_pkt_size  : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*log2(DMA_RX_PKT_SIZE_MAX+1)-1 downto 0);
    signal app_dma_rx_mfb_meta_hdr_meta  : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*HDR_META_WIDTH-1 downto 0);
    signal app_dma_rx_mfb_meta_chan      : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*log2(DMA_RX_CHANNELS)-1 downto 0);

    signal app_dma_rx_mfb_data           : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*DMA_MFB_REGION_SIZE*DMA_MFB_BLOCK_SIZE*DMA_MFB_ITEM_WIDTH-1 downto 0);
    signal app_dma_rx_mfb_sof            : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS-1 downto 0);
    signal app_dma_rx_mfb_eof            : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS-1 downto 0);
    signal app_dma_rx_mfb_sof_pos        : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*max(1,log2(DMA_MFB_REGION_SIZE))-1 downto 0);
    signal app_dma_rx_mfb_eof_pos        : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*max(1,log2(DMA_MFB_REGION_SIZE*DMA_MFB_BLOCK_SIZE))-1 downto 0);
    signal app_dma_rx_mfb_src_rdy        : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal app_dma_rx_mfb_dst_rdy        : std_logic_vector(DMA_STREAMS -1 downto 0);

    signal app_dma_tx_mfb_meta_pkt_size  : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*log2(DMA_TX_PKT_SIZE_MAX+1)-1 downto 0);
    signal app_dma_tx_mfb_meta_hdr_meta  : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*HDR_META_WIDTH-1 downto 0);
    signal app_dma_tx_mfb_meta_chan      : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*log2(DMA_TX_CHANNELS)-1 downto 0);

    signal app_dma_tx_mfb_data           : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*DMA_MFB_REGION_SIZE*DMA_MFB_BLOCK_SIZE*DMA_MFB_ITEM_WIDTH-1 downto 0);
    signal app_dma_tx_mfb_sof            : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS-1 downto 0);
    signal app_dma_tx_mfb_eof            : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS-1 downto 0);
    signal app_dma_tx_mfb_sof_pos        : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*max(1,log2(DMA_MFB_REGION_SIZE))-1 downto 0);
    signal app_dma_tx_mfb_eof_pos        : slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*max(1,log2(DMA_MFB_REGION_SIZE*DMA_MFB_BLOCK_SIZE))-1 downto 0);
    signal app_dma_tx_mfb_src_rdy        : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal app_dma_tx_mfb_dst_rdy        : std_logic_vector(DMA_STREAMS -1 downto 0);
    -- =============================================================================================

    -- Counter connected with an LED to indicate clock activity
    signal heartbeat_cnt                 : unsigned(HEARTBEAT_CNT_W-1 downto 0);
begin

    assert (DMA_STREAMS = PCIE_ENDPOINTS)
        report "FPGA_COMMON: the number of DMA_STREAMS should be equal to the amount of PCIE_ENDPOINTS"
        severity FAILURE;

    -- =========================================================================
    --  CLOCK AND RESET GENERATOR
    -- =========================================================================
    clk_gen_g: if USE_PCIE_CLK = true generate
        ref_clk_in <= clk_pci(0);
        ref_rst_in <= rst_pci(0);
    else generate
        ref_clk_in <= SYSCLK;
        ref_rst_in <= SYSRST;
    end generate;

    clk_gen_i : entity work.COMMON_CLK_GEN
    generic map(
        CLK_WIDTH        => CLK_COUNT,
        REFCLK_PERIOD    => SYSCLK_PERIOD,
        PLL_MULT_F       => PLL_MULT_F,
        PLL_MASTER_DIV   => PLL_MASTER_DIV,
        PLL_OUT0_DIV_F   => PLL_OUT0_DIV_F,
        PLL_OUT_DIV_VECT => PLL_OUT_DIV_VECT,

        INIT_DONE_AS_RESET => TRUE,
        DEVICE             => DEVICE
    )
    port map (
        REFCLK       => ref_clk_in,
        ASYNC_RESET  => ref_rst_in,
        LOCKED       => pll_locked,
        INIT_DONE_N  => init_done_n,
        CLK_OUT_VECT => clk_vector
    );

    global_reset_i : entity work.ASYNC_RESET
    generic map (
        TWO_REG  => false,
        OUT_REG  => true,
        REPLICAS => 1
    )
    port map (
        CLK        => ref_clk_in,
        ASYNC_RST  => not pll_locked,
        OUT_RST(0) => global_reset
    );

    reset_tree_gen_i : entity work.RESET_TREE_GEN
    generic map(
        CLK_COUNT    => CLK_COUNT,
        RST_REPLICAS => RESET_WIDTH
    )
    port map (
        STABLE_CLK   => ref_clk_in,
        GLOBAL_RESET => global_reset,
        CLK_VECTOR   => clk_vector,
        RST_VECTOR   => rst_vector
    );

    rst_vector_deser <= slv_array_deser(rst_vector, CLK_COUNT);

    -- usefull clocks for boot control in top-level
    PCIE_CLK    <= clk_pci(0);
    PCIE_RESET  <= rst_pci(0);

    MISC_OUT(0) <= clk_vector(MI_CLK_IDX);
    MISC_OUT(1) <= rst_vector_deser(MI_CLK_IDX)(0);
    MISC_OUT(2) <= clk_vector(USR_CLK_IDX);
    MISC_OUT(3) <= rst_vector_deser(USR_CLK_IDX)(0);

    -- =========================================================================
    --                      PCIe module instance and connections
    -- =========================================================================
    pcie_i : entity work.PCIE
    generic map (
        BAR0_BASE_ADDR      => BAR0_BASE_ADDR,
        BAR1_BASE_ADDR      => BAR1_BASE_ADDR,
        BAR2_BASE_ADDR      => BAR2_BASE_ADDR,
        BAR3_BASE_ADDR      => BAR3_BASE_ADDR,
        BAR4_BASE_ADDR      => BAR4_BASE_ADDR,
        BAR5_BASE_ADDR      => BAR5_BASE_ADDR,
        EXP_ROM_BASE_ADDR   => EXP_ROM_BASE_ADDR,

        CQ_MFB_REGIONS      => DMA_CQ_MFB_REGIONS,
        CQ_MFB_REGION_SIZE  => DMA_CQ_MFB_REGION_SIZE,
        CQ_MFB_BLOCK_SIZE   => DMA_CQ_MFB_BLOCK_SIZE,
        CQ_MFB_ITEM_WIDTH   => DMA_CQ_MFB_ITEM_WIDTH,

        RC_MFB_REGIONS      => DMA_RC_MFB_REGIONS,
        RC_MFB_REGION_SIZE  => DMA_RC_MFB_REGION_SIZE,
        RC_MFB_BLOCK_SIZE   => DMA_RC_MFB_BLOCK_SIZE,
        RC_MFB_ITEM_WIDTH   => DMA_RC_MFB_ITEM_WIDTH,

        CC_MFB_REGIONS      => DMA_CC_MFB_REGIONS,
        CC_MFB_REGION_SIZE  => DMA_CC_MFB_REGION_SIZE,
        CC_MFB_BLOCK_SIZE   => DMA_CC_MFB_BLOCK_SIZE,
        CC_MFB_ITEM_WIDTH   => DMA_CC_MFB_ITEM_WIDTH,

        RQ_MFB_REGIONS      => DMA_RQ_MFB_REGIONS,
        RQ_MFB_REGION_SIZE  => DMA_RQ_MFB_REGION_SIZE,
        RQ_MFB_BLOCK_SIZE   => DMA_RQ_MFB_BLOCK_SIZE,
        RQ_MFB_ITEM_WIDTH   => DMA_RQ_MFB_ITEM_WIDTH,

        PCIE_ENDPOINT_TYPE  => PCIE_ENDPOINT_TYPE,
        PCIE_ENDPOINT_MODE  => PCIE_ENDPOINT_MODE,
        PCIE_ENDPOINTS      => PCIE_ENDPOINTS,
        PCIE_CLKS           => PCIE_CLKS,
        PCIE_CONS           => PCIE_CONS,
        PCIE_LANES          => PCIE_LANES,

        XVC_ENABLE          => VIRTUAL_DEBUG_ENABLE,
        CARD_ID_WIDTH       => FPGA_ID_WIDTH,
        DEVICE              => DEVICE
    )
    port map (
        PCIE_SYSCLK_P       => PCIE_SYSCLK_P,
        PCIE_SYSCLK_N       => PCIE_SYSCLK_N,
        PCIE_SYSRST_N       => PCIE_SYSRST_N,
        INIT_DONE_N         => init_done_n,
        PCIE_USER_CLK       => clk_pci,
        PCIE_USER_RESET     => rst_pci,

        PCIE_RX_P           => PCIE_RX_P,
        PCIE_RX_N           => PCIE_RX_N,
        PCIE_TX_P           => PCIE_TX_P,
        PCIE_TX_N           => PCIE_TX_N,

        PCIE_LINK_UP        => pcie_link_up,
        PCIE_MPS            => open,
        PCIE_MRRS           => open,
        PCIE_EXT_TAG_EN     => open,
        PCIE_10B_TAG_REQ_EN => open,
        PCIE_RCB_SIZE       => open,
        CARD_ID             => pcie_fpga_id,

        DMA_RQ_MFB_DATA     => dma_rq_mfb_data,
        DMA_RQ_MFB_META     => dma_rq_mfb_meta,
        DMA_RQ_MFB_SOF      => dma_rq_mfb_sof,
        DMA_RQ_MFB_EOF      => dma_rq_mfb_eof,
        DMA_RQ_MFB_SOF_POS  => dma_rq_mfb_sof_pos,
        DMA_RQ_MFB_EOF_POS  => dma_rq_mfb_eof_pos,
        DMA_RQ_MFB_SRC_RDY  => dma_rq_mfb_src_rdy,
        DMA_RQ_MFB_DST_RDY  => dma_rq_mfb_dst_rdy,

        DMA_RC_MFB_DATA     => dma_rc_mfb_data,
        DMA_RC_MFB_META     => open,
        DMA_RC_MFB_SOF      => dma_rc_mfb_sof,
        DMA_RC_MFB_EOF      => dma_rc_mfb_eof,
        DMA_RC_MFB_SOF_POS  => dma_rc_mfb_sof_pos,
        DMA_RC_MFB_EOF_POS  => dma_rc_mfb_eof_pos,
        DMA_RC_MFB_SRC_RDY  => dma_rc_mfb_src_rdy,
        DMA_RC_MFB_DST_RDY  => dma_rc_mfb_dst_rdy,

        DMA_CQ_MFB_DATA     => dma_cq_mfb_data,
        DMA_CQ_MFB_META     => dma_cq_mfb_meta,
        DMA_CQ_MFB_SOF      => dma_cq_mfb_sof,
        DMA_CQ_MFB_EOF      => dma_cq_mfb_eof,
        DMA_CQ_MFB_SOF_POS  => dma_cq_mfb_sof_pos,
        DMA_CQ_MFB_EOF_POS  => dma_cq_mfb_eof_pos,
        DMA_CQ_MFB_SRC_RDY  => dma_cq_mfb_src_rdy,
        DMA_CQ_MFB_DST_RDY  => dma_cq_mfb_dst_rdy,

        DMA_CC_MFB_DATA     => dma_cc_mfb_data,
        DMA_CC_MFB_META     => dma_cc_mfb_meta,
        DMA_CC_MFB_SOF      => dma_cc_mfb_sof,
        DMA_CC_MFB_EOF      => dma_cc_mfb_eof,
        DMA_CC_MFB_SOF_POS  => dma_cc_mfb_sof_pos,
        DMA_CC_MFB_EOF_POS  => dma_cc_mfb_eof_pos,
        DMA_CC_MFB_SRC_RDY  => dma_cc_mfb_src_rdy,
        DMA_CC_MFB_DST_RDY  => dma_cc_mfb_dst_rdy,

        MI_CLK              => clk_vector(MI_CLK_IDX),
        MI_RESET            => rst_vector_deser(MI_CLK_IDX)(1),

        MI_DWR_MTC          => mi_dwr_mtc,
        MI_ADDR_MTC         => mi_addr_mtc,
        MI_BE_MTC           => mi_be_mtc,
        MI_RD_MTC           => mi_rd_mtc,
        MI_WR_MTC           => mi_wr_mtc,
        MI_DRD_MTC          => mi_drd_mtc,
        MI_ARDY_MTC         => mi_ardy_mtc,
        MI_DRDY_MTC         => mi_drdy_mtc,

        MI_DWR              => mi_adc_dwr (MI_ADC_PORT_PCI_DBG),
        MI_ADDR             => mi_adc_addr(MI_ADC_PORT_PCI_DBG),
        MI_BE               => mi_adc_be  (MI_ADC_PORT_PCI_DBG),
        MI_RD               => mi_adc_rd  (MI_ADC_PORT_PCI_DBG),
        MI_WR               => mi_adc_wr  (MI_ADC_PORT_PCI_DBG),
        MI_DRD              => mi_adc_drd (MI_ADC_PORT_PCI_DBG),
        MI_ARDY             => mi_adc_ardy(MI_ADC_PORT_PCI_DBG),
        MI_DRDY             => mi_adc_drdy(MI_ADC_PORT_PCI_DBG)
    );

    cdc_pcie_up_g: for i in 0 to PCIE_ENDPOINTS-1 generate
        cdc_pcie_fpga_id_i: entity work.ASYNC_OPEN_LOOP_SMD
        generic map(
            DATA_WIDTH => FPGA_ID_WIDTH
        )
        port map(
            ACLK     => clk_vector(MI_CLK_IDX),
            BCLK     => clk_pci(i),
            ARST     => '0',
            BRST     => '0',
            ADATAIN  => fpga_id,
            BDATAOUT => pcie_fpga_id(i)
        );
    end generate;

    -- =========================================================================
    --  MI ADDRESS DECODER
    -- =========================================================================
    mi_master_splitter_i : entity work.MI_SPLITTER_PLUS_GEN
    generic map(
        ADDR_WIDTH    => MI_WIDTH,
        DATA_WIDTH    => MI_WIDTH,
        PORTS         => MI_ADC_PORTS,
        ADDR_BASE     => MI_ADC_ADDR_BASE,
        DEVICE        => DEVICE
    )
    port map(
        CLK        => clk_vector(MI_CLK_IDX),
        RESET      => rst_vector_deser(MI_CLK_IDX)(2),

        RX_DWR     => mi_dwr_mtc(0),
        RX_ADDR    => mi_addr_mtc(0),
        RX_BE      => mi_be_mtc(0),
        RX_RD      => mi_rd_mtc(0),
        RX_WR      => mi_wr_mtc(0),
        RX_ARDY    => mi_ardy_mtc(0),
        RX_DRD     => mi_drd_mtc(0),
        RX_DRDY    => mi_drdy_mtc(0),

        TX_DWR     => mi_adc_dwr ,
        TX_ADDR    => mi_adc_addr,
        TX_BE      => mi_adc_be  ,
        TX_RD      => mi_adc_rd  ,
        TX_WR      => mi_adc_wr  ,
        TX_ARDY    => mi_adc_ardy,
        TX_DRD     => mi_adc_drd ,
        TX_DRDY    => mi_adc_drdy
    );

    -- boot control module is in top-level
    BOOT_MI_CLK   <= clk_vector(MI_CLK_IDX);
    BOOT_MI_RESET <= rst_vector_deser(MI_CLK_IDX)(3);
    BOOT_MI_DWR   <= mi_adc_dwr (MI_ADC_PORT_BOOT);
    BOOT_MI_ADDR  <= mi_adc_addr(MI_ADC_PORT_BOOT);
    BOOT_MI_BE    <= mi_adc_be  (MI_ADC_PORT_BOOT);
    BOOT_MI_RD    <= mi_adc_rd  (MI_ADC_PORT_BOOT);
    BOOT_MI_WR    <= mi_adc_wr  (MI_ADC_PORT_BOOT);
    mi_adc_ardy(MI_ADC_PORT_BOOT) <= BOOT_MI_ARDY;
    mi_adc_drd (MI_ADC_PORT_BOOT) <= BOOT_MI_DRD;
    mi_adc_drdy(MI_ADC_PORT_BOOT) <= BOOT_MI_DRDY;

    -- =========================================================================
    --  MI TEST SPACE AND SDM/SYSMON INTERFACE
    -- =========================================================================
    mi_test_space_i : entity work.MI_TEST_SPACE
    generic map (
        DEVICE  => DEVICE
    )
    port map (
        CLK     => clk_vector(MI_CLK_IDX),
        RESET   => rst_vector_deser(MI_CLK_IDX)(4),
        MI_DWR  => mi_adc_dwr(MI_ADC_PORT_TEST),
        MI_ADDR => mi_adc_addr(MI_ADC_PORT_TEST),
        MI_BE   => mi_adc_be(MI_ADC_PORT_TEST),
        MI_RD   => mi_adc_rd(MI_ADC_PORT_TEST),
        MI_WR   => mi_adc_wr(MI_ADC_PORT_TEST),
        MI_DRD  => mi_adc_drd(MI_ADC_PORT_TEST),
        MI_ARDY => mi_adc_ardy(MI_ADC_PORT_TEST),
        MI_DRDY => mi_adc_drdy(MI_ADC_PORT_TEST)
    );

    sdm_ctrl_i: entity work.SDM_CTRL
    Generic map (
        DATA_WIDTH => MI_WIDTH,
        ADDR_WIDTH => MI_WIDTH,
        DEVICE     => DEVICE
    )
    Port map (
        CLK     => clk_vector(MI_CLK_IDX),
        RESET   => rst_vector_deser(MI_CLK_IDX)(5),
        MI_DWR  => mi_adc_dwr(MI_ADC_PORT_SENSOR),
        MI_ADDR => mi_adc_addr(MI_ADC_PORT_SENSOR),
        MI_RD   => mi_adc_rd(MI_ADC_PORT_SENSOR),
        MI_WR   => mi_adc_wr(MI_ADC_PORT_SENSOR),
        MI_BE   => mi_adc_be(MI_ADC_PORT_SENSOR),
        MI_DRD  => mi_adc_drd(MI_ADC_PORT_SENSOR),
        MI_ARDY => mi_adc_ardy(MI_ADC_PORT_SENSOR),
        MI_DRDY => mi_adc_drdy(MI_ADC_PORT_SENSOR),

        CHIP_ID     => intel_chip_id,
        CHIP_ID_VLD => intel_chip_id_vld
    );

    -- =========================================================================
    -- FPGA ID LOGIC
    -- =========================================================================
    hwid_i : entity work.hwid
    generic map (
        DEVICE          => DEVICE
    )
    port map (
        CLK             => clk_vector(MI_CLK_IDX),
        XILINX_DNA      => xilinx_dna,
        XILINX_DNA_VLD  => xilinx_dna_vld
    );

    fpga_id_usp_g: if (DEVICE = "ULTRASCALE") generate
        fpga_id     <= xilinx_dna;
        fpga_id_vld <= xilinx_dna_vld;
    end generate;

    fpga_id_intel_g: if (DEVICE = "STRATIX10" or DEVICE = "AGILEX") generate
        fpga_id     <= intel_chip_id;
        fpga_id_vld <= intel_chip_id_vld;
    end generate;

    -- =========================================================================
    --  DMA MODULE
    -- =========================================================================
    dma_i : entity work.DMA
    generic map (
        DEVICE               => DEVICE                    ,
        DMA_STREAMS          => DMA_STREAMS               ,

        USR_MFB_REGIONS      => DMA_MFB_REGIONS           ,
        USR_MFB_REGION_SIZE  => DMA_MFB_REGION_SIZE       ,
        USR_MFB_BLOCK_SIZE   => DMA_MFB_BLOCK_SIZE        ,
        USR_MFB_ITEM_WIDTH   => DMA_MFB_ITEM_WIDTH        ,

        PCIE_RQ_MFB_REGIONS     => DMA_RQ_MFB_REGIONS     ,
        PCIE_RQ_MFB_REGION_SIZE => DMA_RQ_MFB_REGION_SIZE ,
        PCIE_RQ_MFB_BLOCK_SIZE  => DMA_RQ_MFB_BLOCK_SIZE  ,
        PCIE_RQ_MFB_ITEM_WIDTH  => DMA_RQ_MFB_ITEM_WIDTH  ,

        PCIE_RC_MFB_REGIONS     => DMA_RC_MFB_REGIONS     ,
        PCIE_RC_MFB_REGION_SIZE => DMA_RC_MFB_REGION_SIZE ,
        PCIE_RC_MFB_BLOCK_SIZE  => DMA_RC_MFB_BLOCK_SIZE  ,
        PCIE_RC_MFB_ITEM_WIDTH  => DMA_RC_MFB_ITEM_WIDTH  ,

        PCIE_CQ_MFB_REGIONS     => DMA_CQ_MFB_REGIONS     ,
        PCIE_CQ_MFB_REGION_SIZE => DMA_CQ_MFB_REGION_SIZE ,
        PCIE_CQ_MFB_BLOCK_SIZE  => DMA_CQ_MFB_BLOCK_SIZE  ,
        PCIE_CQ_MFB_ITEM_WIDTH  => DMA_CQ_MFB_ITEM_WIDTH  ,

        PCIE_CC_MFB_REGIONS     => DMA_CC_MFB_REGIONS     ,
        PCIE_CC_MFB_REGION_SIZE => DMA_CC_MFB_REGION_SIZE ,
        PCIE_CC_MFB_BLOCK_SIZE  => DMA_CC_MFB_BLOCK_SIZE  ,
        PCIE_CC_MFB_ITEM_WIDTH  => DMA_CC_MFB_ITEM_WIDTH  ,

        HDR_META_WIDTH       => HDR_META_WIDTH            ,

        RX_CHANNELS          => DMA_RX_CHANNELS           ,
        RX_PTR_WIDTH         => DMA_RX_DATA_PTR_W         ,
        RX_BLOCKING_MODE     => DMA_RX_BLOCKING_MODE      ,
        RX_PKT_SIZE_MAX      => DMA_RX_PKT_SIZE_MAX     ,

        TX_CHANNELS          => DMA_TX_CHANNELS           ,
        TX_PTR_WIDTH         => DMA_TX_DATA_PTR_W         ,
        TX_PKT_SIZE_MAX      => DMA_TX_PKT_SIZE_MAX     ,

        RX_GEN_EN            => RX_GEN_EN                 ,
        TX_GEN_EN            => TX_GEN_EN                 ,

        DMA_DEBUG_ENABLE     => DMA_DEBUG_ENABLE          ,
        GEN_LOOP_EN          => DMA_GEN_LOOP_EN
    )
    port map (
        MI_CLK     => clk_vector(MI_CLK_IDX),
        MI_RESET   => rst_vector_deser(MI_CLK_IDX)(6),
        USR_CLK    => clk_pci,
        USR_RESET  => rst_pci,

        RX_USR_MFB_META_PKT_SIZE => app_dma_rx_mfb_meta_pkt_size,
        RX_USR_MFB_META_HDR_META => app_dma_rx_mfb_meta_hdr_meta,
        RX_USR_MFB_META_CHAN     => app_dma_rx_mfb_meta_chan,

        RX_USR_MFB_DATA     => app_dma_rx_mfb_data,
        RX_USR_MFB_SOF      => app_dma_rx_mfb_sof,
        RX_USR_MFB_EOF      => app_dma_rx_mfb_eof,
        RX_USR_MFB_SOF_POS  => app_dma_rx_mfb_sof_pos,
        RX_USR_MFB_EOF_POS  => app_dma_rx_mfb_eof_pos,
        RX_USR_MFB_SRC_RDY  => app_dma_rx_mfb_src_rdy,
        RX_USR_MFB_DST_RDY  => app_dma_rx_mfb_dst_rdy,

        TX_USR_MFB_META_PKT_SIZE => app_dma_tx_mfb_meta_pkt_size,
        TX_USR_MFB_META_HDR_META => app_dma_tx_mfb_meta_hdr_meta,
        TX_USR_MFB_META_CHAN     => app_dma_tx_mfb_meta_chan,

        TX_USR_MFB_DATA     => app_dma_tx_mfb_data,
        TX_USR_MFB_SOF      => app_dma_tx_mfb_sof,
        TX_USR_MFB_EOF      => app_dma_tx_mfb_eof,
        TX_USR_MFB_SOF_POS  => app_dma_tx_mfb_sof_pos,
        TX_USR_MFB_EOF_POS  => app_dma_tx_mfb_eof_pos,
        TX_USR_MFB_SRC_RDY  => app_dma_tx_mfb_src_rdy,
        TX_USR_MFB_DST_RDY  => app_dma_tx_mfb_dst_rdy,

        PCIE_RQ_MFB_DATA    => dma_rq_mfb_data,
        PCIE_RQ_MFB_META    => dma_rq_mfb_meta,
        PCIE_RQ_MFB_SOF     => dma_rq_mfb_sof,
        PCIE_RQ_MFB_EOF     => dma_rq_mfb_eof,
        PCIE_RQ_MFB_SOF_POS => dma_rq_mfb_sof_pos,
        PCIE_RQ_MFB_EOF_POS => dma_rq_mfb_eof_pos,
        PCIE_RQ_MFB_SRC_RDY => dma_rq_mfb_src_rdy,
        PCIE_RQ_MFB_DST_RDY => dma_rq_mfb_dst_rdy,

        PCIE_RC_MFB_DATA    => dma_rc_mfb_data,
        PCIE_RC_MFB_SOF     => dma_rc_mfb_sof,
        PCIE_RC_MFB_EOF     => dma_rc_mfb_eof,
        PCIE_RC_MFB_SOF_POS => dma_rc_mfb_sof_pos,
        PCIE_RC_MFB_EOF_POS => dma_rc_mfb_eof_pos,
        PCIE_RC_MFB_SRC_RDY => dma_rc_mfb_src_rdy,
        PCIE_RC_MFB_DST_RDY => dma_rc_mfb_dst_rdy,

        PCIE_CQ_MFB_DATA    => dma_cq_mfb_data,
        PCIE_CQ_MFB_META    => dma_cq_mfb_meta,
        PCIE_CQ_MFB_SOF     => dma_cq_mfb_sof,
        PCIE_CQ_MFB_EOF     => dma_cq_mfb_eof,
        PCIE_CQ_MFB_SOF_POS => dma_cq_mfb_sof_pos,
        PCIE_CQ_MFB_EOF_POS => dma_cq_mfb_eof_pos,
        PCIE_CQ_MFB_SRC_RDY => dma_cq_mfb_src_rdy,
        PCIE_CQ_MFB_DST_RDY => dma_cq_mfb_dst_rdy,

        PCIE_CC_MFB_DATA    => dma_cc_mfb_data,
        PCIE_CC_MFB_META    => dma_cc_mfb_meta,
        PCIE_CC_MFB_SOF     => dma_cc_mfb_sof,
        PCIE_CC_MFB_EOF     => dma_cc_mfb_eof,
        PCIE_CC_MFB_SOF_POS => dma_cc_mfb_sof_pos,
        PCIE_CC_MFB_EOF_POS => dma_cc_mfb_eof_pos,
        PCIE_CC_MFB_SRC_RDY => dma_cc_mfb_src_rdy,
        PCIE_CC_MFB_DST_RDY => dma_cc_mfb_dst_rdy,

        MI_ADDR             => dma_mi_addr,
        MI_DWR              => dma_mi_dwr,
        MI_BE               => dma_mi_be,
        MI_RD               => dma_mi_rd,
        MI_WR               => dma_mi_wr,
        MI_DRD              => dma_mi_drd,
        MI_ARDY             => dma_mi_ardy,
        MI_DRDY             => dma_mi_drdy,

        GEN_LOOP_MI_ADDR    => mi_adc_addr(MI_ADC_PORT_GENLOOP),
        GEN_LOOP_MI_DWR     => mi_adc_dwr(MI_ADC_PORT_GENLOOP),
        GEN_LOOP_MI_BE      => mi_adc_be(MI_ADC_PORT_GENLOOP),
        GEN_LOOP_MI_RD      => mi_adc_rd(MI_ADC_PORT_GENLOOP),
        GEN_LOOP_MI_WR      => mi_adc_wr(MI_ADC_PORT_GENLOOP),
        GEN_LOOP_MI_DRD     => mi_adc_drd(MI_ADC_PORT_GENLOOP),
        GEN_LOOP_MI_ARDY    => mi_adc_ardy(MI_ADC_PORT_GENLOOP),
        GEN_LOOP_MI_DRDY    => mi_adc_drdy(MI_ADC_PORT_GENLOOP)
    );

    -- =============================================================================================
    -- MI interface connection for DMA controller(s)
    -- =============================================================================================
    -- Connect to MI ADC for PCIe Endpoint 0
    dma_mi_dwr (0) <= mi_adc_dwr(MI_ADC_PORT_DMA);
    dma_mi_addr(0) <= mi_adc_addr(MI_ADC_PORT_DMA);
    dma_mi_rd  (0) <= mi_adc_rd(MI_ADC_PORT_DMA);
    dma_mi_wr  (0) <= mi_adc_wr(MI_ADC_PORT_DMA);
    dma_mi_be  (0) <= mi_adc_be(MI_ADC_PORT_DMA);
    mi_adc_drd(MI_ADC_PORT_DMA)  <= dma_mi_drd (0);
    mi_adc_ardy(MI_ADC_PORT_DMA) <= dma_mi_ardy(0);
    mi_adc_drdy(MI_ADC_PORT_DMA) <= dma_mi_drdy(0);

    -- If there are multiple PCIe endpoints, the DMA modules with index 1 and higher are connected
    -- directly to the MTC module. There is no split from the other endpoints. The control logic for
    -- other devices is connected only to endpoint 0.
    dma_mi_connect_g: if (PCIE_ENDPOINTS > 1) generate
        dma_mi_dwr(PCIE_ENDPOINTS-1 downto 1)  <= mi_dwr_mtc(PCIE_ENDPOINTS-1 downto 1);
        dma_mi_addr(PCIE_ENDPOINTS-1 downto 1) <= mi_addr_mtc(PCIE_ENDPOINTS-1 downto 1);
        dma_mi_rd(PCIE_ENDPOINTS-1 downto 1)   <= mi_rd_mtc(PCIE_ENDPOINTS-1 downto 1);
        dma_mi_wr(PCIE_ENDPOINTS-1 downto 1)   <= mi_wr_mtc(PCIE_ENDPOINTS-1 downto 1);
        dma_mi_be(PCIE_ENDPOINTS-1 downto 1)   <= mi_be_mtc(PCIE_ENDPOINTS-1 downto 1);
        mi_drd_mtc (PCIE_ENDPOINTS-1 downto 1) <= dma_mi_drd (PCIE_ENDPOINTS-1 downto 1);
        mi_ardy_mtc(PCIE_ENDPOINTS-1 downto 1) <= dma_mi_ardy(PCIE_ENDPOINTS-1 downto 1);
        mi_drdy_mtc(PCIE_ENDPOINTS-1 downto 1) <= dma_mi_drdy(PCIE_ENDPOINTS-1 downto 1);
    end generate;

    -- =========================================================================
    --  THE APPLICATION/ USER LOGIC
    -- =========================================================================
    app_i : entity work.APPLICATION_CORE
    generic map (
        PCIE_ENDPOINTS        => PCIE_ENDPOINTS,
        DMA_STREAMS           => DMA_STREAMS,

        DMA_RX_CHANNELS       => DMA_RX_CHANNELS,
        DMA_TX_CHANNELS       => DMA_TX_CHANNELS,
        DMA_HDR_META_WIDTH    => HDR_META_WIDTH,

        DMA_RX_PKT_SIZE_MAX   => DMA_RX_PKT_SIZE_MAX,
        DMA_TX_PKT_SIZE_MAX   => DMA_TX_PKT_SIZE_MAX,

        DMA_MFB_REGIONS       => DMA_MFB_REGIONS,
        DMA_MFB_REGION_SIZE   => DMA_MFB_REGION_SIZE,
        DMA_MFB_BLOCK_SIZE    => DMA_MFB_BLOCK_SIZE,
        DMA_MFB_ITEM_WIDTH    => DMA_MFB_ITEM_WIDTH,

        HBM_CHANNELS          => HBM_CHANNELS,

        MI_WIDTH              => MI_WIDTH,
        CLK_WIDTH             => CLK_COUNT,
        RESET_WIDTH           => RESET_WIDTH,
        FPGA_ID_WIDTH         => FPGA_ID_WIDTH,

        BOARD                 => BOARD,
        DEVICE                => DEVICE
    )
    port map (
        CLK_VECTOR         => clk_vector,
        RESET_VECTOR       => rst_vector_deser,

        PCIE_USER_CLK      => clk_pci,
        PCIE_USER_RESET    => rst_pci,

        PCIE_LINK_UP       => pcie_link_up,
        FPGA_ID            => fpga_id,
        FPGA_ID_VLD        => fpga_id_vld,

        DMA_RX_MFB_META_PKT_SIZE => app_dma_rx_mfb_meta_pkt_size,
        DMA_RX_MFB_META_HDR_META => app_dma_rx_mfb_meta_hdr_meta,
        DMA_RX_MFB_META_CHAN     => app_dma_rx_mfb_meta_chan,

        DMA_RX_MFB_DATA     => app_dma_rx_mfb_data,
        DMA_RX_MFB_SOF      => app_dma_rx_mfb_sof,
        DMA_RX_MFB_EOF      => app_dma_rx_mfb_eof,
        DMA_RX_MFB_SOF_POS  => app_dma_rx_mfb_sof_pos,
        DMA_RX_MFB_EOF_POS  => app_dma_rx_mfb_eof_pos,
        DMA_RX_MFB_SRC_RDY  => app_dma_rx_mfb_src_rdy,
        DMA_RX_MFB_DST_RDY  => app_dma_rx_mfb_dst_rdy,

        DMA_TX_MFB_META_PKT_SIZE => app_dma_tx_mfb_meta_pkt_size,
        DMA_TX_MFB_META_HDR_META => app_dma_tx_mfb_meta_hdr_meta,
        DMA_TX_MFB_META_CHAN     => app_dma_tx_mfb_meta_chan,

        DMA_TX_MFB_DATA     => app_dma_tx_mfb_data,
        DMA_TX_MFB_SOF      => app_dma_tx_mfb_sof,
        DMA_TX_MFB_EOF      => app_dma_tx_mfb_eof,
        DMA_TX_MFB_SOF_POS  => app_dma_tx_mfb_sof_pos,
        DMA_TX_MFB_EOF_POS  => app_dma_tx_mfb_eof_pos,
        DMA_TX_MFB_SRC_RDY  => app_dma_tx_mfb_src_rdy,
        DMA_TX_MFB_DST_RDY  => app_dma_tx_mfb_dst_rdy,

        HBM_REFCLK_P => HBM_REFCLK_P,
        HBM_REFCLK_N => HBM_REFCLK_N,
        HBM_CATTRIP  => HBM_CATTRIP,

        MI_DWR             => mi_adc_dwr(MI_ADC_PORT_USERAPP),
        MI_ADDR            => mi_adc_addr(MI_ADC_PORT_USERAPP),
        MI_BE              => mi_adc_be(MI_ADC_PORT_USERAPP),
        MI_RD              => mi_adc_rd(MI_ADC_PORT_USERAPP),
        MI_WR              => mi_adc_wr(MI_ADC_PORT_USERAPP),
        MI_DRD             => mi_adc_drd(MI_ADC_PORT_USERAPP),
        MI_ARDY            => mi_adc_ardy(MI_ADC_PORT_USERAPP),
        MI_DRDY            => mi_adc_drdy(MI_ADC_PORT_USERAPP)
    );

    -- =========================================================================
    --  JTAG-OVER-PROTOCOL CONTROLLER (Debug on Intel devices)
    -- =========================================================================
    jtag_op_ctrl_i: entity work.JTAG_OP_CTRL
    generic map (
        MI_ADDR_WIDTH => MI_WIDTH,
        MI_DATA_WIDTH => MI_WIDTH,
        JOP_ENABLE    => VIRTUAL_DEBUG_ENABLE,
        DEVICE        => DEVICE
    )
    port map (
        USER_CLK      => clk_vector(MI_CLK_IDX),
        USER_RESET    => rst_vector_deser(MI_CLK_IDX)(7),
        JOP_CLK       => clk_vector(MI_CLK_IDX),
        JOP_RESET     => rst_vector_deser(MI_CLK_IDX)(8),
        MI_DWR        => mi_adc_dwr(MI_ADC_PORT_JTAG_IP),
        MI_ADDR       => mi_adc_addr(MI_ADC_PORT_JTAG_IP),
        MI_RD         => mi_adc_rd(MI_ADC_PORT_JTAG_IP),
        MI_WR         => mi_adc_wr(MI_ADC_PORT_JTAG_IP),
        MI_BE         => mi_adc_be(MI_ADC_PORT_JTAG_IP),
        MI_DRD        => mi_adc_drd(MI_ADC_PORT_JTAG_IP),
        MI_ARDY       => mi_adc_ardy(MI_ADC_PORT_JTAG_IP),
        MI_DRDY       => mi_adc_drdy(MI_ADC_PORT_JTAG_IP)
    );

    -- =========================================================================
    --  STATUS LEDs
    -- =========================================================================
    -- Proves the correctly running master clock signal
    process (clk_vector(MI_CLK_IDX))
    begin
        if rising_edge(clk_vector(MI_CLK_IDX)) then
            if (rst_vector_deser(MI_CLK_IDX)(9) = '1') then
                heartbeat_cnt <= (others => '0');
            else
                heartbeat_cnt <= heartbeat_cnt + 1;
            end if;
            STATUS_LEDS(0) <= heartbeat_cnt(HEARTBEAT_CNT_W-1);
        end if;
    end process;

    STATUS_LEDS(1) <= (and pcie_link_up);
end architecture;
