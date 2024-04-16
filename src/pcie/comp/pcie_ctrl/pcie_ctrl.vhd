-- pcie_ctrl.vhd: PCIe module controllers
-- Copyright (C) 2019 CESNET z. s. p. o.
-- Author(s): Jakub Cabal <cabal@cesnet.cz>
--
-- SPDX-License-Identifier: BSD-3-Clause

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.combo_user_const.all;

use work.math_pack.all;
use work.type_pack.all;
use work.dma_bus_pack.all;
use work.pcie_meta_pack.all;

entity PCIE_CTRL is
    generic(
        -- =====================================================================
        -- BAR base address configuration
        -- =====================================================================
        BAR0_BASE_ADDR      : std_logic_vector(31 downto 0) := X"01000000";
        BAR1_BASE_ADDR      : std_logic_vector(31 downto 0) := X"02000000";
        BAR2_BASE_ADDR      : std_logic_vector(31 downto 0) := X"03000000";
        BAR3_BASE_ADDR      : std_logic_vector(31 downto 0) := X"04000000";
        BAR4_BASE_ADDR      : std_logic_vector(31 downto 0) := X"05000000";
        BAR5_BASE_ADDR      : std_logic_vector(31 downto 0) := X"06000000";
        EXP_ROM_BASE_ADDR   : std_logic_vector(31 downto 0) := X"0A000000";

        -- =====================================================================
        -- MFB configuration
        -- =====================================================================
        CQ_MFB_REGIONS      : natural := 2;
        CQ_MFB_REGION_SIZE  : natural := 1;
        CQ_MFB_BLOCK_SIZE   : natural := 8;
        CQ_MFB_ITEM_WIDTH   : natural := 32;

        CC_MFB_REGIONS      : natural := 2;
        CC_MFB_REGION_SIZE  : natural := 1;
        CC_MFB_BLOCK_SIZE   : natural := 8;
        CC_MFB_ITEM_WIDTH   : natural := 32;

        -- =====================================================================
        -- Others configuration
        -- =====================================================================
        -- Connected PCIe endpoint type
        ENDPOINT_TYPE       : string  := "P_TILE";
        -- FPGA device
        DEVICE              : string  := "STRATIX10"
    );
    port(
        -- =====================================================================
        --  CLOCK AND RESETS
        -- =====================================================================
        PCIE_CLK            : in  std_logic;
        PCIE_RESET          : in  std_logic_vector(5-1 downto 0);
        MI_CLK              : in  std_logic;
        MI_RESET            : in  std_logic;

        -- =====================================================================
        --  CONFIGURATION STATUS INTERFACE
        -- =====================================================================
        CTL_MAX_PAYLOAD     : in  std_logic_vector(2 downto 0);
        CTL_BAR_APERTURE    : in  std_logic_vector(5 downto 0);
        CTL_RCB_SIZE        : in  std_logic;

        -- =====================================================================
        -- PCIE CQ MFB interface (PCIE_CLK)
        --
        -- MFB bus for transferring CQ PCIe transactions (format according to
        -- the PCIe IP used). Compared to the standard MFB specification, it
        -- does not allow gaps (SRC_RDY=0) inside transactions and requires that
        -- the first transaction in a word starts at byte 0.
        -- =====================================================================
        PCIE_CQ_MFB_DATA    : in  std_logic_vector(CQ_MFB_REGIONS*CQ_MFB_REGION_SIZE*CQ_MFB_BLOCK_SIZE*CQ_MFB_ITEM_WIDTH-1 downto 0);
        PCIE_CQ_MFB_META    : in  std_logic_vector(CQ_MFB_REGIONS*PCIE_CQ_META_WIDTH-1 downto 0);
        PCIE_CQ_MFB_SOF     : in  std_logic_vector(CQ_MFB_REGIONS-1 downto 0);
        PCIE_CQ_MFB_EOF     : in  std_logic_vector(CQ_MFB_REGIONS-1 downto 0);
        PCIE_CQ_MFB_SOF_POS : in  std_logic_vector(CQ_MFB_REGIONS*max(1,log2(CQ_MFB_REGION_SIZE))-1 downto 0);
        PCIE_CQ_MFB_EOF_POS : in  std_logic_vector(CQ_MFB_REGIONS*max(1,log2(CQ_MFB_REGION_SIZE*CQ_MFB_BLOCK_SIZE))-1 downto 0);
        PCIE_CQ_MFB_SRC_RDY : in  std_logic;
        PCIE_CQ_MFB_DST_RDY : out std_logic;

        -- =====================================================================
        -- DMA CQ MFB interface - DMA-BAR (PCIE_CLK)
        --
        -- MFB bus for transferring CQ DMA-BAR PCIe transactions (format
        -- according to the PCIe IP used). Compared to the standard MFB
        -- specification, it does not allow gaps (SRC_RDY=0) inside transactions
        -- and requires that the first transaction in a word starts at byte 0.
        -- =====================================================================
        DMA_CQ_MFB_DATA     : out std_logic_vector(CQ_MFB_REGIONS*CQ_MFB_REGION_SIZE*CQ_MFB_BLOCK_SIZE*CQ_MFB_ITEM_WIDTH-1 downto 0);
        DMA_CQ_MFB_META     : out std_logic_vector(CQ_MFB_REGIONS*PCIE_CQ_META_WIDTH-1 downto 0);
        DMA_CQ_MFB_SOF      : out std_logic_vector(CQ_MFB_REGIONS-1 downto 0);
        DMA_CQ_MFB_EOF      : out std_logic_vector(CQ_MFB_REGIONS-1 downto 0);
        DMA_CQ_MFB_SOF_POS  : out std_logic_vector(CQ_MFB_REGIONS*max(1,log2(CQ_MFB_REGION_SIZE))-1 downto 0);
        DMA_CQ_MFB_EOF_POS  : out std_logic_vector(CQ_MFB_REGIONS*max(1,log2(CQ_MFB_REGION_SIZE*CQ_MFB_BLOCK_SIZE))-1 downto 0);
        DMA_CQ_MFB_SRC_RDY  : out std_logic;
        DMA_CQ_MFB_DST_RDY  : in  std_logic;

        -- =====================================================================
        -- PCIE CC MFB interface (PCIE_CLK)
        --
        -- MFB bus for transferring CC PCIe transactions (format according to
        -- the PCIe IP used). Compared to the standard MFB specification, it
        -- does not allow gaps (SRC_RDY=0) inside transactions and requires that
        -- the first transaction in a word starts at byte 0.
        -- =====================================================================
        PCIE_CC_MFB_DATA    : out std_logic_vector(CC_MFB_REGIONS*CC_MFB_REGION_SIZE*CC_MFB_BLOCK_SIZE*CC_MFB_ITEM_WIDTH-1 downto 0);
        PCIE_CC_MFB_META    : out std_logic_vector(CC_MFB_REGIONS*PCIE_CC_META_WIDTH-1 downto 0);
        PCIE_CC_MFB_SOF     : out std_logic_vector(CC_MFB_REGIONS-1 downto 0);
        PCIE_CC_MFB_EOF     : out std_logic_vector(CC_MFB_REGIONS-1 downto 0);
        PCIE_CC_MFB_SOF_POS : out std_logic_vector(CC_MFB_REGIONS*max(1,log2(CC_MFB_REGION_SIZE))-1 downto 0);
        PCIE_CC_MFB_EOF_POS : out std_logic_vector(CC_MFB_REGIONS*max(1,log2(CC_MFB_REGION_SIZE*CC_MFB_BLOCK_SIZE))-1 downto 0);
        PCIE_CC_MFB_SRC_RDY : out std_logic;
        PCIE_CC_MFB_DST_RDY : in  std_logic;

        -- =====================================================================
        -- DMA CC MFB interface - DMA-BAR (PCIE_CLK)
        --
        -- MFB bus for transferring CC DMA-BAR PCIe transactions (format
        -- according to the PCIe IP used). Compared to the standard MFB
        -- specification, it does not allow gaps (SRC_RDY=0) inside transactions
        -- and requires that the first transaction in a word starts at byte 0.
        -- =====================================================================
        DMA_CC_MFB_DATA     : in  std_logic_vector(CC_MFB_REGIONS*CC_MFB_REGION_SIZE*CC_MFB_BLOCK_SIZE*CC_MFB_ITEM_WIDTH-1 downto 0);
        DMA_CC_MFB_META     : in  std_logic_vector(CC_MFB_REGIONS*PCIE_CC_META_WIDTH-1 downto 0);
        DMA_CC_MFB_SOF      : in  std_logic_vector(CC_MFB_REGIONS-1 downto 0);
        DMA_CC_MFB_EOF      : in  std_logic_vector(CC_MFB_REGIONS-1 downto 0);
        DMA_CC_MFB_SOF_POS  : in  std_logic_vector(CC_MFB_REGIONS*max(1,log2(CC_MFB_REGION_SIZE))-1 downto 0);
        DMA_CC_MFB_EOF_POS  : in  std_logic_vector(CC_MFB_REGIONS*max(1,log2(CC_MFB_REGION_SIZE*CC_MFB_BLOCK_SIZE))-1 downto 0);
        DMA_CC_MFB_SRC_RDY  : in  std_logic;
        DMA_CC_MFB_DST_RDY  : out std_logic;

        -- =====================================================================
        -- MI32 interface (MI_CLK)
        --
        -- Root of the MI32 bus tree.
        -- =====================================================================
        MI_DWR              : out std_logic_vector(31 downto 0);
        MI_ADDR             : out std_logic_vector(31 downto 0);
        MI_BE               : out std_logic_vector(3 downto 0);
        MI_RD               : out std_logic;
        MI_WR               : out std_logic;
        MI_DRD              : in  std_logic_vector(31 downto 0);
        MI_ARDY             : in  std_logic;
        MI_DRDY             : in  std_logic
    );
end entity;

architecture FULL of PCIE_CTRL is

    constant CC_MFB_MERGER_CNT_MAX : natural := 4;

    signal mtc_cq_mfb_data        : std_logic_vector(CQ_MFB_REGIONS*CQ_MFB_REGION_SIZE*CQ_MFB_BLOCK_SIZE*CQ_MFB_ITEM_WIDTH-1 downto 0);
    signal mtc_cq_mfb_meta        : std_logic_vector(CQ_MFB_REGIONS*PCIE_CQ_META_WIDTH-1 downto 0);
    signal mtc_cq_mfb_sof         : std_logic_vector(CQ_MFB_REGIONS-1 downto 0);
    signal mtc_cq_mfb_eof         : std_logic_vector(CQ_MFB_REGIONS-1 downto 0);
    signal mtc_cq_mfb_sof_pos     : std_logic_vector(CQ_MFB_REGIONS*max(1,log2(CQ_MFB_REGION_SIZE))-1 downto 0);
    signal mtc_cq_mfb_eof_pos     : std_logic_vector(CQ_MFB_REGIONS*max(1,log2(CQ_MFB_REGION_SIZE*CQ_MFB_BLOCK_SIZE))-1 downto 0);
    signal mtc_cq_mfb_src_rdy     : std_logic;
    signal mtc_cq_mfb_dst_rdy     : std_logic;

    signal mtc_fifo_mfb_data        : std_logic_vector(CQ_MFB_REGIONS*CQ_MFB_REGION_SIZE*CQ_MFB_BLOCK_SIZE*CQ_MFB_ITEM_WIDTH-1 downto 0);
    signal mtc_fifo_mfb_meta        : std_logic_vector(CQ_MFB_REGIONS*PCIE_CQ_META_WIDTH-1 downto 0);
    signal mtc_fifo_mfb_sof         : std_logic_vector(CQ_MFB_REGIONS-1 downto 0);
    signal mtc_fifo_mfb_eof         : std_logic_vector(CQ_MFB_REGIONS-1 downto 0);
    signal mtc_fifo_mfb_sof_pos     : std_logic_vector(CQ_MFB_REGIONS*max(1,log2(CQ_MFB_REGION_SIZE))-1 downto 0);
    signal mtc_fifo_mfb_eof_pos     : std_logic_vector(CQ_MFB_REGIONS*max(1,log2(CQ_MFB_REGION_SIZE*CQ_MFB_BLOCK_SIZE))-1 downto 0);
    signal mtc_fifo_mfb_src_rdy     : std_logic;
    signal mtc_fifo_mfb_dst_rdy     : std_logic;

    signal mtc_cc_mfb_data        : std_logic_vector(CC_MFB_REGIONS*CC_MFB_REGION_SIZE*CC_MFB_BLOCK_SIZE*CC_MFB_ITEM_WIDTH-1 downto 0);
    signal mtc_cc_mfb_meta        : std_logic_vector(CC_MFB_REGIONS*PCIE_CC_META_WIDTH-1 downto 0);
    signal mtc_cc_mfb_sof         : std_logic_vector(CC_MFB_REGIONS-1 downto 0);
    signal mtc_cc_mfb_eof         : std_logic_vector(CC_MFB_REGIONS-1 downto 0);
    signal mtc_cc_mfb_sof_pos     : std_logic_vector(CC_MFB_REGIONS*max(1,log2(CC_MFB_REGION_SIZE))-1 downto 0);
    signal mtc_cc_mfb_eof_pos     : std_logic_vector(CC_MFB_REGIONS*max(1,log2(CC_MFB_REGION_SIZE*CC_MFB_BLOCK_SIZE))-1 downto 0);
    signal mtc_cc_mfb_src_rdy     : std_logic;
    signal mtc_cc_mfb_dst_rdy     : std_logic;

    signal pcie_cc_mfb_data_mrg    : std_logic_vector(CC_MFB_REGIONS*CC_MFB_REGION_SIZE*CC_MFB_BLOCK_SIZE*CC_MFB_ITEM_WIDTH-1 downto 0);
    signal pcie_cc_mfb_meta_mrg    : std_logic_vector(CC_MFB_REGIONS*PCIE_CC_META_WIDTH-1 downto 0);
    signal pcie_cc_mfb_sof_mrg     : std_logic_vector(CC_MFB_REGIONS-1 downto 0);
    signal pcie_cc_mfb_eof_mrg     : std_logic_vector(CC_MFB_REGIONS-1 downto 0);
    signal pcie_cc_mfb_sof_pos_mrg : std_logic_vector(CC_MFB_REGIONS*max(1,log2(CC_MFB_REGION_SIZE))-1 downto 0);
    signal pcie_cc_mfb_eof_pos_mrg : std_logic_vector(CC_MFB_REGIONS*max(1,log2(CC_MFB_REGION_SIZE*CC_MFB_BLOCK_SIZE))-1 downto 0);
    signal pcie_cc_mfb_src_rdy_mrg : std_logic;
    signal pcie_cc_mfb_dst_rdy_mrg : std_logic;

    signal pcie_cq_mfb_meta_arr   : slv_array_t(CQ_MFB_REGIONS-1 downto 0)(PCIE_CQ_META_WIDTH-1 downto 0);
    signal pcie_cq_mfb_data_arr   : slv_array_t(CQ_MFB_REGIONS-1 downto 0)(CQ_MFB_REGION_SIZE*CQ_MFB_BLOCK_SIZE*CQ_MFB_ITEM_WIDTH-1 downto 0);
    signal pcie_cq_mfb_bar        : slv_array_t(CQ_MFB_REGIONS-1 downto 0)(PCIE_META_BAR_W-1 downto 0);
    signal pcie_cq_mfb_sel        : std_logic_vector(CQ_MFB_REGIONS-1 downto 0);

    signal ctl_max_payload_reg    : std_logic_vector(3-1 downto 0);

    signal mtc_mi_dwr             : std_logic_vector(31 downto 0);
    signal mtc_mi_addr            : std_logic_vector(31 downto 0);
    signal mtc_mi_be              : std_logic_vector(3 downto 0);
    signal mtc_mi_rd              : std_logic;
    signal mtc_mi_wr              : std_logic;
    signal mtc_mi_drd             : std_logic_vector(31 downto 0);
    signal mtc_mi_ardy            : std_logic;
    signal mtc_mi_drdy            : std_logic;

    signal mi_sync_dwr            : std_logic_vector(31 downto 0);
    signal mi_sync_addr           : std_logic_vector(31 downto 0);
    signal mi_sync_be             : std_logic_vector(3 downto 0);
    signal mi_sync_rd             : std_logic;
    signal mi_sync_wr             : std_logic;
    signal mi_sync_drd            : std_logic_vector(31 downto 0);
    signal mi_sync_ardy           : std_logic;
    signal mi_sync_drdy           : std_logic;
begin
    -- =============================================================================================
    -- CC MFB PIPE to PCIE_CORE
    -- =============================================================================================
    cc_mfb_pipe: entity work.MFB_PIPE
        generic map (
            REGIONS     => CC_MFB_REGIONS,
            REGION_SIZE => CC_MFB_REGION_SIZE,
            BLOCK_SIZE  => CC_MFB_BLOCK_SIZE,
            ITEM_WIDTH  => CC_MFB_ITEM_WIDTH,
            META_WIDTH  => PCIE_CC_META_WIDTH,

            FAKE_PIPE   => FALSE,
            USE_DST_RDY => TRUE,
            PIPE_TYPE   => "REG",
            DEVICE      => DEVICE)
        port map (
            CLK        => PCIE_CLK,
            RESET      => PCIE_RESET(1),

            RX_DATA    => pcie_cc_mfb_data_mrg,
            RX_META    => pcie_cc_mfb_meta_mrg,
            RX_SOF_POS => pcie_cc_mfb_sof_pos_mrg,
            RX_EOF_POS => pcie_cc_mfb_eof_pos_mrg,
            RX_SOF     => pcie_cc_mfb_sof_mrg,
            RX_EOF     => pcie_cc_mfb_eof_mrg,
            RX_SRC_RDY => pcie_cc_mfb_src_rdy_mrg,
            RX_DST_RDY => pcie_cc_mfb_dst_rdy_mrg,

            TX_DATA    => PCIE_CC_MFB_DATA,
            TX_META    => PCIE_CC_MFB_META,
            TX_SOF_POS => PCIE_CC_MFB_SOF_POS,
            TX_EOF_POS => PCIE_CC_MFB_EOF_POS,
            TX_SOF     => PCIE_CC_MFB_SOF,
            TX_EOF     => PCIE_CC_MFB_EOF,
            TX_SRC_RDY => PCIE_CC_MFB_SRC_RDY,
            TX_DST_RDY => PCIE_CC_MFB_DST_RDY);

    -- =========================================================================
    -- DMA-BAR SPLITTER/MERGER
    -- =========================================================================
    -- first 64b BAR (BAR0) is for MI access (MTC)
    -- second 64b BAR (BAR2) is for special DMA access (DMA Calypte)

    pcie_cq_mfb_meta_arr <= slv_array_deser(PCIE_CQ_MFB_META,CQ_MFB_REGIONS);
    pcie_cq_mfb_data_arr <= slv_array_deser(PCIE_CQ_MFB_DATA,CQ_MFB_REGIONS);

    cq_mfb_sel_g: for i in 0 to CQ_MFB_REGIONS-1 generate
        bar_index_g: if (DEVICE="ULTRASCALE") generate
            -- BAR index is in AXI header
            pcie_cq_mfb_bar(i) <= pcie_cq_mfb_data_arr(i)(114 downto 112);
        else generate -- Intel FPGA (R-Tile, P-Tile)
            pcie_cq_mfb_bar(i) <= pcie_cq_mfb_meta_arr(i)(PCIE_CQ_META_BAR);
        end generate;
        pcie_cq_mfb_sel(i) <= '1' when (unsigned(pcie_cq_mfb_bar(i)) = 2) else '0';
    end generate;

    cq_splitter_i : entity work.MFB_SPLITTER_SIMPLE
    generic map(
        REGIONS     => CQ_MFB_REGIONS,
        REGION_SIZE => CQ_MFB_REGION_SIZE,
        BLOCK_SIZE  => CQ_MFB_BLOCK_SIZE,
        ITEM_WIDTH  => CQ_MFB_ITEM_WIDTH,
        META_WIDTH  => PCIE_CQ_META_WIDTH
    )
    port map(
        CLK             => PCIE_CLK,
        RST             => PCIE_RESET(0),

        RX_MFB_SEL      => pcie_cq_mfb_sel,
        RX_MFB_DATA     => PCIE_CQ_MFB_DATA,
        RX_MFB_META     => PCIE_CQ_MFB_META,
        RX_MFB_SOF      => PCIE_CQ_MFB_SOF,
        RX_MFB_EOF      => PCIE_CQ_MFB_EOF,
        RX_MFB_SOF_POS  => PCIE_CQ_MFB_SOF_POS,
        RX_MFB_EOF_POS  => PCIE_CQ_MFB_EOF_POS,
        RX_MFB_SRC_RDY  => PCIE_CQ_MFB_SRC_RDY,
        RX_MFB_DST_RDY  => PCIE_CQ_MFB_DST_RDY,

        TX0_MFB_DATA    => mtc_fifo_mfb_data,
        TX0_MFB_META    => mtc_fifo_mfb_meta,
        TX0_MFB_SOF     => mtc_fifo_mfb_sof,
        TX0_MFB_EOF     => mtc_fifo_mfb_eof,
        TX0_MFB_SOF_POS => mtc_fifo_mfb_sof_pos,
        TX0_MFB_EOF_POS => mtc_fifo_mfb_eof_pos,
        TX0_MFB_SRC_RDY => mtc_fifo_mfb_src_rdy,
        TX0_MFB_DST_RDY => mtc_fifo_mfb_dst_rdy,

        TX1_MFB_DATA    => DMA_CQ_MFB_DATA,
        TX1_MFB_META    => DMA_CQ_MFB_META,
        TX1_MFB_SOF     => DMA_CQ_MFB_SOF,
        TX1_MFB_EOF     => DMA_CQ_MFB_EOF,
        TX1_MFB_SOF_POS => DMA_CQ_MFB_SOF_POS,
        TX1_MFB_EOF_POS => DMA_CQ_MFB_EOF_POS,
        TX1_MFB_SRC_RDY => DMA_CQ_MFB_SRC_RDY,
        TX1_MFB_DST_RDY => DMA_CQ_MFB_DST_RDY
    );

    cc_merger_i : entity work.MFB_MERGER_SIMPLE
    generic map(
        REGIONS     => CC_MFB_REGIONS,
        REGION_SIZE => CC_MFB_REGION_SIZE,
        BLOCK_SIZE  => CC_MFB_BLOCK_SIZE,
        ITEM_WIDTH  => CC_MFB_ITEM_WIDTH,
        META_WIDTH  => PCIE_CC_META_WIDTH,
        MASKING_EN  => False,
        CNT_MAX     => CC_MFB_MERGER_CNT_MAX
    )
    port map(
        CLK             => PCIE_CLK,
        RST             => PCIE_RESET(1),

        RX_MFB0_DATA    => mtc_cc_mfb_data,
        RX_MFB0_META    => mtc_cc_mfb_meta,
        RX_MFB0_SOF     => mtc_cc_mfb_sof,
        RX_MFB0_EOF     => mtc_cc_mfb_eof,
        RX_MFB0_SOF_POS => mtc_cc_mfb_sof_pos,
        RX_MFB0_EOF_POS => mtc_cc_mfb_eof_pos,
        RX_MFB0_SRC_RDY => mtc_cc_mfb_src_rdy,
        RX_MFB0_DST_RDY => mtc_cc_mfb_dst_rdy,

        RX_MFB1_DATA    => DMA_CC_MFB_DATA,
        RX_MFB1_META    => DMA_CC_MFB_META,
        RX_MFB1_SOF     => DMA_CC_MFB_SOF,
        RX_MFB1_EOF     => DMA_CC_MFB_EOF,
        RX_MFB1_SOF_POS => DMA_CC_MFB_SOF_POS,
        RX_MFB1_EOF_POS => DMA_CC_MFB_EOF_POS,
        RX_MFB1_SRC_RDY => DMA_CC_MFB_SRC_RDY,
        RX_MFB1_DST_RDY => DMA_CC_MFB_DST_RDY,

        TX_MFB_DATA     => pcie_cc_mfb_data_mrg,
        TX_MFB_META     => pcie_cc_mfb_meta_mrg,
        TX_MFB_SOF      => pcie_cc_mfb_sof_mrg,
        TX_MFB_EOF      => pcie_cc_mfb_eof_mrg,
        TX_MFB_SOF_POS  => pcie_cc_mfb_sof_pos_mrg,
        TX_MFB_EOF_POS  => pcie_cc_mfb_eof_pos_mrg,
        TX_MFB_SRC_RDY  => pcie_cc_mfb_src_rdy_mrg,
        TX_MFB_DST_RDY  => pcie_cc_mfb_dst_rdy_mrg
    );

    -- =========================================================================
    -- MI32 CONTROLLER (MTC)
    -- =========================================================================
    process (PCIE_CLK)
    begin
        if (rising_edge(PCIE_CLK)) then
            ctl_max_payload_reg <= CTL_MAX_PAYLOAD;
        end if;
    end process;

    mtc_i : entity work.MTC
    generic map (
        MFB_REGIONS       => CQ_MFB_REGIONS,
        MFB_REGION_SIZE   => CQ_MFB_REGION_SIZE,
        MFB_BLOCK_SIZE    => CQ_MFB_BLOCK_SIZE,
        MFB_ITEM_WIDTH    => CQ_MFB_ITEM_WIDTH,

        BAR0_BASE_ADDR    => BAR0_BASE_ADDR,
        BAR1_BASE_ADDR    => BAR1_BASE_ADDR,
        BAR2_BASE_ADDR    => BAR2_BASE_ADDR,
        BAR3_BASE_ADDR    => BAR3_BASE_ADDR,
        BAR4_BASE_ADDR    => BAR4_BASE_ADDR,
        BAR5_BASE_ADDR    => BAR5_BASE_ADDR,
        EXP_ROM_BASE_ADDR => EXP_ROM_BASE_ADDR,
        
        ENDPOINT_TYPE     => ENDPOINT_TYPE,
        DEVICE            => DEVICE
    )
    port map (
        CLK                  => PCIE_CLK,
        RESET                => PCIE_RESET(2),

        CTL_MAX_PAYLOAD_SIZE => ctl_max_payload_reg,
        CTL_BAR_APERTURE     => CTL_BAR_APERTURE,

        CQ_MFB_DATA          => mtc_cq_mfb_data,
        CQ_MFB_META          => mtc_cq_mfb_meta,
        CQ_MFB_SOF           => mtc_cq_mfb_sof,
        CQ_MFB_EOF           => mtc_cq_mfb_eof,
        CQ_MFB_SOF_POS       => mtc_cq_mfb_sof_pos,
        CQ_MFB_EOF_POS       => mtc_cq_mfb_eof_pos,
        CQ_MFB_SRC_RDY       => mtc_cq_mfb_src_rdy,
        CQ_MFB_DST_RDY       => mtc_cq_mfb_dst_rdy,

        CC_MFB_DATA          => mtc_cc_mfb_data,
        CC_MFB_META          => mtc_cc_mfb_meta,
        CC_MFB_SOF           => mtc_cc_mfb_sof,
        CC_MFB_EOF           => mtc_cc_mfb_eof,
        CC_MFB_SOF_POS       => mtc_cc_mfb_sof_pos,
        CC_MFB_EOF_POS       => mtc_cc_mfb_eof_pos,
        CC_MFB_SRC_RDY       => mtc_cc_mfb_src_rdy,
        CC_MFB_DST_RDY       => mtc_cc_mfb_dst_rdy,

        MI_DWR               => mtc_mi_dwr,
        MI_ADDR              => mtc_mi_addr,
        MI_BE                => mtc_mi_be,
        MI_RD                => mtc_mi_rd,
        MI_WR                => mtc_mi_wr,
        MI_DRD               => mtc_mi_drd,
        MI_ARDY              => mtc_mi_ardy,
        MI_DRDY              => mtc_mi_drdy
    );

    mtc_fifo_i : entity work.MFB_FIFOX
        generic map (
            REGIONS             => CQ_MFB_REGIONS,
            REGION_SIZE         => CQ_MFB_REGION_SIZE,
            BLOCK_SIZE          => CQ_MFB_BLOCK_SIZE,
            ITEM_WIDTH          => CQ_MFB_ITEM_WIDTH,

            META_WIDTH          => PCIE_CQ_META_WIDTH,
            FIFO_DEPTH          => 512,
            RAM_TYPE            => "AUTO",
            DEVICE              => DEVICE,
            ALMOST_FULL_OFFSET  => 2,
            ALMOST_EMPTY_OFFSET => 2)
        port map (
            CLK         => PCIE_CLK,
            RST         => PCIE_RESET(3),

            RX_DATA     => mtc_fifo_mfb_data,
            RX_META     => mtc_fifo_mfb_meta,
            RX_SOF_POS  => mtc_fifo_mfb_sof_pos,
            RX_EOF_POS  => mtc_fifo_mfb_eof_pos,
            RX_SOF      => mtc_fifo_mfb_sof,
            RX_EOF      => mtc_fifo_mfb_eof,
            RX_SRC_RDY  => mtc_fifo_mfb_src_rdy,
            RX_DST_RDY  => mtc_fifo_mfb_dst_rdy,

            TX_DATA     => mtc_cq_mfb_data,
            TX_META     => mtc_cq_mfb_meta,
            TX_SOF_POS  => mtc_cq_mfb_sof_pos,
            TX_EOF_POS  => mtc_cq_mfb_eof_pos,
            TX_SOF      => mtc_cq_mfb_sof,
            TX_EOF      => mtc_cq_mfb_eof,
            TX_SRC_RDY  => mtc_cq_mfb_src_rdy,
            TX_DST_RDY  => mtc_cq_mfb_dst_rdy,

            FIFO_STATUS => open,
            FIFO_AFULL  => open,
            FIFO_AEMPTY => open);

    mi_async_i : entity work.MI_ASYNC
    generic map(
        DEVICE => DEVICE
    )
    port map(
        -- Master interface
        CLK_M     => PCIE_CLK,
        RESET_M   => PCIE_RESET(4),
        MI_M_DWR  => mtc_mi_dwr,
        MI_M_ADDR => mtc_mi_addr,
        MI_M_RD   => mtc_mi_rd,
        MI_M_WR   => mtc_mi_wr,
        MI_M_BE   => mtc_mi_be,
        MI_M_DRD  => mtc_mi_drd,
        MI_M_ARDY => mtc_mi_ardy,
        MI_M_DRDY => mtc_mi_drdy,

        -- Slave interface
        CLK_S     => MI_CLK,
        RESET_S   => MI_RESET,
        MI_S_DWR  => mi_sync_dwr,
        MI_S_ADDR => mi_sync_addr,
        MI_S_RD   => mi_sync_rd,
        MI_S_WR   => mi_sync_wr,
        MI_S_BE   => mi_sync_be,
        MI_S_DRD  => mi_sync_drd,
        MI_S_ARDY => mi_sync_ardy,
        MI_S_DRDY => mi_sync_drdy
    );

    mi_pipe_i : entity work.MI_PIPE
    generic map(
        DEVICE      => DEVICE,
        DATA_WIDTH  => 32,
        ADDR_WIDTH  => 32,
        PIPE_TYPE   => "REG",
        USE_OUTREG  => True,
        FAKE_PIPE   => False
    )
    port map(
        -- Common interface
        CLK      => MI_CLK,
        RESET    => MI_RESET,
        
        -- Input MI interface
        IN_DWR   => mi_sync_dwr,
        IN_ADDR  => mi_sync_addr,
        IN_RD    => mi_sync_rd,
        IN_WR    => mi_sync_wr,
        IN_BE    => mi_sync_be,
        IN_DRD   => mi_sync_drd,
        IN_ARDY  => mi_sync_ardy,
        IN_DRDY  => mi_sync_drdy,
        
        -- Output MI interface
        OUT_DWR  => MI_DWR,
        OUT_ADDR => MI_ADDR,
        OUT_RD   => MI_RD,
        OUT_WR   => MI_WR,
        OUT_BE   => MI_BE,
        OUT_DRD  => MI_DRD,
        OUT_ARDY => MI_ARDY,
        OUT_DRDY => MI_DRDY
    );
end architecture;
