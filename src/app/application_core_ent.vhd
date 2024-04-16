-- application_ent.vhd: Entity of user application core
-- Copyright (C) 2020 CESNET z. s. p. o.
-- Author(s): Daniel Kondys <xkondy00@vutbr.cz>
--            Jakub Cabal <cabal@cesnet.cz>
--
-- SPDX-License-Identifier: BSD-3-Clause

library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
use work.type_pack.all;

use work.math_pack.all;
use work.type_pack.all;

entity APPLICATION_CORE is
generic (
    -- Number of instantiated PCIe endpoints
    PCIE_ENDPOINTS     : natural := 1;
    -- DMA: number of DMA streams
    DMA_STREAMS        : natural := 1;

    -- DMA: number of RX channel per DMA stream
    DMA_RX_CHANNELS    : natural := 16;
    -- DMA: number of TX channel per DMA stream
    DMA_TX_CHANNELS    : natural := 16;
    -- DMA: size of User Header Metadata in bits
    DMA_HDR_META_WIDTH : natural := 12;

    -- DMA: Maximum size of a packet on RX DMA interfaces (in bytes)
    DMA_RX_PKT_SIZE_MAX : natural := 2**12;
    -- DMA: Maximum size of a packet on TX DMA interfaces (in bytes)
    DMA_TX_PKT_SIZE_MAX : natural := 2**12;

    -- DMA MFB: number of regions in word
    DMA_MFB_REGIONS       : natural := 1;
    -- DMA MFB: number of blocks in region
    DMA_MFB_REGION_SIZE   : natural := 8;
    -- MFB parameters: number of items in block
    DMA_MFB_BLOCK_SIZE    : natural := 8;
    -- MFB parameters: width of one item in bits
    DMA_MFB_ITEM_WIDTH    : natural := 8;

    -- The amount of HBM channels (0 to 32)
    HBM_CHANNELS       : natural := 0;
    -- MI parameters: width of data signals
    MI_WIDTH           : integer := 32;
    -- Width of a reset signal
    CLK_WIDTH          : integer := 2;
    -- Width of reset signals
    RESET_WIDTH        : integer := 2;
    -- Width of the FPGA chip identifier
    FPGA_ID_WIDTH      : natural := 20;

    -- Name of an FPGA board
    BOARD              : string := "UNKNOWN";
    -- Name of an FPGA device
    DEVICE             : string := "ULTRASCALE"
);
port (
    -- =============================================================================================
    -- USER CLOCK AND RESET INPUTS
    -- =============================================================================================
    CLK_VECTOR   : in std_logic_vector(CLK_WIDTH -1 downto 0);
    RESET_VECTOR : in slv_array_t(CLK_WIDTH -1 downto 0)(RESET_WIDTH -1 downto 0);

    PCIE_USER_CLK   : in std_logic_vector(PCIE_ENDPOINTS -1 downto 0);
    PCIE_USER_RESET : in std_logic_vector(PCIE_ENDPOINTS -1 downto 0);

    -- =============================================================================================
    -- STATUS INPUTS
    -- =============================================================================================
    -- Link Up flags of each PCIe endpoints, active when PCIe EP is ready for data transfers.
    -- DMA channels are statically and evenly mapped to all PCIe EPs (clocked at PCIE_USER_CLK)
    PCIE_LINK_UP            : in  std_logic_vector(PCIE_ENDPOINTS-1 downto 0);
    -- Unique identification number of the FPGA chip (clocked at CLK_VECTOR(1))
    FPGA_ID                 : in  std_logic_vector(FPGA_ID_WIDTH-1 downto 0);
    FPGA_ID_VLD             : in  std_logic;

    -- =============================================================================================
    -- RX DMA STREAMS (clocked at PCIE_USER_CLK by default)
    --
    -- MFB interfaces to DMA module (to software). Each packet is accompanied by a metadata that are
    -- valid when corresponding SOF is se to 1
    -- =============================================================================================
    -- DMA RX MVB streams: length of data packet in bytes
    DMA_RX_MFB_META_PKT_SIZE : out slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*log2(DMA_RX_PKT_SIZE_MAX+1)-1 downto 0);
    -- DMA RX MVB streams: user metadata for DMA header
    DMA_RX_MFB_META_HDR_META : out slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*DMA_HDR_META_WIDTH-1 downto 0);
    -- DMA RX MVB streams: number of DMA channel
    DMA_RX_MFB_META_CHAN     : out slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*log2(DMA_RX_CHANNELS)-1 downto 0);

    -- DMA RX MFB streams: data word with frames (packets)
    DMA_RX_MFB_DATA          : out slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*DMA_MFB_REGION_SIZE*DMA_MFB_BLOCK_SIZE*DMA_MFB_ITEM_WIDTH-1 downto 0);
    -- DMA RX MFB streams: Start Of Frame (SOF) flag for each MFB region
    DMA_RX_MFB_SOF           : out slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS-1 downto 0);
    -- DMA RX MFB streams: End Of Frame (EOF) flag for each MFB region
    DMA_RX_MFB_EOF           : out slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS-1 downto 0);
    -- DMA RX MFB streams: SOF position for each MFB region in MFB blocks
    DMA_RX_MFB_SOF_POS       : out slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*max(1,log2(DMA_MFB_REGION_SIZE))-1 downto 0);
    -- DMA RX MFB streams: EOF position for each MFB region in MFB items
    DMA_RX_MFB_EOF_POS       : out slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*max(1,log2(DMA_MFB_REGION_SIZE*DMA_MFB_BLOCK_SIZE))-1 downto 0);
    -- DMA RX MFB streams: source ready of each MFB bus
    DMA_RX_MFB_SRC_RDY       : out std_logic_vector(DMA_STREAMS-1 downto 0);
    -- DMA RX MFB streams: destination ready of each MFB bus
    DMA_RX_MFB_DST_RDY       : in  std_logic_vector(DMA_STREAMS-1 downto 0);

    -- =============================================================================================
    -- TX DMA STREAMS (clocked at PCIE_USER_CLK by default)
    --
    -- MFB interface from DMA module (from software). Each packet contains metadata that are valid
    -- with the corresponding SOF in a region.
    -- =============================================================================================
    -- DMA TX MVB streams: length of data packet in bytes
    DMA_TX_MFB_META_PKT_SIZE : in  slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*log2(DMA_TX_PKT_SIZE_MAX+1)-1 downto 0);
    -- DMA TX MVB streams: user metadata for DMA header
    DMA_TX_MFB_META_HDR_META : in  slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*DMA_HDR_META_WIDTH-1 downto 0);
    -- DMA TX MVB streams: number of DMA channel
    DMA_TX_MFB_META_CHAN     : in  slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*log2(DMA_TX_CHANNELS)-1 downto 0);

    -- DMA TX MFB streams: data word with frames (packets)
    DMA_TX_MFB_DATA          : in  slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*DMA_MFB_REGION_SIZE*DMA_MFB_BLOCK_SIZE*DMA_MFB_ITEM_WIDTH-1 downto 0);
    -- DMA TX MFB streams: Start Of Frame (SOF) flag for each MFB region
    DMA_TX_MFB_SOF           : in  slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS-1 downto 0);
    -- DMA TX MFB streams: End Of Frame (EOF) flag for each MFB region
    DMA_TX_MFB_EOF           : in  slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS-1 downto 0);
    -- DMA TX MFB streams: SOF position for each MFB region in MFB blocks
    DMA_TX_MFB_SOF_POS       : in  slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*max(1,log2(DMA_MFB_REGION_SIZE))-1 downto 0);
    -- DMA TX MFB streams: EOF position for each MFB region in MFB items
    DMA_TX_MFB_EOF_POS       : in  slv_array_t(DMA_STREAMS -1 downto 0)(DMA_MFB_REGIONS*max(1,log2(DMA_MFB_REGION_SIZE*DMA_MFB_BLOCK_SIZE))-1 downto 0);
    -- DMA TX MFB streams: source ready of each MFB bus
    DMA_TX_MFB_SRC_RDY       : in  std_logic_vector(DMA_STREAMS-1 downto 0);
    -- DMA TX MFB streams: destination ready of each MFB bus
    DMA_TX_MFB_DST_RDY       : out std_logic_vector(DMA_STREAMS-1 downto 0);

    -- =============================================================================================
    -- HBM signals
    -- =============================================================================================
    HBM_REFCLK_P             : in std_logic;
    HBM_REFCLK_N             : in std_logic;
    HBM_CATTRIP              : out std_logic;

    -- =============================================================================================
    -- MI INTERFACE (clocked at CLK_VECTOR(1) by default)
    -- =============================================================================================
    -- MI bus: data from master to slave (write data)
    MI_DWR                  : in  std_logic_vector(MI_WIDTH-1 downto 0);
    -- MI bus: slave address
    MI_ADDR                 : in  std_logic_vector(MI_WIDTH-1 downto 0);
    -- MI bus: byte enable
    MI_BE                   : in  std_logic_vector(MI_WIDTH/8-1 downto 0);
    -- MI bus: read request
    MI_RD                   : in  std_logic;
    -- MI bus: write request
    MI_WR                   : in  std_logic;
    -- MI bus: ready of slave module
    MI_ARDY                 : out std_logic;
    -- MI bus: data from slave to master (read data)
    MI_DRD                  : out std_logic_vector(MI_WIDTH-1 downto 0);
    -- MI bus: valid of MI_DRD data signal
    MI_DRDY                 : out std_logic
);
end entity;
