-- pcie_top.vhd: Top level of PCIe module
-- Copyright (C) 2019 CESNET z. s. p. o.
-- Author(s): Jakub Cabal <cabal@cesnet.cz>
--
-- SPDX-License-Identifier: BSD-3-Clause

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.math_pack.all;
use work.type_pack.all;
use work.pcie_meta_pack.all;

entity PCIE is
    generic(
        -- =====================================================================
        -- BAR base address configuration
        -- =====================================================================
        BAR0_BASE_ADDR     : std_logic_vector(31 downto 0) := X"01000000";
        BAR1_BASE_ADDR     : std_logic_vector(31 downto 0) := X"02000000";
        BAR2_BASE_ADDR     : std_logic_vector(31 downto 0) := X"03000000";
        BAR3_BASE_ADDR     : std_logic_vector(31 downto 0) := X"04000000";
        BAR4_BASE_ADDR     : std_logic_vector(31 downto 0) := X"05000000";
        BAR5_BASE_ADDR     : std_logic_vector(31 downto 0) := X"06000000";
        EXP_ROM_BASE_ADDR  : std_logic_vector(31 downto 0) := X"0A000000";

        -- =====================================================================
        -- MFB configuration
        -- =====================================================================
        CQ_MFB_REGIONS     : natural := 2;
        CQ_MFB_REGION_SIZE : natural := 1;
        CQ_MFB_BLOCK_SIZE  : natural := 8;
        CQ_MFB_ITEM_WIDTH  : natural := 32;

        RC_MFB_REGIONS     : natural := 2;
        RC_MFB_REGION_SIZE : natural := 1;
        RC_MFB_BLOCK_SIZE  : natural := 8;
        RC_MFB_ITEM_WIDTH  : natural := 32;

        CC_MFB_REGIONS     : natural := 2;
        CC_MFB_REGION_SIZE : natural := 1;
        CC_MFB_BLOCK_SIZE  : natural := 8;
        CC_MFB_ITEM_WIDTH  : natural := 32;

        RQ_MFB_REGIONS     : natural := 2;
        RQ_MFB_REGION_SIZE : natural := 1;
        RQ_MFB_BLOCK_SIZE  : natural := 8;
        RQ_MFB_ITEM_WIDTH  : natural := 32;

        -- =====================================================================
        -- Other configuration
        -- =====================================================================
        -- Connected PCIe endpoint type
        PCIE_ENDPOINT_TYPE : string  := "P_TILE";
        -- Connected PCIe endpoint mode: 0=x16, 1=x8x8, 2=x8
        PCIE_ENDPOINT_MODE : natural := 0;
        -- Number of PCIe endpoints
        PCIE_ENDPOINTS     : natural := 1;
        -- Number of PCIe clocks per PCIe connector
        PCIE_CLKS          : natural := 2;
        -- Number of PCIe connectors
        PCIE_CONS          : natural := 1;
        -- Number of PCIe lanes in each PCIe connector
        PCIE_LANES         : natural := 16;
        -- Width of CARD/FPGA ID number
        CARD_ID_WIDTH      : natural := 0;
        -- Enable of XCV IP, for Xilinx only
        XVC_ENABLE         : boolean := false;
        -- FPGA device
        DEVICE             : string  := "STRATIX10"
    );
    port(
        -- =====================================================================
        -- CLOCKS AND RESETS
        -- =====================================================================
        -- Clock from PCIe port, 100 MHz
        PCIE_SYSCLK_P       : in  std_logic_vector(PCIE_CONS*PCIE_CLKS-1 downto 0);
        PCIE_SYSCLK_N       : in  std_logic_vector(PCIE_CONS*PCIE_CLKS-1 downto 0);
        -- PCIe reset from PCIe port
        PCIE_SYSRST_N       : in  std_logic_vector(PCIE_CONS-1 downto 0);
        -- nINIT_DONE output of the Reset Release Intel Stratix 10 FPGA IP
        INIT_DONE_N         : in  std_logic;
        -- PCIe user clock and reset
        PCIE_USER_CLK       : out std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
        PCIE_USER_RESET     : out std_logic_vector(PCIE_ENDPOINTS-1 downto 0);

        -- =====================================================================
        -- PCIE SERIAL INTERFACE
        -- =====================================================================
        -- Receive data
        PCIE_RX_P           : in  std_logic_vector(PCIE_CONS*PCIE_LANES-1 downto 0);
        PCIE_RX_N           : in  std_logic_vector(PCIE_CONS*PCIE_LANES-1 downto 0);
        -- Transmit data
        PCIE_TX_P           : out std_logic_vector(PCIE_CONS*PCIE_LANES-1 downto 0);
        PCIE_TX_N           : out std_logic_vector(PCIE_CONS*PCIE_LANES-1 downto 0);

        -- =====================================================================
        -- Configuration status interface (PCIE_USER_CLK)
        -- =====================================================================
        -- PCIe link up flag per PCIe endpoint
        PCIE_LINK_UP        : out std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
        -- PCIe maximum payload size
        PCIE_MPS            : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(3-1 downto 0);
        -- PCIe maximum read request size
        PCIE_MRRS           : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(3-1 downto 0);
        -- PCIe extended tag enable (8-bit tag)
        PCIE_EXT_TAG_EN     : out std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
        -- PCIe 10-bit tag requester enable
        PCIE_10B_TAG_REQ_EN : out std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
        -- PCIe RCB size control
        PCIE_RCB_SIZE       : out std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
        -- Card ID / PCIe Device Serial Number
        CARD_ID             : in slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CARD_ID_WIDTH-1 downto 0) := (others => (others => '0'));

        -- =====================================================================
        -- DMA RQ MFB interface (PCIE_USER_CLK)
        --
        -- MFB bus only for transferring RQ PCIe transactions
        -- (format according to the PCIe IP used). Compared to the standard MFB
        -- specification, it does not allow gaps (SRC_RDY=0) inside transactions
        -- and requires that the first transaction in a word starts at byte 0.
        -- =====================================================================
        DMA_RQ_MFB_DATA     : in  slv_array_t(PCIE_ENDPOINTS-1 downto 0)(RQ_MFB_REGIONS*RQ_MFB_REGION_SIZE*RQ_MFB_BLOCK_SIZE*RQ_MFB_ITEM_WIDTH-1 downto 0);
        DMA_RQ_MFB_META     : in  slv_array_t(PCIE_ENDPOINTS-1 downto 0)(RQ_MFB_REGIONS*PCIE_RQ_META_WIDTH-1 downto 0);
        DMA_RQ_MFB_SOF      : in  slv_array_t(PCIE_ENDPOINTS-1 downto 0)(RQ_MFB_REGIONS-1 downto 0);
        DMA_RQ_MFB_EOF      : in  slv_array_t(PCIE_ENDPOINTS-1 downto 0)(RQ_MFB_REGIONS-1 downto 0);
        DMA_RQ_MFB_SOF_POS  : in  slv_array_t(PCIE_ENDPOINTS-1 downto 0)(RQ_MFB_REGIONS*max(1,log2(RQ_MFB_REGION_SIZE))-1 downto 0);
        DMA_RQ_MFB_EOF_POS  : in  slv_array_t(PCIE_ENDPOINTS-1 downto 0)(RQ_MFB_REGIONS*max(1,log2(RQ_MFB_REGION_SIZE*RQ_MFB_BLOCK_SIZE))-1 downto 0);
        DMA_RQ_MFB_SRC_RDY  : in  std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
        DMA_RQ_MFB_DST_RDY  : out std_logic_vector(PCIE_ENDPOINTS-1 downto 0);

        -- =====================================================================
        -- DMA RC MFB interface (PCIE_USER_CLK)
        --
        -- MFB bus only for transferring RC PCIe transactions
        -- (format according to the PCIe IP used). Compared to the standard MFB
        -- specification, it does not allow gaps (SRC_RDY=0) inside transactions
        -- and requires that the first transaction in a word starts at byte 0.
        -- =====================================================================
        DMA_RC_MFB_DATA     : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(RC_MFB_REGIONS*RC_MFB_REGION_SIZE*RC_MFB_BLOCK_SIZE*RC_MFB_ITEM_WIDTH-1 downto 0);
        DMA_RC_MFB_META     : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(RC_MFB_REGIONS*PCIE_RC_META_WIDTH-1 downto 0);
        DMA_RC_MFB_SOF      : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(RC_MFB_REGIONS-1 downto 0);
        DMA_RC_MFB_EOF      : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(RC_MFB_REGIONS-1 downto 0);
        DMA_RC_MFB_SOF_POS  : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(RC_MFB_REGIONS*max(1,log2(RC_MFB_REGION_SIZE))-1 downto 0);
        DMA_RC_MFB_EOF_POS  : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(RC_MFB_REGIONS*max(1,log2(RC_MFB_REGION_SIZE*RC_MFB_BLOCK_SIZE))-1 downto 0);
        DMA_RC_MFB_SRC_RDY  : out std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
        DMA_RC_MFB_DST_RDY  : in  std_logic_vector(PCIE_ENDPOINTS-1 downto 0);

        -- =====================================================================
        -- DMA CQ MFB interface - DMA-BAR (PCIE_CLK)
        --
        -- MFB bus for transferring CQ DMA-BAR PCIe transactions (format
        -- according to the PCIe IP used). Compared to the standard MFB
        -- specification, it does not allow gaps (SRC_RDY=0) inside transactions
        -- and requires that the first transaction in a word starts at byte 0.
        -- =====================================================================
        DMA_CQ_MFB_DATA     : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CQ_MFB_REGIONS*CQ_MFB_REGION_SIZE*CQ_MFB_BLOCK_SIZE*CQ_MFB_ITEM_WIDTH-1 downto 0);
        DMA_CQ_MFB_META     : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CQ_MFB_REGIONS*PCIE_CQ_META_WIDTH-1 downto 0);
        DMA_CQ_MFB_SOF      : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CQ_MFB_REGIONS-1 downto 0);
        DMA_CQ_MFB_EOF      : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CQ_MFB_REGIONS-1 downto 0);
        DMA_CQ_MFB_SOF_POS  : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CQ_MFB_REGIONS*max(1,log2(CQ_MFB_REGION_SIZE))-1 downto 0);
        DMA_CQ_MFB_EOF_POS  : out slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CQ_MFB_REGIONS*max(1,log2(CQ_MFB_REGION_SIZE*CQ_MFB_BLOCK_SIZE))-1 downto 0);
        DMA_CQ_MFB_SRC_RDY  : out std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
        DMA_CQ_MFB_DST_RDY  : in  std_logic_vector(PCIE_ENDPOINTS-1 downto 0);

        -- =====================================================================
        -- PCIE CC MFB interface - DMA-BAR (PCIE_CLK)
        --
        -- MFB bus for transferring CC DMA-BAR PCIe transactions (format
        -- according to the PCIe IP used). Compared to the standard MFB
        -- specification, it does not allow gaps (SRC_RDY=0) inside transactions
        -- and requires that the first transaction in a word starts at byte 0.
        -- =====================================================================
        DMA_CC_MFB_DATA     : in  slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CC_MFB_REGIONS*CC_MFB_REGION_SIZE*CC_MFB_BLOCK_SIZE*CC_MFB_ITEM_WIDTH-1 downto 0);
        DMA_CC_MFB_META     : in  slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CC_MFB_REGIONS*PCIE_CC_META_WIDTH-1 downto 0);
        DMA_CC_MFB_SOF      : in  slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CC_MFB_REGIONS-1 downto 0);
        DMA_CC_MFB_EOF      : in  slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CC_MFB_REGIONS-1 downto 0);
        DMA_CC_MFB_SOF_POS  : in  slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CC_MFB_REGIONS*max(1,log2(CC_MFB_REGION_SIZE))-1 downto 0);
        DMA_CC_MFB_EOF_POS  : in  slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CC_MFB_REGIONS*max(1,log2(CC_MFB_REGION_SIZE*CC_MFB_BLOCK_SIZE))-1 downto 0);
        DMA_CC_MFB_SRC_RDY  : in  std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
        DMA_CC_MFB_DST_RDY  : out std_logic_vector(PCIE_ENDPOINTS-1 downto 0);

        -- =====================================================================
        -- MI32 interfaces (MI_CLK)
        --
        -- MI - Root of the MI32 bus tree for each PCIe endpoint (connection to the MTC)
        -- MI_DBG - MI interface to PCIe registers (currently only debug registers)
        -- =====================================================================
        MI_CLK              : in  std_logic;
        MI_RESET            : in  std_logic;

        MI_DWR_MTC  : out slv_array_t     (PCIE_ENDPOINTS-1 downto 0)(32-1 downto 0);
        MI_ADDR_MTC : out slv_array_t     (PCIE_ENDPOINTS-1 downto 0)(32-1 downto 0);
        MI_BE_MTC   : out slv_array_t     (PCIE_ENDPOINTS-1 downto 0)(32/8-1 downto 0);
        MI_RD_MTC   : out std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
        MI_WR_MTC   : out std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
        MI_DRD_MTC  : in  slv_array_t     (PCIE_ENDPOINTS-1 downto 0)(32-1 downto 0);
        MI_ARDY_MTC : in  std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
        MI_DRDY_MTC : in  std_logic_vector(PCIE_ENDPOINTS-1 downto 0);

        MI_DWR   : in  std_logic_vector(32-1 downto 0);
        MI_ADDR  : in  std_logic_vector(32-1 downto 0);
        MI_BE    : in  std_logic_vector(32/8-1 downto 0);
        MI_RD    : in  std_logic;
        MI_WR    : in  std_logic;
        MI_DRD   : out std_logic_vector(32-1 downto 0);
        MI_ARDY  : out std_logic;
        MI_DRDY  : out std_logic
    );
end entity;

architecture FULL of PCIE is

    constant CORE_RQ_MFB_REGIONS : natural := RQ_MFB_REGIONS;
    constant CORE_RC_MFB_REGIONS : natural := RC_MFB_REGIONS;
    constant RESET_WIDTH         : natural := 6;
    constant BAR_APERTURE        : natural := 26;

    signal pcie_clk                : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal pcie_reset              : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(RESET_WIDTH-1 downto 0);

    signal pcie_cfg_mps            : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(3-1 downto 0);
    signal pcie_cfg_mrrs           : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(3-1 downto 0);
    signal pcie_cfg_ext_tag_en     : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal pcie_cfg_10b_tag_req_en : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal pcie_cfg_rcb_size       : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);

    signal core_rq_mfb_data        : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CORE_RQ_MFB_REGIONS*RQ_MFB_REGION_SIZE*RQ_MFB_BLOCK_SIZE*RQ_MFB_ITEM_WIDTH-1 downto 0);
    signal core_rq_mfb_meta        : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CORE_RQ_MFB_REGIONS*PCIE_RQ_META_WIDTH-1 downto 0);
    signal core_rq_mfb_sof         : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CORE_RQ_MFB_REGIONS-1 downto 0);
    signal core_rq_mfb_eof         : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CORE_RQ_MFB_REGIONS-1 downto 0);
    signal core_rq_mfb_sof_pos     : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CORE_RQ_MFB_REGIONS*max(1,log2(RQ_MFB_REGION_SIZE))-1 downto 0);
    signal core_rq_mfb_eof_pos     : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CORE_RQ_MFB_REGIONS*max(1,log2(RQ_MFB_REGION_SIZE*RQ_MFB_BLOCK_SIZE))-1 downto 0);
    signal core_rq_mfb_src_rdy     : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal core_rq_mfb_dst_rdy     : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);

    signal core_rc_mfb_data        : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CORE_RC_MFB_REGIONS*RC_MFB_REGION_SIZE*RC_MFB_BLOCK_SIZE*RC_MFB_ITEM_WIDTH-1 downto 0);
    signal core_rc_mfb_meta        : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CORE_RC_MFB_REGIONS*PCIE_RC_META_WIDTH-1 downto 0);
    signal core_rc_mfb_sof         : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CORE_RC_MFB_REGIONS-1 downto 0);
    signal core_rc_mfb_eof         : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CORE_RC_MFB_REGIONS-1 downto 0);
    signal core_rc_mfb_sof_pos     : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CORE_RC_MFB_REGIONS*max(1,log2(RC_MFB_REGION_SIZE))-1 downto 0);
    signal core_rc_mfb_eof_pos     : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CORE_RC_MFB_REGIONS*max(1,log2(RC_MFB_REGION_SIZE*RC_MFB_BLOCK_SIZE))-1 downto 0);
    signal core_rc_mfb_src_rdy     : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal core_rc_mfb_dst_rdy     : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);

    signal core_cq_mfb_data        : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CQ_MFB_REGIONS*CQ_MFB_REGION_SIZE*CQ_MFB_BLOCK_SIZE*CQ_MFB_ITEM_WIDTH-1 downto 0);
    signal core_cq_mfb_meta        : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CQ_MFB_REGIONS*PCIE_CQ_META_WIDTH-1 downto 0);
    signal core_cq_mfb_sof         : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CQ_MFB_REGIONS-1 downto 0);
    signal core_cq_mfb_eof         : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CQ_MFB_REGIONS-1 downto 0);
    signal core_cq_mfb_sof_pos     : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CQ_MFB_REGIONS*max(1,log2(CQ_MFB_REGION_SIZE))-1 downto 0);
    signal core_cq_mfb_eof_pos     : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CQ_MFB_REGIONS*max(1,log2(CQ_MFB_REGION_SIZE*CQ_MFB_BLOCK_SIZE))-1 downto 0);
    signal core_cq_mfb_src_rdy     : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal core_cq_mfb_dst_rdy     : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);

    signal core_cc_mfb_data        : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CC_MFB_REGIONS*CC_MFB_REGION_SIZE*CC_MFB_BLOCK_SIZE*CC_MFB_ITEM_WIDTH-1 downto 0);
    signal core_cc_mfb_meta        : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CC_MFB_REGIONS*PCIE_CC_META_WIDTH-1 downto 0);
    signal core_cc_mfb_sof         : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CC_MFB_REGIONS-1 downto 0);
    signal core_cc_mfb_eof         : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CC_MFB_REGIONS-1 downto 0);
    signal core_cc_mfb_sof_pos     : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CC_MFB_REGIONS*max(1,log2(CC_MFB_REGION_SIZE))-1 downto 0);
    signal core_cc_mfb_eof_pos     : slv_array_t(PCIE_ENDPOINTS-1 downto 0)(CC_MFB_REGIONS*max(1,log2(CC_MFB_REGION_SIZE*CC_MFB_BLOCK_SIZE))-1 downto 0);
    signal core_cc_mfb_src_rdy     : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    signal core_cc_mfb_dst_rdy     : std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
begin

    assert (CORE_RQ_MFB_REGIONS /= 0) report "PCIE: Unsupported CORE_RQ_MFB_REGIONS configuration!"
        severity failure;

    assert (CORE_RC_MFB_REGIONS /= 0) report "PCIE: Unsupported CORE_RC_MFB_REGIONS configuration!"
        severity failure;

    -- =========================================================================
    --  PCIE CORE
    -- =========================================================================

    -- The architecture depends on the selected PCIe Hard IP (or used FPGA),
    -- see Modules.tcl of PCIE_CORE.
    pcie_core_i : entity work.PCIE_CORE
    generic map (
        CQ_MFB_REGIONS     => CQ_MFB_REGIONS,
        CQ_MFB_REGION_SIZE => CQ_MFB_REGION_SIZE,
        CQ_MFB_BLOCK_SIZE  => CQ_MFB_BLOCK_SIZE,
        CQ_MFB_ITEM_WIDTH  => CQ_MFB_ITEM_WIDTH,

        RC_MFB_REGIONS     => CORE_RC_MFB_REGIONS,
        RC_MFB_REGION_SIZE => RC_MFB_REGION_SIZE,
        RC_MFB_BLOCK_SIZE  => RC_MFB_BLOCK_SIZE,
        RC_MFB_ITEM_WIDTH  => RC_MFB_ITEM_WIDTH,

        CC_MFB_REGIONS     => CC_MFB_REGIONS,
        CC_MFB_REGION_SIZE => CC_MFB_REGION_SIZE,
        CC_MFB_BLOCK_SIZE  => CC_MFB_BLOCK_SIZE,
        CC_MFB_ITEM_WIDTH  => CC_MFB_ITEM_WIDTH,

        RQ_MFB_REGIONS     => CORE_RQ_MFB_REGIONS,
        RQ_MFB_REGION_SIZE => RQ_MFB_REGION_SIZE,
        RQ_MFB_BLOCK_SIZE  => RQ_MFB_BLOCK_SIZE,
        RQ_MFB_ITEM_WIDTH  => RQ_MFB_ITEM_WIDTH,

        ENDPOINT_TYPE      => PCIE_ENDPOINT_TYPE,
        ENDPOINT_MODE      => PCIE_ENDPOINT_MODE,
        PCIE_ENDPOINTS     => PCIE_ENDPOINTS,
        PCIE_CLKS          => PCIE_CLKS,
        PCIE_CONS          => PCIE_CONS,
        PCIE_LANES         => PCIE_LANES,

        MI_WIDTH           => 32,
        XVC_ENABLE         => XVC_ENABLE,
        CARD_ID_WIDTH      => CARD_ID_WIDTH,
        RESET_WIDTH        => RESET_WIDTH,
        DEVICE             => DEVICE
    )
    port map (
        PCIE_SYSCLK_P       => PCIE_SYSCLK_P,
        PCIE_SYSCLK_N       => PCIE_SYSCLK_N,
        PCIE_SYSRST_N       => PCIE_SYSRST_N,
        INIT_DONE_N         => INIT_DONE_N,
        
        PCIE_RX_P           => PCIE_RX_P,
        PCIE_RX_N           => PCIE_RX_N,
        PCIE_TX_P           => PCIE_TX_P,
        PCIE_TX_N           => PCIE_TX_N,

        PCIE_USER_CLK       => pcie_clk,
        PCIE_USER_RESET     => pcie_reset,

        PCIE_LINK_UP        => PCIE_LINK_UP,
        PCIE_MPS            => pcie_cfg_mps,
        PCIE_MRRS           => pcie_cfg_mrrs,
        PCIE_EXT_TAG_EN     => pcie_cfg_ext_tag_en,
        PCIE_10B_TAG_REQ_EN => pcie_cfg_10b_tag_req_en,
        PCIE_RCB_SIZE       => pcie_cfg_rcb_size,

        CARD_ID             => CARD_ID,

        CQ_MFB_DATA         => core_cq_mfb_data,
        CQ_MFB_META         => core_cq_mfb_meta,
        CQ_MFB_SOF          => core_cq_mfb_sof,
        CQ_MFB_EOF          => core_cq_mfb_eof,
        CQ_MFB_SOF_POS      => core_cq_mfb_sof_pos,
        CQ_MFB_EOF_POS      => core_cq_mfb_eof_pos,
        CQ_MFB_SRC_RDY      => core_cq_mfb_src_rdy,
        CQ_MFB_DST_RDY      => core_cq_mfb_dst_rdy,

        RC_MFB_DATA         => DMA_RC_MFB_DATA,
        RC_MFB_META         => DMA_RC_MFB_META,
        RC_MFB_SOF          => DMA_RC_MFB_SOF,
        RC_MFB_EOF          => DMA_RC_MFB_EOF,
        RC_MFB_SOF_POS      => DMA_RC_MFB_SOF_POS,
        RC_MFB_EOF_POS      => DMA_RC_MFB_EOF_POS,
        RC_MFB_SRC_RDY      => DMA_RC_MFB_SRC_RDY,
        RC_MFB_DST_RDY      => DMA_RC_MFB_DST_RDY,

        CC_MFB_DATA         => core_cc_mfb_data,
        CC_MFB_META         => core_cc_mfb_meta,
        CC_MFB_SOF          => core_cc_mfb_sof,
        CC_MFB_EOF          => core_cc_mfb_eof,
        CC_MFB_SOF_POS      => core_cc_mfb_sof_pos,
        CC_MFB_EOF_POS      => core_cc_mfb_eof_pos,
        CC_MFB_SRC_RDY      => core_cc_mfb_src_rdy,
        CC_MFB_DST_RDY      => core_cc_mfb_dst_rdy,

        RQ_MFB_DATA         => DMA_RQ_MFB_DATA,
        RQ_MFB_META         => DMA_RQ_MFB_META,
        RQ_MFB_SOF          => DMA_RQ_MFB_SOF,
        RQ_MFB_EOF          => DMA_RQ_MFB_EOF,
        RQ_MFB_SOF_POS      => DMA_RQ_MFB_SOF_POS,
        RQ_MFB_EOF_POS      => DMA_RQ_MFB_EOF_POS,
        RQ_MFB_SRC_RDY      => DMA_RQ_MFB_SRC_RDY,
        RQ_MFB_DST_RDY      => DMA_RQ_MFB_DST_RDY,

        TAG_ASSIGN          => open,
        TAG_ASSIGN_VLD      => open,

        MI_CLK              => MI_CLK,
        MI_RESET            => MI_RESET,
        MI_ADDR             => MI_ADDR,
        MI_DWR              => MI_DWR,
        MI_BE               => MI_BE,
        MI_RD               => MI_RD,
        MI_WR               => MI_WR,
        MI_DRD              => MI_DRD,
        MI_ARDY             => MI_ARDY,
        MI_DRDY             => MI_DRDY
    );

    PCIE_USER_CLK <= pcie_clk;
    pcie_user_reset_g: for i in 0 to PCIE_ENDPOINTS-1 generate
        PCIE_USER_RESET(i) <= pcie_reset(i)(0);
    end generate;

    PCIE_MPS            <= pcie_cfg_mps;
    PCIE_MRRS           <= pcie_cfg_mrrs;
    PCIE_EXT_TAG_EN     <= pcie_cfg_ext_tag_en;
    PCIE_10B_TAG_REQ_EN <= pcie_cfg_10b_tag_req_en;
    PCIE_RCB_SIZE       <= pcie_cfg_rcb_size;

    -- =========================================================================
    --  PCIE CONTROLLERS
    -- =========================================================================

    pcie_ctrl_g: for i in 0 to PCIE_ENDPOINTS-1 generate
    begin
        pcie_ctrl_i : entity work.PCIE_CTRL
        generic map (
            BAR0_BASE_ADDR      => BAR0_BASE_ADDR,
            BAR1_BASE_ADDR      => BAR1_BASE_ADDR,
            BAR2_BASE_ADDR      => BAR2_BASE_ADDR,
            BAR3_BASE_ADDR      => BAR3_BASE_ADDR,
            BAR4_BASE_ADDR      => BAR4_BASE_ADDR,
            BAR5_BASE_ADDR      => BAR5_BASE_ADDR,
            EXP_ROM_BASE_ADDR   => EXP_ROM_BASE_ADDR,

            CQ_MFB_REGIONS      => CQ_MFB_REGIONS,
            CQ_MFB_REGION_SIZE  => CQ_MFB_REGION_SIZE,
            CQ_MFB_BLOCK_SIZE   => CQ_MFB_BLOCK_SIZE,
            CQ_MFB_ITEM_WIDTH   => CQ_MFB_ITEM_WIDTH,

            CC_MFB_REGIONS      => CC_MFB_REGIONS,
            CC_MFB_REGION_SIZE  => CC_MFB_REGION_SIZE,
            CC_MFB_BLOCK_SIZE   => CC_MFB_BLOCK_SIZE,
            CC_MFB_ITEM_WIDTH   => CC_MFB_ITEM_WIDTH,

            ENDPOINT_TYPE       => PCIE_ENDPOINT_TYPE,
            DEVICE              => DEVICE
        )
        port map (
            PCIE_CLK            => pcie_clk(i),
            PCIE_RESET          => pcie_reset(i)(5-1 downto 0),
            MI_CLK              => MI_CLK,
            MI_RESET            => MI_RESET,

            CTL_MAX_PAYLOAD     => pcie_cfg_mps(i),
            CTL_BAR_APERTURE    => std_logic_vector(to_unsigned(BAR_APERTURE,6)),
            CTL_RCB_SIZE        => pcie_cfg_rcb_size(i),

            PCIE_CQ_MFB_DATA    => core_cq_mfb_data(i),
            PCIE_CQ_MFB_META    => core_cq_mfb_meta(i),
            PCIE_CQ_MFB_SOF     => core_cq_mfb_sof(i),
            PCIE_CQ_MFB_EOF     => core_cq_mfb_eof(i),
            PCIE_CQ_MFB_SOF_POS => core_cq_mfb_sof_pos(i),
            PCIE_CQ_MFB_EOF_POS => core_cq_mfb_eof_pos(i),
            PCIE_CQ_MFB_SRC_RDY => core_cq_mfb_src_rdy(i),
            PCIE_CQ_MFB_DST_RDY => core_cq_mfb_dst_rdy(i),

            PCIE_CC_MFB_DATA    => core_cc_mfb_data(i),
            PCIE_CC_MFB_META    => core_cc_mfb_meta(i),
            PCIE_CC_MFB_SOF     => core_cc_mfb_sof(i),
            PCIE_CC_MFB_EOF     => core_cc_mfb_eof(i),
            PCIE_CC_MFB_SOF_POS => core_cc_mfb_sof_pos(i),
            PCIE_CC_MFB_EOF_POS => core_cc_mfb_eof_pos(i),
            PCIE_CC_MFB_SRC_RDY => core_cc_mfb_src_rdy(i),
            PCIE_CC_MFB_DST_RDY => core_cc_mfb_dst_rdy(i),

            DMA_CQ_MFB_DATA     => DMA_CQ_MFB_DATA(i),
            DMA_CQ_MFB_META     => DMA_CQ_MFB_META(i),
            DMA_CQ_MFB_SOF      => DMA_CQ_MFB_SOF(i),
            DMA_CQ_MFB_EOF      => DMA_CQ_MFB_EOF(i),
            DMA_CQ_MFB_SOF_POS  => DMA_CQ_MFB_SOF_POS(i),
            DMA_CQ_MFB_EOF_POS  => DMA_CQ_MFB_EOF_POS(i),
            DMA_CQ_MFB_SRC_RDY  => DMA_CQ_MFB_SRC_RDY(i),
            DMA_CQ_MFB_DST_RDY  => DMA_CQ_MFB_DST_RDY(i),

            DMA_CC_MFB_DATA     => DMA_CC_MFB_DATA(i),
            DMA_CC_MFB_META     => DMA_CC_MFB_META(i),
            DMA_CC_MFB_SOF      => DMA_CC_MFB_SOF(i),
            DMA_CC_MFB_EOF      => DMA_CC_MFB_EOF(i),
            DMA_CC_MFB_SOF_POS  => DMA_CC_MFB_SOF_POS(i),
            DMA_CC_MFB_EOF_POS  => DMA_CC_MFB_EOF_POS(i),
            DMA_CC_MFB_SRC_RDY  => DMA_CC_MFB_SRC_RDY(i),
            DMA_CC_MFB_DST_RDY  => DMA_CC_MFB_DST_RDY(i),

            MI_DWR              => MI_DWR_MTC(i),
            MI_ADDR             => MI_ADDR_MTC(i),
            MI_BE               => MI_BE_MTC(i),
            MI_RD               => MI_RD_MTC(i),
            MI_WR               => MI_WR_MTC(i),
            MI_DRD              => MI_DRD_MTC(i),
            MI_ARDY             => MI_ARDY_MTC(i),
            MI_DRDY             => MI_DRDY_MTC(i)
        );
    end generate;
end architecture;
