-- dma.vhd: DMA Module Wrapper
-- Copyright (C) 2022 CESNET z. s. p. o.
-- Author(s): Jan Kubalek <kubalek@cesnet.cz>
--            Vladislav Valek <valekv@cesnet.cz>
--
-- SPDX-License-Identifier: BSD-3-Clause

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.math_pack.all;
use work.type_pack.all;

use work.dma_bus_pack.all;

architecture FULL of DMA is

    constant GLS_MI_OFFSET : std_logic_vector(32-1 downto 0) := X"0000_0200";

    function gls_mi_addr_base_f return slv_array_t is
        variable mi_addr_base_var : slv_array_t(DMA_STREAMS-1 downto 0)(32-1 downto 0);
    begin
        for i in 0 to DMA_STREAMS-1 loop
            mi_addr_base_var(i) := std_logic_vector(resize(i*unsigned(GLS_MI_OFFSET), 32));
        end loop;
        return mi_addr_base_var;
    end function;

    -- =====================================================================
    --  MI Splitting for multiple GLS
    -- =====================================================================
    signal gls_mi_addr : slv_array_t (DMA_STREAMS -1 downto 0)(32 -1 downto 0);
    signal gls_mi_dwr  : slv_array_t (DMA_STREAMS -1 downto 0)(32 -1 downto 0);
    signal gls_mi_be   : slv_array_t (DMA_STREAMS -1 downto 0)(32/8 -1 downto 0);
    signal gls_mi_rd   : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal gls_mi_wr   : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal gls_mi_drd  : slv_array_t (DMA_STREAMS -1 downto 0)(32 -1 downto 0);
    signal gls_mi_ardy : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal gls_mi_drdy : std_logic_vector(DMA_STREAMS -1 downto 0);

    -- =============================================================================================
    -- RX: Metadata extractor -> GLS
    -- =============================================================================================
    signal rx_usr_mvb_data_ext    : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*(log2(RX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(RX_CHANNELS)) -1 downto 0);
    signal rx_usr_mvb_vld_ext     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal rx_usr_mvb_src_rdy_ext : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal rx_usr_mvb_dst_rdy_ext : std_logic_vector(DMA_STREAMS -1 downto 0);

    signal rx_usr_mfb_data_ext    : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*USR_MFB_REGION_SIZE*USR_MFB_BLOCK_SIZE*USR_MFB_ITEM_WIDTH-1 downto 0);
    signal rx_usr_mfb_sof_ext     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal rx_usr_mfb_eof_ext     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal rx_usr_mfb_sof_pos_ext : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*max(1, log2(USR_MFB_REGION_SIZE)) -1 downto 0);
    signal rx_usr_mfb_eof_pos_ext : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*max(1, log2(USR_MFB_REGION_SIZE*USR_MFB_BLOCK_SIZE)) -1 downto 0);
    signal rx_usr_mfb_src_rdy_ext : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal rx_usr_mfb_dst_rdy_ext : std_logic_vector(DMA_STREAMS -1 downto 0);

    -- =============================================================================================
    -- TX: GLS -> Metadata insertor
    -- =============================================================================================
    signal tx_usr_mvb_pkt_size_gls : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*log2(TX_PKT_SIZE_MAX+1)-1 downto 0);
    signal tx_usr_mvb_hdr_meta_gls : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*HDR_META_WIDTH -1 downto 0);
    signal tx_usr_mvb_chan_gls     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*log2(TX_CHANNELS) -1 downto 0);
    signal tx_usr_mvb_vld_gls      : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal tx_usr_mvb_src_rdy_gls  : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal tx_usr_mvb_dst_rdy_gls  : std_logic_vector(DMA_STREAMS -1 downto 0);

    signal tx_usr_mfb_data_gls    : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*USR_MFB_REGION_SIZE*USR_MFB_BLOCK_SIZE*USR_MFB_ITEM_WIDTH-1 downto 0);
    signal tx_usr_mfb_sof_gls     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal tx_usr_mfb_eof_gls     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal tx_usr_mfb_sof_pos_gls : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*max(1, log2(USR_MFB_REGION_SIZE)) -1 downto 0);
    signal tx_usr_mfb_eof_pos_gls : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*max(1, log2(USR_MFB_REGION_SIZE*USR_MFB_BLOCK_SIZE)) -1 downto 0);
    signal tx_usr_mfb_src_rdy_gls : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal tx_usr_mfb_dst_rdy_gls : std_logic_vector(DMA_STREAMS -1 downto 0);

    -- =============================================================================================
    -- RX: GLS -> Metadata insertor
    -- =============================================================================================
    signal rx_usr_mvb_pkt_size_gls : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*log2(RX_PKT_SIZE_MAX+1)-1 downto 0);
    signal rx_usr_mvb_hdr_meta_gls : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*HDR_META_WIDTH -1 downto 0);
    signal rx_usr_mvb_chan_gls     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*log2(RX_CHANNELS) -1 downto 0);
    signal rx_usr_mvb_vld_gls      : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal rx_usr_mvb_src_rdy_gls  : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal rx_usr_mvb_dst_rdy_gls  : std_logic_vector(DMA_STREAMS -1 downto 0);

    signal rx_usr_mfb_data_gls    : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*USR_MFB_REGION_SIZE*USR_MFB_BLOCK_SIZE*USR_MFB_ITEM_WIDTH-1 downto 0);
    signal rx_usr_mfb_sof_gls     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal rx_usr_mfb_eof_gls     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal rx_usr_mfb_sof_pos_gls : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*max(1, log2(USR_MFB_REGION_SIZE)) -1 downto 0);
    signal rx_usr_mfb_eof_pos_gls : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*max(1, log2(USR_MFB_REGION_SIZE*USR_MFB_BLOCK_SIZE)) -1 downto 0);
    signal rx_usr_mfb_src_rdy_gls : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal rx_usr_mfb_dst_rdy_gls : std_logic_vector(DMA_STREAMS -1 downto 0);

    -- =============================================================================================
    -- TX: Metadata extractor -> GLS
    -- =============================================================================================
    signal tx_usr_mvb_data_ext    : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*(log2(TX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(TX_CHANNELS)) -1 downto 0);
    signal tx_usr_mvb_vld_ext     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal tx_usr_mvb_src_rdy_ext : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal tx_usr_mvb_dst_rdy_ext : std_logic_vector(DMA_STREAMS -1 downto 0);

    signal tx_usr_mfb_data_ext    : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*USR_MFB_REGION_SIZE*USR_MFB_BLOCK_SIZE*USR_MFB_ITEM_WIDTH-1 downto 0);
    signal tx_usr_mfb_sof_ext     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal tx_usr_mfb_eof_ext     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal tx_usr_mfb_sof_pos_ext : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*max(1, log2(USR_MFB_REGION_SIZE)) -1 downto 0);
    signal tx_usr_mfb_eof_pos_ext : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*max(1, log2(USR_MFB_REGION_SIZE*USR_MFB_BLOCK_SIZE)) -1 downto 0);
    signal tx_usr_mfb_src_rdy_ext : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal tx_usr_mfb_dst_rdy_ext : std_logic_vector(DMA_STREAMS -1 downto 0);

    -- =============================================================================================
    -- RX: Metadata insertor -> DMA wrapper
    -- =============================================================================================
    signal rx_usr_mfb_meta_pkt_size_ins : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*log2(RX_PKT_SIZE_MAX+1)-1 downto 0);
    signal rx_usr_mfb_meta_hdr_meta_ins : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*HDR_META_WIDTH -1 downto 0);
    signal rx_usr_mfb_meta_chan_ins     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*log2(RX_CHANNELS) -1 downto 0);

    signal rx_usr_mfb_data_ins    : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*USR_MFB_REGION_SIZE*USR_MFB_BLOCK_SIZE*USR_MFB_ITEM_WIDTH-1 downto 0);
    signal rx_usr_mfb_sof_ins     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal rx_usr_mfb_eof_ins     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal rx_usr_mfb_sof_pos_ins : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*max(1, log2(USR_MFB_REGION_SIZE)) -1 downto 0);
    signal rx_usr_mfb_eof_pos_ins : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*max(1, log2(USR_MFB_REGION_SIZE*USR_MFB_BLOCK_SIZE)) -1 downto 0);
    signal rx_usr_mfb_src_rdy_ins : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal rx_usr_mfb_dst_rdy_ins : std_logic_vector(DMA_STREAMS -1 downto 0);

    -- =============================================================================================
    -- TX: DMA wrapper -> Metadata extractor
    -- =============================================================================================
    signal tx_usr_mfb_meta_pkt_size_dma : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*log2(TX_PKT_SIZE_MAX+1)-1 downto 0);
    signal tx_usr_mfb_meta_hdr_meta_dma : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*HDR_META_WIDTH -1 downto 0);
    signal tx_usr_mfb_meta_chan_dma     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*log2(TX_CHANNELS) -1 downto 0);

    signal tx_usr_mfb_data_dma    : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*USR_MFB_REGION_SIZE*USR_MFB_BLOCK_SIZE*USR_MFB_ITEM_WIDTH-1 downto 0);
    signal tx_usr_mfb_sof_dma     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal tx_usr_mfb_eof_dma     : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS -1 downto 0);
    signal tx_usr_mfb_sof_pos_dma : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*max(1, log2(USR_MFB_REGION_SIZE)) -1 downto 0);
    signal tx_usr_mfb_eof_pos_dma : slv_array_t(DMA_STREAMS -1 downto 0)(USR_MFB_REGIONS*max(1, log2(USR_MFB_REGION_SIZE*USR_MFB_BLOCK_SIZE)) -1 downto 0);
    signal tx_usr_mfb_src_rdy_dma : std_logic_vector(DMA_STREAMS -1 downto 0);
    signal tx_usr_mfb_dst_rdy_dma : std_logic_vector(DMA_STREAMS -1 downto 0);

    -- =============================================================================================
    -- Miscellaneous
    -- =============================================================================================
    -- helper signal to parse the output of the metadata insertor to the output ports
    signal tx_usr_mfb_meta_ins : slv_array_t(DMA_STREAMS -1 downto 0)(log2(TX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(TX_CHANNELS) -1 downto 0);
    -- helper signal to parse metatdata on the RX interface of the DMA wrapper
    signal rx_usr_mfb_meta_ins : slv_array_t(DMA_STREAMS -1 downto 0)(log2(RX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(RX_CHANNELS) -1 downto 0);
begin

    -- =====================================================================
    --  DMA Module
    -- =====================================================================
    dma_wrapper_i : entity work.DMA_WRAPPER
        generic map(
            DEVICE => DEVICE,

            DMA_STREAMS => DMA_STREAMS,

            USR_MFB_REGIONS     => USR_MFB_REGIONS,
            USR_MFB_REGION_SIZE => USR_MFB_REGION_SIZE,
            USR_MFB_BLOCK_SIZE  => USR_MFB_BLOCK_SIZE,
            USR_MFB_ITEM_WIDTH  => USR_MFB_ITEM_WIDTH,

            PCIE_RQ_MFB_REGIONS     => PCIE_RQ_MFB_REGIONS,
            PCIE_RQ_MFB_REGION_SIZE => PCIE_RQ_MFB_REGION_SIZE,
            PCIE_RQ_MFB_BLOCK_SIZE  => PCIE_RQ_MFB_BLOCK_SIZE,
            PCIE_RQ_MFB_ITEM_WIDTH  => PCIE_RQ_MFB_ITEM_WIDTH,

            PCIE_RC_MFB_REGIONS     => PCIE_RC_MFB_REGIONS,
            PCIE_RC_MFB_REGION_SIZE => PCIE_RC_MFB_REGION_SIZE,
            PCIE_RC_MFB_BLOCK_SIZE  => PCIE_RC_MFB_BLOCK_SIZE,
            PCIE_RC_MFB_ITEM_WIDTH  => PCIE_RC_MFB_ITEM_WIDTH,

            PCIE_CQ_MFB_REGIONS     => PCIE_CQ_MFB_REGIONS,
            PCIE_CQ_MFB_REGION_SIZE => PCIE_CQ_MFB_REGION_SIZE,
            PCIE_CQ_MFB_BLOCK_SIZE  => PCIE_CQ_MFB_BLOCK_SIZE,
            PCIE_CQ_MFB_ITEM_WIDTH  => PCIE_CQ_MFB_ITEM_WIDTH,

            PCIE_CC_MFB_REGIONS     => PCIE_CC_MFB_REGIONS,
            PCIE_CC_MFB_REGION_SIZE => PCIE_CC_MFB_REGION_SIZE,
            PCIE_CC_MFB_BLOCK_SIZE  => PCIE_CC_MFB_BLOCK_SIZE,
            PCIE_CC_MFB_ITEM_WIDTH  => PCIE_CC_MFB_ITEM_WIDTH,

            HDR_META_WIDTH => HDR_META_WIDTH,

            RX_CHANNELS      => RX_CHANNELS,
            RX_PTR_WIDTH     => RX_PTR_WIDTH,
            RX_BLOCKING_MODE => RX_BLOCKING_MODE,
            RX_PKT_SIZE_MAX  => RX_PKT_SIZE_MAX,

            TX_CHANNELS     => TX_CHANNELS,
            TX_PTR_WIDTH    => TX_PTR_WIDTH,
            TX_PKT_SIZE_MAX => TX_PKT_SIZE_MAX,

            RX_GEN_EN => RX_GEN_EN,
            TX_GEN_EN => TX_GEN_EN,

            DMA_DEBUG_ENABLE => DMA_DEBUG_ENABLE,

            MI_WIDTH => 32
            )
        port map(
            MI_CLK   => MI_CLK,
            MI_RESET => MI_RESET,

            USR_CLK   => USR_CLK,
            USR_RESET => USR_RESET,

            RX_USR_MFB_META_PKT_SIZE => rx_usr_mfb_meta_pkt_size_ins,
            RX_USR_MFB_META_HDR_META => rx_usr_mfb_meta_hdr_meta_ins,
            RX_USR_MFB_META_CHAN     => rx_usr_mfb_meta_chan_ins,

            RX_USR_MFB_DATA    => rx_usr_mfb_data_ins,
            RX_USR_MFB_SOF     => rx_usr_mfb_sof_ins,
            RX_USR_MFB_EOF     => rx_usr_mfb_eof_ins,
            RX_USR_MFB_SOF_POS => rx_usr_mfb_sof_pos_ins,
            RX_USR_MFB_EOF_POS => rx_usr_mfb_eof_pos_ins,
            RX_USR_MFB_SRC_RDY => rx_usr_mfb_src_rdy_ins,
            RX_USR_MFB_DST_RDY => rx_usr_mfb_dst_rdy_ins,

            TX_USR_MFB_META_PKT_SIZE => tx_usr_mfb_meta_pkt_size_dma,
            TX_USR_MFB_META_HDR_META => tx_usr_mfb_meta_hdr_meta_dma,
            TX_USR_MFB_META_CHAN     => tx_usr_mfb_meta_chan_dma,

            TX_USR_MFB_DATA    => tx_usr_mfb_data_dma,
            TX_USR_MFB_SOF     => tx_usr_mfb_sof_dma,
            TX_USR_MFB_EOF     => tx_usr_mfb_eof_dma,
            TX_USR_MFB_SOF_POS => tx_usr_mfb_sof_pos_dma,
            TX_USR_MFB_EOF_POS => tx_usr_mfb_eof_pos_dma,
            TX_USR_MFB_SRC_RDY => tx_usr_mfb_src_rdy_dma,
            TX_USR_MFB_DST_RDY => tx_usr_mfb_dst_rdy_dma,

            PCIE_RQ_MFB_DATA    => PCIE_RQ_MFB_DATA,
            PCIE_RQ_MFB_META    => PCIE_RQ_MFB_META,
            PCIE_RQ_MFB_SOF     => PCIE_RQ_MFB_SOF,
            PCIE_RQ_MFB_EOF     => PCIE_RQ_MFB_EOF,
            PCIE_RQ_MFB_SOF_POS => PCIE_RQ_MFB_SOF_POS,
            PCIE_RQ_MFB_EOF_POS => PCIE_RQ_MFB_EOF_POS,
            PCIE_RQ_MFB_SRC_RDY => PCIE_RQ_MFB_SRC_RDY,
            PCIE_RQ_MFB_DST_RDY => PCIE_RQ_MFB_DST_RDY,

            PCIE_RC_MFB_DATA    => PCIE_RC_MFB_DATA,
            PCIE_RC_MFB_SOF     => PCIE_RC_MFB_SOF,
            PCIE_RC_MFB_EOF     => PCIE_RC_MFB_EOF,
            PCIE_RC_MFB_SOF_POS => PCIE_RC_MFB_SOF_POS,
            PCIE_RC_MFB_EOF_POS => PCIE_RC_MFB_EOF_POS,
            PCIE_RC_MFB_SRC_RDY => PCIE_RC_MFB_SRC_RDY,
            PCIE_RC_MFB_DST_RDY => PCIE_RC_MFB_DST_RDY,

            PCIE_CQ_MFB_DATA    => PCIE_CQ_MFB_DATA,
            PCIE_CQ_MFB_META    => PCIE_CQ_MFB_META,
            PCIE_CQ_MFB_SOF     => PCIE_CQ_MFB_SOF,
            PCIE_CQ_MFB_EOF     => PCIE_CQ_MFB_EOF,
            PCIE_CQ_MFB_SOF_POS => PCIE_CQ_MFB_SOF_POS,
            PCIE_CQ_MFB_EOF_POS => PCIE_CQ_MFB_EOF_POS,
            PCIE_CQ_MFB_SRC_RDY => PCIE_CQ_MFB_SRC_RDY,
            PCIE_CQ_MFB_DST_RDY => PCIE_CQ_MFB_DST_RDY,

            PCIE_CC_MFB_DATA    => PCIE_CC_MFB_DATA,
            PCIE_CC_MFB_META    => PCIE_CC_MFB_META,
            PCIE_CC_MFB_SOF     => PCIE_CC_MFB_SOF,
            PCIE_CC_MFB_EOF     => PCIE_CC_MFB_EOF,
            PCIE_CC_MFB_SOF_POS => PCIE_CC_MFB_SOF_POS,
            PCIE_CC_MFB_EOF_POS => PCIE_CC_MFB_EOF_POS,
            PCIE_CC_MFB_SRC_RDY => PCIE_CC_MFB_SRC_RDY,
            PCIE_CC_MFB_DST_RDY => PCIE_CC_MFB_DST_RDY,

            MI_ADDR => MI_ADDR,
            MI_DWR  => MI_DWR,
            MI_BE   => MI_BE,
            MI_RD   => MI_RD,
            MI_WR   => MI_WR,
            MI_DRD  => MI_DRD,
            MI_ARDY => MI_ARDY,
            MI_DRDY => MI_DRDY
            );
    -- =====================================================================

    gls_mi_split_g : if (GEN_LOOP_EN) generate
        mi_splitter_gls_i : entity work.MI_SPLITTER_PLUS_GEN
            generic map(
                ADDR_WIDTH => 32,
                DATA_WIDTH => 32,
                META_WIDTH => 0,
                PORTS      => DMA_STREAMS,
                ADDR_BASE  => gls_mi_addr_base_f,
                DEVICE     => DEVICE
                )
            port map(
                CLK   => MI_CLK,
                RESET => MI_RESET,

                RX_DWR  => GEN_LOOP_MI_DWR,
                RX_ADDR => GEN_LOOP_MI_ADDR,
                RX_BE   => GEN_LOOP_MI_BE,
                RX_RD   => GEN_LOOP_MI_RD,
                RX_WR   => GEN_LOOP_MI_WR,
                RX_ARDY => GEN_LOOP_MI_ARDY,
                RX_DRD  => GEN_LOOP_MI_DRD,
                RX_DRDY => GEN_LOOP_MI_DRDY,

                TX_DWR  => gls_mi_dwr,
                TX_ADDR => gls_mi_addr,
                TX_BE   => gls_mi_be,
                TX_RD   => gls_mi_rd,
                TX_WR   => gls_mi_wr,
                TX_ARDY => gls_mi_ardy,
                TX_DRD  => gls_mi_drd,
                TX_DRDY => gls_mi_drdy
                );
    else generate
        GEN_LOOP_MI_ARDY <= GEN_LOOP_MI_RD or GEN_LOOP_MI_WR;
        GEN_LOOP_MI_DRD  <= x"DEADBEAD";
        GEN_LOOP_MI_DRDY <= GEN_LOOP_MI_RD;
    end generate;

    gls_g : for stream in 0 to DMA_STREAMS-1 generate
        gls_en_g : if (GEN_LOOP_EN) generate

            rx_usr_meta_extract_i : entity work.METADATA_EXTRACTOR
                generic map (
                    MVB_ITEMS => USR_MFB_REGIONS,

                    MFB_REGIONS     => USR_MFB_REGIONS,
                    MFB_REGION_SIZE => USR_MFB_REGION_SIZE,
                    MFB_BLOCK_SIZE  => USR_MFB_BLOCK_SIZE,
                    MFB_ITEM_WIDTH  => USR_MFB_ITEM_WIDTH,
                    MFB_META_WIDTH  => log2(RX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(RX_CHANNELS),

                    EXTRACT_MODE     => 0,
                    MVB_SHAKEDOWN_EN => TRUE,
                    OUT_MVB_PIPE_EN  => TRUE,
                    OUT_MFB_PIPE_EN  => TRUE,
                    DEVICE           => DEVICE)
                port map (
                    CLK   => USR_CLK(stream),
                    RESET => USR_RESET(stream),

                    RX_MFB_DATA    => RX_USR_MFB_DATA(stream),
                    RX_MFB_META    => RX_USR_MFB_META_PKT_SIZE(stream) & RX_USR_MFB_META_HDR_META(stream) & RX_USR_MFB_META_CHAN(stream),
                    RX_MFB_SOF     => RX_USR_MFB_SOF(stream),
                    RX_MFB_EOF     => RX_USR_MFB_EOF(stream),
                    RX_MFB_SOF_POS => RX_USR_MFB_SOF_POS(stream),
                    RX_MFB_EOF_POS => RX_USR_MFB_EOF_POS(stream),
                    RX_MFB_SRC_RDY => RX_USR_MFB_SRC_RDY(stream),
                    RX_MFB_DST_RDY => RX_USR_MFB_DST_RDY(stream),

                    TX_MVB_DATA    => rx_usr_mvb_data_ext(stream),
                    TX_MVB_VLD     => rx_usr_mvb_vld_ext(stream),
                    TX_MVB_SRC_RDY => rx_usr_mvb_src_rdy_ext(stream),
                    TX_MVB_DST_RDY => rx_usr_mvb_dst_rdy_ext(stream),

                    TX_MFB_DATA    => rx_usr_mfb_data_ext(stream),
                    TX_MFB_META    => open,
                    TX_MFB_SOF     => rx_usr_mfb_sof_ext(stream),
                    TX_MFB_EOF     => rx_usr_mfb_eof_ext(stream),
                    TX_MFB_SOF_POS => rx_usr_mfb_sof_pos_ext(stream),
                    TX_MFB_EOF_POS => rx_usr_mfb_eof_pos_ext(stream),
                    TX_MFB_SRC_RDY => rx_usr_mfb_src_rdy_ext(stream),
                    TX_MFB_DST_RDY => rx_usr_mfb_dst_rdy_ext(stream));

            tx_usr_meta_insert_i : entity work.METADATA_INSERTOR
                generic map (
                    MVB_ITEMS      => USR_MFB_REGIONS,
                    MVB_ITEM_WIDTH => log2(TX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(TX_CHANNELS),

                    MFB_REGIONS     => USR_MFB_REGIONS,
                    MFB_REGION_SIZE => USR_MFB_REGION_SIZE,
                    MFB_BLOCK_SIZE  => USR_MFB_BLOCK_SIZE,
                    MFB_ITEM_WIDTH  => USR_MFB_ITEM_WIDTH,
                    MFB_META_WIDTH  => log2(TX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(TX_CHANNELS),

                    INSERT_MODE     => 0,
                    MVB_FIFO_SIZE   => 16,
                    MVB_FIFOX_MULTI => TRUE,
                    DEVICE          => DEVICE)
                port map (
                    CLK   => USR_CLK(stream),
                    RESET => USR_RESET(stream),

                    RX_MVB_DATA    => tx_usr_mvb_pkt_size_gls(stream) & tx_usr_mvb_hdr_meta_gls(stream) & tx_usr_mvb_chan_gls(stream),
                    RX_MVB_VLD     => tx_usr_mvb_vld_gls(stream),
                    RX_MVB_SRC_RDY => tx_usr_mvb_src_rdy_gls(stream),
                    RX_MVB_DST_RDY => tx_usr_mvb_dst_rdy_gls(stream),

                    RX_MFB_DATA    => tx_usr_mfb_data_gls(stream),
                    RX_MFB_META    => (others => '0'),
                    RX_MFB_SOF     => tx_usr_mfb_sof_gls(stream),
                    RX_MFB_EOF     => tx_usr_mfb_eof_gls(stream),
                    RX_MFB_SOF_POS => tx_usr_mfb_sof_pos_gls(stream),
                    RX_MFB_EOF_POS => tx_usr_mfb_eof_pos_gls(stream),
                    RX_MFB_SRC_RDY => tx_usr_mfb_src_rdy_gls(stream),
                    RX_MFB_DST_RDY => tx_usr_mfb_dst_rdy_gls(stream),

                    TX_MFB_DATA     => TX_USR_MFB_DATA(stream),
                    TX_MFB_META     => open,
                    -- TODO: connect this meta signal to the output
                    TX_MFB_META_NEW => tx_usr_mfb_meta_ins(stream),
                    TX_MFB_SOF      => TX_USR_MFB_SOF(stream),
                    TX_MFB_EOF      => TX_USR_MFB_EOF(stream),
                    TX_MFB_SOF_POS  => TX_USR_MFB_SOF_POS(stream),
                    TX_MFB_EOF_POS  => TX_USR_MFB_EOF_POS(stream),
                    TX_MFB_SRC_RDY  => TX_USR_MFB_SRC_RDY(stream),
                    TX_MFB_DST_RDY  => TX_USR_MFB_DST_RDY(stream));

            TX_USR_MFB_META_PKT_SIZE(stream) <= tx_usr_mfb_meta_ins(stream)(log2(TX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(TX_CHANNELS) -1 downto HDR_META_WIDTH + log2(TX_CHANNELS));
            TX_USR_MFB_META_HDR_META(stream) <= tx_usr_mfb_meta_ins(stream)(HDR_META_WIDTH + log2(TX_CHANNELS) -1 downto log2(TX_CHANNELS));
            TX_USR_MFB_META_CHAN(stream)     <= tx_usr_mfb_meta_ins(stream)(log2(TX_CHANNELS) -1 downto 0);

            gen_loop_switch_i : entity work.GEN_LOOP_SWITCH
                generic map(
                    REGIONS         => USR_MFB_REGIONS,
                    REGION_SIZE     => USR_MFB_REGION_SIZE,
                    BLOCK_SIZE      => USR_MFB_BLOCK_SIZE,
                    ITEM_WIDTH      => USR_MFB_ITEM_WIDTH,
                    PKT_MTU         => RX_PKT_SIZE_MAX,
                    RX_DMA_CHANNELS => RX_CHANNELS,
                    TX_DMA_CHANNELS => TX_CHANNELS,
                    HDR_META_WIDTH  => HDR_META_WIDTH,
                    RX_HDR_INS_EN   => FALSE,  -- only enable for version 1 to DMA Medusa
                    SAME_CLK        => FALSE,
                    MI_PIPE_EN      => TRUE,
                    DEVICE          => DEVICE
                    )
                port map(
                    MI_CLK   => MI_CLK,
                    MI_RESET => MI_RESET,
                    MI_DWR   => gls_mi_dwr(stream),
                    MI_ADDR  => gls_mi_addr(stream),
                    MI_BE    => gls_mi_be(stream),
                    MI_RD    => gls_mi_rd(stream),
                    MI_WR    => gls_mi_wr(stream),
                    MI_ARDY  => gls_mi_ardy(stream),
                    MI_DRD   => gls_mi_drd(stream),
                    MI_DRDY  => gls_mi_drdy(stream),

                    CLK   => USR_CLK(stream),
                    RESET => USR_RESET(stream),

                    ETH_RX_MVB_LEN      => rx_usr_mvb_data_ext(stream)(log2(RX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(RX_CHANNELS) -1 downto HDR_META_WIDTH + log2(RX_CHANNELS)),
                    ETH_RX_MVB_HDR_META => rx_usr_mvb_data_ext(stream)(HDR_META_WIDTH + log2(RX_CHANNELS) -1 downto log2(RX_CHANNELS)),
                    ETH_RX_MVB_CHANNEL  => rx_usr_mvb_data_ext(stream)(log2(RX_CHANNELS) -1 downto 0),
                    ETH_RX_MVB_DISCARD  => (others => '0'),
                    ETH_RX_MVB_VLD      => rx_usr_mvb_vld_ext(stream),
                    ETH_RX_MVB_SRC_RDY  => rx_usr_mvb_src_rdy_ext(stream),
                    ETH_RX_MVB_DST_RDY  => rx_usr_mvb_dst_rdy_ext(stream),

                    ETH_RX_MFB_DATA    => rx_usr_mfb_data_ext(stream),
                    ETH_RX_MFB_SOF     => rx_usr_mfb_sof_ext(stream),
                    ETH_RX_MFB_EOF     => rx_usr_mfb_eof_ext(stream),
                    ETH_RX_MFB_SOF_POS => rx_usr_mfb_sof_pos_ext(stream),
                    ETH_RX_MFB_EOF_POS => rx_usr_mfb_eof_pos_ext(stream),
                    ETH_RX_MFB_SRC_RDY => rx_usr_mfb_src_rdy_ext(stream),
                    ETH_RX_MFB_DST_RDY => rx_usr_mfb_dst_rdy_ext(stream),

                    ETH_TX_MVB_LEN      => tx_usr_mvb_pkt_size_gls(stream),
                    ETH_TX_MVB_HDR_META => tx_usr_mvb_hdr_meta_gls(stream),
                    ETH_TX_MVB_CHANNEL  => tx_usr_mvb_chan_gls(stream),
                    ETH_TX_MVB_VLD      => tx_usr_mvb_vld_gls(stream),
                    ETH_TX_MVB_SRC_RDY  => tx_usr_mvb_src_rdy_gls(stream),
                    ETH_TX_MVB_DST_RDY  => tx_usr_mvb_dst_rdy_gls(stream),

                    ETH_TX_MFB_DATA    => tx_usr_mfb_data_gls(stream),
                    ETH_TX_MFB_SOF     => tx_usr_mfb_sof_gls(stream),
                    ETH_TX_MFB_EOF     => tx_usr_mfb_eof_gls(stream),
                    ETH_TX_MFB_SOF_POS => tx_usr_mfb_sof_pos_gls(stream),
                    ETH_TX_MFB_EOF_POS => tx_usr_mfb_eof_pos_gls(stream),
                    ETH_TX_MFB_SRC_RDY => tx_usr_mfb_src_rdy_gls(stream),
                    ETH_TX_MFB_DST_RDY => tx_usr_mfb_dst_rdy_gls(stream),

                    DMA_RX_MVB_LEN      => rx_usr_mvb_pkt_size_gls(stream),
                    DMA_RX_MVB_HDR_META => rx_usr_mvb_hdr_meta_gls(stream),
                    DMA_RX_MVB_CHANNEL  => rx_usr_mvb_chan_gls(stream),
                    DMA_RX_MVB_DISCARD  => open,
                    DMA_RX_MVB_VLD      => rx_usr_mvb_vld_gls(stream),
                    DMA_RX_MVB_SRC_RDY  => rx_usr_mvb_src_rdy_gls(stream),
                    DMA_RX_MVB_DST_RDY  => rx_usr_mvb_dst_rdy_gls(stream),

                    DMA_RX_MFB_DATA    => rx_usr_mfb_data_gls(stream),
                    DMA_RX_MFB_SOF     => rx_usr_mfb_sof_gls(stream),
                    DMA_RX_MFB_EOF     => rx_usr_mfb_eof_gls(stream),
                    DMA_RX_MFB_SOF_POS => rx_usr_mfb_sof_pos_gls(stream),
                    DMA_RX_MFB_EOF_POS => rx_usr_mfb_eof_pos_gls(stream),
                    DMA_RX_MFB_SRC_RDY => rx_usr_mfb_src_rdy_gls(stream),
                    DMA_RX_MFB_DST_RDY => rx_usr_mfb_dst_rdy_gls(stream),

                    DMA_TX_MVB_LEN      => tx_usr_mvb_data_ext(stream)(log2(TX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(TX_CHANNELS) -1 downto HDR_META_WIDTH + log2(TX_CHANNELS)),
                    DMA_TX_MVB_HDR_META => tx_usr_mvb_data_ext(stream)(HDR_META_WIDTH + log2(TX_CHANNELS) -1 downto log2(TX_CHANNELS)),
                    DMA_TX_MVB_CHANNEL  => tx_usr_mvb_data_ext(stream)(log2(TX_CHANNELS) -1 downto 0),
                    DMA_TX_MVB_VLD      => tx_usr_mvb_vld_ext(stream),
                    DMA_TX_MVB_SRC_RDY  => tx_usr_mvb_src_rdy_ext(stream),
                    DMA_TX_MVB_DST_RDY  => tx_usr_mvb_dst_rdy_ext(stream),

                    DMA_TX_MFB_DATA    => tx_usr_mfb_data_ext(stream),
                    DMA_TX_MFB_SOF     => tx_usr_mfb_sof_ext(stream),
                    DMA_TX_MFB_EOF     => tx_usr_mfb_eof_ext(stream),
                    DMA_TX_MFB_SOF_POS => tx_usr_mfb_sof_pos_ext(stream),
                    DMA_TX_MFB_EOF_POS => tx_usr_mfb_eof_pos_ext(stream),
                    DMA_TX_MFB_SRC_RDY => tx_usr_mfb_src_rdy_ext(stream),
                    DMA_TX_MFB_DST_RDY => tx_usr_mfb_dst_rdy_ext(stream)
                    );

            rx_dma_meta_insert_i : entity work.METADATA_INSERTOR
                generic map (
                    MVB_ITEMS      => USR_MFB_REGIONS,
                    MVB_ITEM_WIDTH => log2(RX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(RX_CHANNELS),

                    MFB_REGIONS     => USR_MFB_REGIONS,
                    MFB_REGION_SIZE => USR_MFB_REGION_SIZE,
                    MFB_BLOCK_SIZE  => USR_MFB_BLOCK_SIZE,
                    MFB_ITEM_WIDTH  => USR_MFB_ITEM_WIDTH,
                    MFB_META_WIDTH  => log2(RX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(RX_CHANNELS),

                    INSERT_MODE     => 0,
                    MVB_FIFO_SIZE   => 16,
                    MVB_FIFOX_MULTI => TRUE,
                    DEVICE          => DEVICE)
                port map (
                    CLK   => USR_CLK(stream),
                    RESET => USR_RESET(stream),

                    RX_MVB_DATA    => rx_usr_mvb_pkt_size_gls(stream) & rx_usr_mvb_hdr_meta_gls(stream) & rx_usr_mvb_chan_gls(stream),
                    RX_MVB_VLD     => rx_usr_mvb_vld_gls(stream),
                    RX_MVB_SRC_RDY => rx_usr_mvb_src_rdy_gls(stream),
                    RX_MVB_DST_RDY => rx_usr_mvb_dst_rdy_gls(stream),

                    RX_MFB_DATA    => rx_usr_mfb_data_gls(stream),
                    RX_MFB_META    => (others => '0'),
                    RX_MFB_SOF     => rx_usr_mfb_sof_gls(stream),
                    RX_MFB_EOF     => rx_usr_mfb_eof_gls(stream),
                    RX_MFB_SOF_POS => rx_usr_mfb_sof_pos_gls(stream),
                    RX_MFB_EOF_POS => rx_usr_mfb_eof_pos_gls(stream),
                    RX_MFB_SRC_RDY => rx_usr_mfb_src_rdy_gls(stream),
                    RX_MFB_DST_RDY => rx_usr_mfb_dst_rdy_gls(stream),

                    TX_MFB_DATA     => rx_usr_mfb_data_ins(stream),
                    TX_MFB_META     => open,
                    TX_MFB_META_NEW => rx_usr_mfb_meta_ins(stream),
                    TX_MFB_SOF      => rx_usr_mfb_sof_ins(stream),
                    TX_MFB_EOF      => rx_usr_mfb_eof_ins(stream),
                    TX_MFB_SOF_POS  => rx_usr_mfb_sof_pos_ins(stream),
                    TX_MFB_EOF_POS  => rx_usr_mfb_eof_pos_ins(stream),
                    TX_MFB_SRC_RDY  => rx_usr_mfb_src_rdy_ins(stream),
                    TX_MFB_DST_RDY  => rx_usr_mfb_dst_rdy_ins(stream));

            rx_usr_mfb_meta_pkt_size_ins(stream) <= rx_usr_mfb_meta_ins(stream)(log2(RX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(RX_CHANNELS) -1 downto HDR_META_WIDTH + log2(RX_CHANNELS));
            rx_usr_mfb_meta_hdr_meta_ins(stream) <= rx_usr_mfb_meta_ins(stream)(HDR_META_WIDTH + log2(RX_CHANNELS) -1 downto log2(RX_CHANNELS));
            rx_usr_mfb_meta_chan_ins(stream)     <= rx_usr_mfb_meta_ins(stream)(log2(RX_CHANNELS) -1 downto 0);

            tx_dma_meta_extract_i : entity work.METADATA_EXTRACTOR
                generic map (
                    MVB_ITEMS => USR_MFB_REGIONS,

                    MFB_REGIONS     => USR_MFB_REGIONS,
                    MFB_REGION_SIZE => USR_MFB_REGION_SIZE,
                    MFB_BLOCK_SIZE  => USR_MFB_BLOCK_SIZE,
                    MFB_ITEM_WIDTH  => USR_MFB_ITEM_WIDTH,
                    MFB_META_WIDTH  => log2(TX_PKT_SIZE_MAX+1) + HDR_META_WIDTH + log2(TX_CHANNELS),

                    EXTRACT_MODE     => 0,
                    MVB_SHAKEDOWN_EN => TRUE,
                    OUT_MVB_PIPE_EN  => TRUE,
                    OUT_MFB_PIPE_EN  => TRUE,
                    DEVICE           => DEVICE)
                port map (
                    CLK   => USR_CLK(stream),
                    RESET => USR_RESET(stream),

                    RX_MFB_DATA    => tx_usr_mfb_data_dma(stream),
                    RX_MFB_META    => tx_usr_mfb_meta_pkt_size_dma(stream) & tx_usr_mfb_meta_hdr_meta_dma(stream) & tx_usr_mfb_meta_chan_dma(stream),
                    RX_MFB_SOF     => tx_usr_mfb_sof_dma(stream),
                    RX_MFB_EOF     => tx_usr_mfb_eof_dma(stream),
                    RX_MFB_SOF_POS => tx_usr_mfb_sof_pos_dma(stream),
                    RX_MFB_EOF_POS => tx_usr_mfb_eof_pos_dma(stream),
                    RX_MFB_SRC_RDY => tx_usr_mfb_src_rdy_dma(stream),
                    RX_MFB_DST_RDY => tx_usr_mfb_dst_rdy_dma(stream),

                    TX_MVB_DATA    => tx_usr_mvb_data_ext(stream),
                    TX_MVB_VLD     => tx_usr_mvb_vld_ext(stream),
                    TX_MVB_SRC_RDY => tx_usr_mvb_src_rdy_ext(stream),
                    TX_MVB_DST_RDY => tx_usr_mvb_dst_rdy_ext(stream),

                    TX_MFB_DATA    => tx_usr_mfb_data_ext(stream),
                    TX_MFB_META    => open,
                    TX_MFB_SOF     => tx_usr_mfb_sof_ext(stream),
                    TX_MFB_EOF     => tx_usr_mfb_eof_ext(stream),
                    TX_MFB_SOF_POS => tx_usr_mfb_sof_pos_ext(stream),
                    TX_MFB_EOF_POS => tx_usr_mfb_eof_pos_ext(stream),
                    TX_MFB_SRC_RDY => tx_usr_mfb_src_rdy_ext(stream),
                    TX_MFB_DST_RDY => tx_usr_mfb_dst_rdy_ext(stream));

        else generate

            rx_usr_mfb_meta_pkt_size_ins(stream) <= RX_USR_MFB_META_PKT_SIZE(stream);
            rx_usr_mfb_meta_hdr_meta_ins(stream) <= RX_USR_MFB_META_HDR_META(stream);
            rx_usr_mfb_meta_chan_ins(stream)     <= RX_USR_MFB_META_CHAN(stream);

            rx_usr_mfb_data_ins(stream)    <= RX_USR_MFB_DATA(stream);
            rx_usr_mfb_sof_ins(stream)     <= RX_USR_MFB_SOF(stream);
            rx_usr_mfb_eof_ins(stream)     <= RX_USR_MFB_EOF(stream);
            rx_usr_mfb_sof_pos_ins(stream) <= RX_USR_MFB_SOF_POS(stream);
            rx_usr_mfb_eof_pos_ins(stream) <= RX_USR_MFB_EOF_POS(stream);
            rx_usr_mfb_src_rdy_ins(stream) <= RX_USR_MFB_SRC_RDY(stream);
            RX_USR_MFB_DST_RDY(stream)     <= rx_usr_mfb_dst_rdy_ins(stream);

            TX_USR_MFB_META_PKT_SIZE(stream) <= tx_usr_mfb_meta_pkt_size_dma(stream);
            TX_USR_MFB_META_HDR_META(stream) <= tx_usr_mfb_meta_hdr_meta_dma(stream);
            TX_USR_MFB_META_CHAN(stream)     <= tx_usr_mfb_meta_chan_dma(stream);

            TX_USR_MFB_DATA(stream)        <= tx_usr_mfb_data_dma(stream);
            TX_USR_MFB_SOF(stream)         <= tx_usr_mfb_sof_dma(stream);
            TX_USR_MFB_EOF(stream)         <= tx_usr_mfb_eof_dma(stream);
            TX_USR_MFB_SOF_POS(stream)     <= tx_usr_mfb_sof_pos_dma(stream);
            TX_USR_MFB_EOF_POS(stream)     <= tx_usr_mfb_eof_pos_dma(stream);
            TX_USR_MFB_SRC_RDY(stream)     <= tx_usr_mfb_src_rdy_dma(stream);
            tx_usr_mfb_dst_rdy_dma(stream) <= TX_USR_MFB_DST_RDY(stream);
        end generate;
    end generate;
end architecture;
