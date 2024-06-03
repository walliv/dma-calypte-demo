#!/usr/bin/env python3
#
# gls_mod.py: Script that measures the throughput of the DMA in the FPGA design
# with each direction (RX/TX) but also its combination.  Upon running this
# script with given paramters (simply run the script without them to see the
# available options), it iterates through a sequence of packet lengths (by
# default from 60 to 1500 B corresponding to the Ethernet traffic) and measures
# a throughput of the PCIE/DMA system for each of them.
# Copyright (C) 2022 CESNET z. s. p. o.
# Author: Jakub Cabal <cabal@cesnet.cz> 
#
# SPDX-License-Identifier: BSD-3-Clause

import sys
import subprocess
import time
import os
import csv
import signal

class GracefulExiter():

    def __init__(self):
        self.state = False
        signal.signal(signal.SIGINT, self.change_state)

    def change_state(self, signum, frame):
        print("Exit flag set to True")
        signal.signal(signal.SIGINT, signal.SIG_DFL)
        self.state = True

    def exit(self):
        return self.state

def nfb_bus(path,addr,value=None):
    pcie_index=0
    if (value==None): # read
        return int("0x"+subprocess.Popen("nfb-bus -i%d -p%s %s" % (pcie_index,path,hex(addr)),shell=True,stdout=subprocess.PIPE).stdout.read().strip().decode("utf-8"),16)
    else: # write
        return subprocess.call("nfb-bus -i%d -p%s %s %s" % (pcie_index,path,hex(addr),hex(value)),shell=True)

def sm_get_speed(path,offset,frequency,type=0):
    done = 0
    check_cnt = 0
    if type == 1:
        ticks_offset = 0x44
        bytes_offset = 0x48
        max_offset = 0x28
    else:
        ticks_offset = 0x0 
        bytes_offset = 0x8
        max_offset = 0x4

    # Check if speed meter is done
    while (done != 1 and check_cnt < 10):
        done = nfb_bus(path,offset+max_offset)
        if type == 1:
            done = done >> 28
        check_cnt += 1
        #print(check_cnt)
        time.sleep(0.01)

    # read accumulated bytes and convert to Gigabits
    sm_bytes = nfb_bus(path,offset+bytes_offset) * 8/(10**9)
    if sm_bytes == 0:
        return 0
    
    # read test length in number of ticks
    sm_ticks = nfb_bus(path,offset+ticks_offset)
    sm_run_time = sm_ticks/frequency
    
    return round(sm_bytes/sm_run_time, 2)

def sm_reset(path,offset,type=0):
    if type == 1:
        nfb_bus(path,offset+0x2C, 0x4)
    else:
        nfb_bus(path,offset+0xC, 0x1)

def run_test(mode,min_fr_size,max_fr_size,fr_size_step,gls_clk_freq,log_en,demo_en,port_list,dma_streams,port_dma_channels):

    os.system("killall ndp-generate -9 2> /dev/null; killall ndp-read -9 2> /dev/null")

    if log_en:
        file_str = "./report_" + mode + ".csv"
        # Open CSV file to save data
        f = open(file_str, 'w', newline='')
        writer = csv.writer(f)

        # CSV file row
        row = ["Length", "TX APP speed","RX APP speed"]
        writer.writerow(row)

    sm_gls_eth_tx_addr = 0x70
    sm_gls_eth_rx_addr = 0x60
    sm_gls_dma_tx_addr = 0x50
    sm_gls_dma_rx_addr = 0x40

    dt_path_gls = {}
    dt_path_gen2eth = {}
    dt_path_gen2dma = {}

    # List of frame lengths for TX generator(s)
    fr_lengths = []
    fr_lengths = list(range(min_fr_size, max_fr_size, fr_size_step))

    for p in dma_streams:
        # Prepare DT paths
        dt_path_gls[p] = "/firmware/mi_bus0/dbg_gls"+str(p)
        dt_path_gen2eth[p] = dt_path_gls[p]+"/mfb_gen2eth"
        dt_path_gen2dma[p] = dt_path_gls[p]+"/mfb_gen2dma"
        # Set GLS muxes back to default
        nfb_bus(dt_path_gls[p], 0x00, 0x0)
        nfb_bus(dt_path_gls[p], 0x04, 0x0)
        nfb_bus(dt_path_gls[p], 0x08, 0x0)
        nfb_bus(dt_path_gls[p], 0x0C, 0x0)
        # Set GLS GEN channel range to default
        nfb_bus(dt_path_gen2eth[p], 0xC, 0xffff0000)
        nfb_bus(dt_path_gen2dma[p], 0xC, 0xffff0000)

    channel_list = []
    for p in port_list:
        for i in range(port_dma_channels):
            channel_list.append(int(p)*port_dma_channels+i)
    channel_list_str = ','.join(str(e) for e in channel_list)
    channel_min = min(channel_list)
    channel_max = max(channel_list)
    chan_range = (65536*channel_max)+channel_min
    print("INFO: Selected queues: %s\n" % channel_list_str)
    #print(channel_min)
    #print(channel_max)
    #print(chan_range)

    # Select correct SpeedMeters
    sm_tx_addr = sm_gls_eth_tx_addr
    sm_rx_addr = sm_gls_eth_rx_addr
    if (mode=="dma_rx" or mode=="dma_tx" or mode=="dma_rxtx" or mode=="dma_loop"):
        sm_tx_addr = sm_gls_dma_tx_addr
        sm_rx_addr = sm_gls_dma_rx_addr

    # Setup loopback paths in GLS
    if (mode=="dma_rx" or mode=="dma_rxtx"):
        # create a black hole for the RX data (DMA input will be from RX generator)
        for p in dma_streams:
            nfb_bus(dt_path_gls[p], 0x08, 0x1)
    if (mode=="dma_tx" or mode=="dma_rxtx" or mode=="dma_loop"):
        # make the TX generator the source of data
        for p in dma_streams:
            nfb_bus(dt_path_gls[p], 0x0C, 0x1)
    if (mode=="dma_loop"):
        # enable DMA loopback (TX to RX)
        for p in dma_streams:
            nfb_bus(dt_path_gls[p], 0x00, 0x1)

    # Enable RX DMA for all channels
    if (mode=="dma_rx" or mode=="dma_rxtx" or mode=="dma_loop"):
        ndp_read = subprocess.Popen("ndp-read",shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        time.sleep(0.5)

    for i in range(len(fr_lengths)):
        length = fr_lengths[i]
        print("Frame Size (with CRC):     % 4i [Bytes]" % length)
        print("----------------------------------------")

        if (mode=="dma_tx" or mode=="dma_rxtx" or mode=="dma_loop"):
            ndp_gen = subprocess.Popen("ndp-generate -s%d -i %s" % (length,channel_list_str),shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if (mode=="dma_rx" or mode=="dma_rxtx"):
            for p in dma_streams:
                # set GLS RX generator
                nfb_bus(dt_path_gen2dma[p], 0x4, length)
                # select correct channel range for device with single GLS
                if dma_streams != port_list:
                    nfb_bus(dt_path_gen2dma[p], 0xC, chan_range)
                # channel reverse
                #nfb_bus(dt_path_gen2dma[p], 0x8, 0x10101)
                # channel 0 only
                nfb_bus(dt_path_gen2dma[p], 0x8, 0x10001)
                # Start RX generator
                nfb_bus(dt_path_gen2dma[p], 0x0, 0x1)

        time.sleep(0.1)
        tx_total_speed = 0
        rx_total_speed = 0

        for p in dma_streams:
            print("DMA Stream: " + str(p))
            tx_app_speed = 0
            rx_app_speed = 0
            measurements = 2

            for j in range(measurements):
                # Reset TX and RX speed meter
                sm_reset(dt_path_gls[p], sm_tx_addr)
                sm_reset(dt_path_gls[p], sm_rx_addr)
                tx_speed = sm_get_speed(dt_path_gls[p],sm_tx_addr,gls_clk_freq)
                rx_speed = sm_get_speed(dt_path_gls[p],sm_rx_addr,gls_clk_freq)
                tx_app_speed += tx_speed
                rx_app_speed += rx_speed
                time.sleep(0.05)

            tx_app_speed = round((tx_app_speed/measurements),2)
            rx_app_speed = round((rx_app_speed/measurements),2)

            print("Stream Speed TX:          % 7.2f [Gbps]" % tx_app_speed)
            print("Stream Speed RX:          % 7.2f [Gbps]" % rx_app_speed)
            print("----------------------------------------")

            tx_total_speed += tx_app_speed
            rx_total_speed += rx_app_speed
            
        tx_total_speed = round(tx_total_speed,2)
        rx_total_speed = round(rx_total_speed,2)

        print("Total Speed TX:           % 7.2f [Gbps]" % tx_total_speed)
        print("Total Speed RX:           % 7.2f [Gbps]" % rx_total_speed)
        print("========================================")

        if demo_en:
            demo_gui = open("/tmp/demo_gui.txt", "w")
            demo_gui.write(str(length) + '\n')
            demo_gui.write(str(tx_total_speed) + '\n')
            demo_gui.write(str(rx_total_speed))
            demo_gui.close()
    
        # Stop TX generator
        if (mode=="dma_tx" or mode=="dma_rxtx" or mode=="dma_loop"):
            ndp_gen.send_signal(signal.SIGINT)
        if (mode=="dma_rx" or mode=="dma_rxtx"):
            # Stop RX generator
            nfb_bus(dt_path_gen2dma[p], 0x0, 0x0)

        if log_en:
            # Save row to CSV file
            row = [str(length), str(tx_total_speed), str(rx_total_speed)]
            writer.writerow(row) # write data to CSV file

    if (mode=="dma_rx" or mode=="dma_rxtx" or mode=="dma_loop"):
        ndp_read.send_signal(signal.SIGINT)
        ndp_read.terminate()

    if log_en:
        f.close()
    if demo_en:
        os.remove("/tmp/demo_gui.txt")

    # Set muxes back to default
    for p in dma_streams:
        nfb_bus(dt_path_gls[p], 0x00, 0x0)
        nfb_bus(dt_path_gls[p], 0x04, 0x0)
        nfb_bus(dt_path_gls[p], 0x08, 0x0)
        nfb_bus(dt_path_gls[p], 0x0C, 0x0)

# ==============================================================================
# GLS MAIN FUNCTION
# ==============================================================================

def print_modes():
    print("gls_mod.py mode [port_list]")
    print("Example: gls_mod.py 1 \"0,1\"")
    print()
    print("Supported modes:")
    print("1: HW Gen --> RX DMA     ###")
    print("2: TX DMA --> Black Hole ###")
    print("3: TX DMA --> Black Hole ### HW Gen --> RX DMA;")
    print("4: TX DMA --> RX DMA     ### (internal DMA loopback)")
    print()
    print("Port list: (default: \"0\")")
    print("List of used ports (Warning: On cards with a single DMA stream,")
    print("the ports must be selected consecutively, so for example")
    print("the option \"0,2,3\" cannot be selected! This is a limitation of the HW")
    print("packet generator.)\n")
    print("Additional configuration is available inside the script.")

if __name__ == '__main__':
    args = []
    args = sys.argv[1:]

    if len(args) == 0 or len(args) > 2:
        print_modes()
        exit()
    elif args[0] == "1":
        mode="dma_rx"
    elif args[0] == "2":
        mode="dma_tx"
    elif args[0] == "3":
        mode="dma_rxtx"
    elif args[0] == "4":
        mode="dma_loop"
    else:
        print("Incorrect mode!\n")
        print_modes()
        exit()
    
    port_list = [0]
    if len(args) > 1:
        port_list = list(args[1].split(","))

    # ==========================================================================
    # TEST CONFIGURATION (can be changed by the user)
    # ==========================================================================

    # Speed meter clock frequency in HZ (needs to be checed on the specific design), a.k.a.
    # the clock frequency on a communication bus the GLS is connected to.
    gls_clk_freq = 250000000 # 250 MHz

    # Define min and max frame sizes (in bytes)
    # This length range and the step can be set individually but there are some
    # limitations:
    # 1. The absolute minimum length of a packet can be 60 B
    # 2. The absolute maximum length of a packet can be up to 4096 B
    #
    # The step size can be set even to 1 for finest measurement.
    min_fr_size = 60
    max_fr_size = 1500
    fr_size_step = 32

    # Enables logging of the measured parameters to the CSV file (the file is named
    # accoring to the current value of the "mode")
    log_en = False
    # When true, the current measurement result is written to a file that can be read
    # by the GUI to show the results in a fancy way.
    demo_en = False
    # Runs the measurement (e.g. all packet lengths in the specified range) only
    # once. Otherwise, the measurement repeats starting again from the lowes
    # specified packet length.
    single_cycle = True
    # ==========================================================================

    print("INFO: Finding information about NDK firmware...")
    card_name = subprocess.Popen("nfb-info -q card",shell=True,stdout=subprocess.PIPE).stdout.read().strip().decode("utf-8")
    # Total number of Ethernet ports on card
    print("INFO: Card name:      %s" % card_name)
    # Get total number of DMA channels
    dma_chan_rx = int(subprocess.Popen("nfb-info -q rx",shell=True,stdout=subprocess.PIPE).stdout.read().strip())
    dma_chan_tx = int(subprocess.Popen("nfb-info -q tx",shell=True,stdout=subprocess.PIPE).stdout.read().strip())
    print("INFO: DMA RX queues:  %d" % dma_chan_rx)
    print("INFO: DMA TX queues:  %d" % dma_chan_tx)

    gls_count = int(subprocess.Popen("nfb-bus -l | grep gen_loop_switch | wc -l",shell=True,stdout=subprocess.PIPE).stdout.read().strip())
    print("INFO: GLS modules:    %d" % gls_count)
    if (gls_count == 0):
        print("ERROR: Unsupported NDK firmware, no GLS modules found!")
        exit()

    dma_channels = min(dma_chan_rx, dma_chan_tx)

    force_single_dma_stream = False
    if (gls_count == 1):
        force_single_dma_stream = True

    dma_streams = port_list
    if force_single_dma_stream:
        dma_streams = [0]
    port_dma_channels = int(dma_channels)

    # ==========================================================================
    # GLS TEST START
    # ==========================================================================

    x = 1
    flag = GracefulExiter()
    while True:
        print("\nINFO: Test #",x,"started...")
        run_test(mode,min_fr_size,max_fr_size,fr_size_step,gls_clk_freq,log_en,demo_en,port_list,dma_streams,port_dma_channels)
        x+=1
        print("finished.")
        if single_cycle or flag.exit():
            break
