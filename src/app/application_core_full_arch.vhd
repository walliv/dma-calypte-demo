-- application_core_full_arch.vhd: Run architecture of the APPLICATION_CORE
-- Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
-- Author(s): Vladislav Valek <vladislav.valek@stud.uni-heidelberg.de>
--
-- SPDX-License-Identifier: CERN-OHL-P-2.0

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.math_pack.all;
use work.type_pack.all;

library unisim;
use unisim.vcomponents.BUFG;

architecture FULL of APPLICATION_CORE is

    component RISCV_manycore_wrapper is
        generic (
            MI_WIDTH : natural := 32;

            MFB_REGIONS     : natural := 1;
            MFB_REGION_SIZE : natural := 4;
            MFB_BLOCK_SIZE  : natural := 1;
            MFB_ITEM_WIDTH  : natural := 1;

            USR_PKT_SIZE_MAX : natural := 2**11);
        port (
            clk   : in std_logic;
            reset : in std_logic;

            channel : out std_logic_vector(3 downto 0);

            DMA_RX_MFB_DATA    : out std_logic_vector(MFB_REGIONS*MFB_REGION_SIZE*MFB_BLOCK_SIZE*MFB_ITEM_WIDTH -1 downto 0);
            DMA_RX_MFB_SOF     : out std_logic_vector(MFB_REGIONS -1 downto 0);
            DMA_RX_MFB_EOF     : out std_logic_vector(MFB_REGIONS -1 downto 0);
            DMA_RX_MFB_SRC_VLD : out std_logic;
            DMA_RX_MFB_DST_RDY : in  std_logic);
    end component;

    -- =============================================================================================
    -- MI synchronizer
    -- =============================================================================================
    signal sync_mi_dwr  : std_logic_vector(MI_WIDTH-1 downto 0);
    signal sync_mi_addr : std_logic_vector(MI_WIDTH-1 downto 0);
    signal sync_mi_be   : std_logic_vector(MI_WIDTH/8-1 downto 0);
    signal sync_mi_rd   : std_logic;
    signal sync_mi_wr   : std_logic;
    signal sync_mi_drd  : std_logic_vector(MI_WIDTH-1 downto 0);
    signal sync_mi_ardy : std_logic;
    signal sync_mi_drdy : std_logic;

    -- =============================================================================================
    -- RX DMA adapter signals
    -- =============================================================================================
    signal dma_rx_mfb_data_int    : std_logic_vector(DMA_MFB_REGIONS*(DMA_MFB_REGION_SIZE/2)*DMA_MFB_BLOCK_SIZE*DMA_MFB_ITEM_WIDTH -1 downto 0);
    signal dma_rx_mfb_meta_int    : std_logic_vector(log2(DMA_RX_PKT_SIZE_MAX+1) + DMA_HDR_META_WIDTH + log2(DMA_RX_CHANNELS) -1 downto 0);
    signal dma_rx_mfb_sof_pos_int : std_logic_vector(DMA_MFB_REGIONS*maximum(1, log2(DMA_MFB_REGION_SIZE/2)) -1 downto 0);
    signal dma_rx_mfb_eof_pos_int : std_logic_vector(DMA_MFB_REGIONS*maximum(1, log2((DMA_MFB_REGION_SIZE/2)*DMA_MFB_BLOCK_SIZE)) -1 downto 0);

    -- =============================================================================================
    -- ASFIFOX ---> Manycore system
    -- =============================================================================================
    signal tx_mfb_data_mcore    : std_logic_vector(DMA_MFB_REGIONS*(DMA_MFB_REGION_SIZE/2)*DMA_MFB_BLOCK_SIZE*DMA_MFB_ITEM_WIDTH -1 downto 0);
    signal tx_mfb_meta_mcore    : std_logic_vector(log2(DMA_TX_PKT_SIZE_MAX+1) + DMA_HDR_META_WIDTH + log2(DMA_TX_CHANNELS) -1 downto 0);
    signal tx_mfb_sof_mcore     : std_logic_vector(DMA_MFB_REGIONS -1 downto 0);
    signal tx_mfb_eof_mcore     : std_logic_vector(DMA_MFB_REGIONS -1 downto 0);
    signal tx_mfb_sof_pos_mcore : std_logic_vector(DMA_MFB_REGIONS*maximum(1, log2(DMA_MFB_REGION_SIZE/2)) -1 downto 0);
    signal tx_mfb_eof_pos_mcore : std_logic_vector(DMA_MFB_REGIONS*maximum(1, log2((DMA_MFB_REGION_SIZE/2)*DMA_MFB_BLOCK_SIZE)) -1 downto 0);
    signal tx_mfb_src_rdy_mcore : std_logic;
    signal tx_mfb_dst_rdy_mcore : std_logic;

    -- =============================================================================================
    -- Manycore system ---> ASFIFOX
    -- =============================================================================================
    signal rx_mfb_meta_pkt_size_mcore : std_logic_vector(log2(DMA_RX_PKT_SIZE_MAX+1) -1 downto 0);
    signal rx_mfb_meta_hdr_meta_mcore : std_logic_vector(DMA_HDR_META_WIDTH -1 downto 0);
    signal rx_mfb_meta_chan_mcore     : std_logic_vector(log2(DMA_RX_CHANNELS) -1 downto 0);

    signal rx_mfb_data_mcore    : std_logic_vector(DMA_MFB_REGIONS*(DMA_MFB_REGION_SIZE/2)*DMA_MFB_BLOCK_SIZE*DMA_MFB_ITEM_WIDTH -1 downto 0);
    signal rx_mfb_sof_mcore     : std_logic_vector(DMA_MFB_REGIONS -1 downto 0);
    signal rx_mfb_eof_mcore     : std_logic_vector(DMA_MFB_REGIONS -1 downto 0);
    signal rx_mfb_sof_pos_mcore : std_logic_vector(DMA_MFB_REGIONS*maximum(1, log2(DMA_MFB_REGION_SIZE/2)) -1 downto 0);
    signal rx_mfb_eof_pos_mcore : std_logic_vector(DMA_MFB_REGIONS*maximum(1, log2((DMA_MFB_REGION_SIZE/2)*DMA_MFB_BLOCK_SIZE)) -1 downto 0);
    signal rx_mfb_src_rdy_mcore : std_logic;
    signal rx_mfb_dst_rdy_mcore : std_logic;

    -- =============================================================================================
    -- Miscelaneous
    -- =============================================================================================
    signal proc_rst          : std_logic;
    signal proc_rst_reg_1    : std_logic;
    signal proc_rst_reg_2    : std_logic;
    signal proc_rst_reg_3    : std_logic;
    signal proc_rst_reg_4    : std_logic;
    signal proc_rst_reg_5    : std_logic;
    signal proc_rst_reg_6    : std_logic;
    signal proc_rst_buffered : std_logic;

    signal perf_cnt_rst_sync : std_logic;
    signal fr_run_cntr       : unsigned(64 -1 downto 0);
    signal cntr_sample_val   : std_logic_vector(128 -1 downto 0);

begin

    assert (PCIE_ENDPOINTS = 1 and DMA_STREAMS = 1)
        report "APPLICATION_CORE(FULL): Unsupported amount of DMA streams and/or PCIE Endpoints, only one for each is allowed!"
        severity FAILURE;

    -- =============================================================================================
    --  MI32 LOGIC
    -- =============================================================================================
    mi_async_i : entity work.MI_ASYNC
        generic map(
            ADDR_WIDTH => MI_WIDTH,
            DATA_WIDTH => MI_WIDTH,
            DEVICE     => DEVICE)
        port map(
            -- Master interface
            CLK_M     => CLK_VECTOR(1),
            RESET_M   => RESET_VECTOR(1)(0),
            MI_M_DWR  => MI_DWR,
            MI_M_ADDR => MI_ADDR,
            MI_M_RD   => MI_RD,
            MI_M_WR   => MI_WR,
            MI_M_BE   => MI_BE,
            MI_M_DRD  => MI_DRD,
            MI_M_ARDY => MI_ARDY,
            MI_M_DRDY => MI_DRDY,

            -- Slave interface
            CLK_S     => CLK_VECTOR(0),
            RESET_S   => RESET_VECTOR(0)(0),
            MI_S_DWR  => sync_mi_dwr,
            MI_S_ADDR => sync_mi_addr,
            MI_S_RD   => sync_mi_rd,
            MI_S_WR   => sync_mi_wr,
            MI_S_BE   => sync_mi_be,
            MI_S_DRD  => sync_mi_drd,
            MI_S_ARDY => sync_mi_ardy,
            MI_S_DRDY => sync_mi_drdy);

    barrel_proc_debug_core_i : entity work.BARREL_PROC_DEBUG_CORE
        generic map (
            MI_WIDTH => MI_WIDTH)
        port map (
            CLK   => CLK_VECTOR(0),
            RESET => RESET_VECTOR(0)(1),

            RESET_OUT => proc_rst,
            MI_ADDR   => sync_mi_addr,
            MI_DWR    => sync_mi_dwr,
            MI_BE     => sync_mi_be,
            MI_RD     => sync_mi_rd,
            MI_WR     => sync_mi_wr,
            MI_DRD    => sync_mi_drd,
            MI_ARDY   => sync_mi_ardy,
            MI_DRDY   => sync_mi_drdy);

    prebufg_rst_regs : process (CLK_VECTOR(0)) is
    begin
        if (rising_edge(CLK_VECTOR(0))) then
            proc_rst_reg_1 <= proc_rst;
            proc_rst_reg_2 <= proc_rst_reg_1;
            proc_rst_reg_3 <= proc_rst_reg_2;

            proc_rst_reg_4 <= proc_rst_reg_3;
            proc_rst_reg_5 <= proc_rst_reg_4;
            proc_rst_reg_6 <= proc_rst_reg_5;
        end if;
    end process;

    proc_rst_buf_i : BUFG
        port map (
            O => proc_rst_buffered,
            I => proc_rst_reg_6);

    perf_cnt_rst_sync_i : entity work.ASYNC_RESET
        generic map (
            TWO_REG  => FALSE,
            OUT_REG  => FALSE,
            REPLICAS => 1)
        port map (
            CLK        => PCIE_USER_CLK(0),
            ASYNC_RST  => proc_rst_buffered,
            OUT_RST(0) => perf_cnt_rst_sync);

    free_run_cntr_p : process (PCIE_USER_CLK(0)) is
    begin
        if (rising_edge(PCIE_USER_CLK(0))) then
            if (perf_cnt_rst_sync = '1') then
                fr_run_cntr <= (others => '0');
            else
                fr_run_cntr <= fr_run_cntr + 1;
            end if;
        end if;
    end process;

    cntr_sample_val <= std_logic_vector(resize(fr_run_cntr, 128))
                       when (DMA_RX_MFB_SRC_RDY(0) = '1' and DMA_RX_MFB_DST_RDY(0) = '1')
                       else (others => '0');

    DMA_RX_MFB_META_PKT_SIZE(0) <= dma_rx_mfb_meta_int(log2(DMA_RX_PKT_SIZE_MAX+1) + DMA_HDR_META_WIDTH + log2(DMA_RX_CHANNELS) -1 downto DMA_HDR_META_WIDTH + log2(DMA_RX_CHANNELS));
    DMA_RX_MFB_META_HDR_META(0) <= dma_rx_mfb_meta_int(DMA_HDR_META_WIDTH + log2(DMA_RX_CHANNELS) -1 downto log2(DMA_RX_CHANNELS));
    DMA_RX_MFB_META_CHAN(0)     <= dma_rx_mfb_meta_int(log2(DMA_RX_CHANNELS) -1 downto 0);

    DMA_RX_MFB_DATA(0)    <= (255 downto 128 => cntr_sample_val, 127 downto 0 => dma_rx_mfb_data_int);
    DMA_RX_MFB_SOF_POS(0) <= (1              => '0', 0 => dma_rx_mfb_sof_pos_int);
    DMA_RX_MFB_EOF_POS(0) <= (3 downto 0     => dma_rx_mfb_eof_pos_int, others => '0');

    dma_rx_mfb_asfifox_i : entity work.MFB_ASFIFOX
        generic map (
            MFB_REGIONS         => DMA_MFB_REGIONS,
            MFB_REG_SIZE        => DMA_MFB_REGION_SIZE/2,
            MFB_BLOCK_SIZE      => DMA_MFB_BLOCK_SIZE,
            MFB_ITEM_WIDTH      => DMA_MFB_ITEM_WIDTH,
            FIFO_ITEMS          => 128,
            RAM_TYPE            => "BRAM",
            FWFT_MODE           => TRUE,
            OUTPUT_REG          => FALSE,
            METADATA_WIDTH      => log2(DMA_RX_PKT_SIZE_MAX + 1) + DMA_HDR_META_WIDTH + log2(DMA_RX_CHANNELS),
            DEVICE              => DEVICE,
            ALMOST_FULL_OFFSET  => 2,
            ALMOST_EMPTY_OFFSET => 2)
        port map (
            RX_CLK   => CLK_VECTOR(0),
            RX_RESET => RESET_VECTOR(0)(2),

            RX_DATA    => rx_mfb_data_mcore,
            RX_META    => rx_mfb_meta_pkt_size_mcore & rx_mfb_meta_hdr_meta_mcore & rx_mfb_meta_chan_mcore,
            RX_SOF     => rx_mfb_sof_mcore,
            RX_EOF     => rx_mfb_eof_mcore,
            RX_SOF_POS => rx_mfb_sof_pos_mcore,
            RX_EOF_POS => rx_mfb_eof_pos_mcore,
            RX_SRC_RDY => rx_mfb_src_rdy_mcore,
            RX_DST_RDY => rx_mfb_dst_rdy_mcore,
            RX_AFULL   => open,
            RX_STATUS  => open,

            TX_CLK   => PCIE_USER_CLK(0),
            TX_RESET => PCIE_USER_RESET(0),

            TX_DATA    => dma_rx_mfb_data_int,
            TX_META    => dma_rx_mfb_meta_int,
            TX_SOF     => DMA_RX_MFB_SOF(0),
            TX_EOF     => DMA_RX_MFB_EOF(0),
            TX_SOF_POS => dma_rx_mfb_sof_pos_int,
            TX_EOF_POS => dma_rx_mfb_eof_pos_int,
            TX_SRC_RDY => DMA_RX_MFB_SRC_RDY(0),
            TX_DST_RDY => DMA_RX_MFB_DST_RDY(0),
            TX_AEMPTY  => open,
            TX_STATUS  => open);

    dma_tx_mfb_asfifox_i : entity work.MFB_ASFIFOX
        generic map (
            MFB_REGIONS         => DMA_MFB_REGIONS,
            MFB_REG_SIZE        => DMA_MFB_REGION_SIZE/2,
            MFB_BLOCK_SIZE      => DMA_MFB_BLOCK_SIZE,
            MFB_ITEM_WIDTH      => DMA_MFB_ITEM_WIDTH,
            FIFO_ITEMS          => 128,
            RAM_TYPE            => "BRAM",
            FWFT_MODE           => TRUE,
            OUTPUT_REG          => FALSE,
            METADATA_WIDTH      => log2(DMA_TX_PKT_SIZE_MAX + 1) + DMA_HDR_META_WIDTH + log2(DMA_TX_CHANNELS),
            DEVICE              => DEVICE,
            ALMOST_FULL_OFFSET  => 2,
            ALMOST_EMPTY_OFFSET => 2)
        port map (

            RX_CLK   => PCIE_USER_CLK(0),
            RX_RESET => PCIE_USER_RESET(0),

            RX_DATA    => DMA_TX_MFB_DATA(0)(127 downto 0),
            RX_META    => DMA_TX_MFB_META_PKT_SIZE(0) & DMA_TX_MFB_META_HDR_META(0) & DMA_TX_MFB_META_CHAN(0),
            RX_SOF     => DMA_TX_MFB_SOF(0),
            RX_EOF     => DMA_TX_MFB_EOF(0),
            RX_SOF_POS => DMA_TX_MFB_SOF_POS(0)(0 downto 0),
            RX_EOF_POS => DMA_TX_MFB_EOF_POS(0)(3 downto 0),
            RX_SRC_RDY => DMA_TX_MFB_SRC_RDY(0),
            RX_DST_RDY => DMA_TX_MFB_DST_RDY(0),
            RX_AFULL   => open,
            RX_STATUS  => open,

            TX_CLK   => CLK_VECTOR(0),
            TX_RESET => RESET_VECTOR(0)(3),

            -- NOTE: This TX interface remains unconnected. The DST_RDY signal si set to permanent 1.
            TX_DATA    => tx_mfb_data_mcore,
            TX_META    => tx_mfb_meta_mcore,
            TX_SOF     => tx_mfb_sof_mcore,
            TX_EOF     => tx_mfb_eof_mcore,
            TX_SOF_POS => tx_mfb_sof_pos_mcore,
            TX_EOF_POS => tx_mfb_eof_pos_mcore,
            TX_SRC_RDY => tx_mfb_src_rdy_mcore,
            TX_DST_RDY => tx_mfb_dst_rdy_mcore,
            TX_AEMPTY  => open,
            TX_STATUS  => open);

    rx_mfb_meta_pkt_size_mcore <= std_logic_vector(to_unsigned(4096, log2(DMA_RX_PKT_SIZE_MAX+1)));
    rx_mfb_meta_hdr_meta_mcore <= (others => '0');

    rx_mfb_sof_pos_mcore <= (others => '0');
    rx_mfb_eof_pos_mcore <= (others => '1');

    tx_mfb_dst_rdy_mcore <= '1';

    manycore_wrapper_opt_i : RISCV_manycore_wrapper
        generic map(
            MI_WIDTH         => 32,
            MFB_REGIONS      => DMA_MFB_REGIONS,        -- Number of regions in word
            MFB_REGION_SIZE  => DMA_MFB_REGION_SIZE/2,  -- Number of blocks in region
            MFB_BLOCK_SIZE   => DMA_MFB_BLOCK_SIZE,     -- Number of items in block
            MFB_ITEM_WIDTH   => DMA_MFB_ITEM_WIDTH,     -- Width of one item in bits
            USR_PKT_SIZE_MAX => DMA_RX_PKT_SIZE_MAX)
        port map(
            clk                => CLK_VECTOR(0),
            reset              => proc_rst_buffered,
            channel            => rx_mfb_meta_chan_mcore,
            DMA_RX_MFB_DATA    => rx_mfb_data_mcore,
            DMA_RX_MFB_SOF     => rx_mfb_sof_mcore,
            DMA_RX_MFB_EOF     => rx_mfb_eof_mcore,
            DMA_RX_MFB_SRC_VLD => rx_mfb_src_rdy_mcore,
            DMA_RX_MFB_DST_RDY => rx_mfb_dst_rdy_mcore);
end architecture;
