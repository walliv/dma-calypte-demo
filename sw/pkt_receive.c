// Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
// SPDX-License-Identifier: Apache-2.0

/* This program provides and example to how receive data on a host from
   the F2H controller inside and FPGA.

   Compilation:
	Prerequisities: You have a nfb-framework package installed on your
	machine.

	gcc pkt_receive.c -o pkt_receive.o -lnfb
	*/


#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>
#include <stdint.h>
#include <err.h>

#include <pthread.h>

// Necessary header files to interact with the FPGA design
// nfb.h is used for interaction with design's Configuration/Status registers
//      (NFB = Network Firmware Base)
// ndp.h is used for data transmission through the DMA engine
//      (NDP = Network Data Pane)
#include <nfb/nfb.h>
#include <nfb/ndp.h>

/* NOTE: The declaration of the packet structure in nfb/ndp.h
struct ndp_packet {
	unsigned char *data; // packet data location
	unsigned char *header; // packet metadata location (TODO)
	uint32_t data_length;  // packet data length in bytes
	uint16_t header_length;  // packet metadata length (set to 0)
	uint16_t flags;  // packet specific flags length (TODO)
}

A queue is a DMA channel inside the FPGA through which data can be independetly
transfered (received from F2H controller or sent to the H2F controller). Each
controller has its own set of queues. These can also be controlled in parallel,
using multiple threads.
*/

#define NDP_PACKET_COUNT 64
#define QUEUE_COUNT 15

struct ThreadData {
	struct ndp_queue *rxq;
	int *pkts_per_row_total;
	FILE *fileptr;
};

// This function is about to be executed within each thread.
void *packet_reception(void *arg) {
	struct ThreadData *data = (struct ThreadData *)arg;
	struct ndp_packet pkts[NDP_PACKET_COUNT];
	int ret;

	/* In order to prevent endless cycling, the amount of iteration for this
	loop can be limited, when f.e. some data are expected but never come. */
	while (*(data->pkts_per_row_total) > 0) {

		// Request reception of packets. The requested amount is
		// specified by NDP_PACKET_COUNT which means at most this amount
		// of packet will be received. The pkts structure is passed to
		// the function call to be filled with valid packets. A queue
		// structure is passed through "data" structure.
		ret = ndp_rx_burst_get(data->rxq, pkts, NDP_PACKET_COUNT);
		printf("Received %d packets.\n", ret);

		if (ret == 0)
			continue;

		*(data->pkts_per_row_total) -= ret;

		for (int k = 0; k < ret; k++)
			fwrite(pkts[k].data, pkts[k].data_length, 1, data->fileptr);

		// Release packets that were read. Between the call of
		// ndp_rx_burst_get and ndp_rx_burst_put, the data are still held
		// in the queue and can be processed. The pkts structure holds
		// only the pointers to the packets in the queue. No packet data
		// are copied unless specifically done by the user.
		//
		// NOTE: Always remember to follow the call of ndp_rx_burst_get by
		// the ndp_rx_burst_put.
		ndp_rx_burst_put(data->rxq);
	}

	pthread_exit(NULL);
}

int main(int argc, char *argv[])
{
	// Limits to how many data shoould be received through F2H controller
	const int max_iterations = 6;
	int pkts_per_row_per_it [QUEUE_COUNT]= {18,18,18,18,18,14,14,15,15,18,18,18,18,18,18};
	// Counters of remaining packets within each queue
	int pkts_per_row_remain [QUEUE_COUNT];

	int ret = -1;
	struct nfb_device *dev;
	int comp_offs;
	struct nfb_comp *comp;
	// The queues are numbered in the same manner as seen when running
	// the nfb-dma command.
	struct ndp_queue *rxq[QUEUE_COUNT];
	pthread_t threads[QUEUE_COUNT];
	FILE *fileptr_1[QUEUE_COUNT];
	struct ThreadData thread_data[QUEUE_COUNT];

	/* ====================================================
	 Initialization
	 =================================================== */
	// Initialize packet counters to the total amount for each channel
	for (int i = 0; i < QUEUE_COUNT; i++)
		pkts_per_row_remain[i] = max_iterations * pkts_per_row_per_it[i];

	// Open files for each channel
	for (int i = 0; i < QUEUE_COUNT; i++) {
		// Output file name
		char filename_1[16];
		sprintf(filename_1, "dma_data_%d.dat", i);

		// Open file to write the data in
		fileptr_1[i] = fopen(filename_1, "wb");
		if (fileptr_1[i] == NULL)
			errx(-1, "Can't open file for data write.");
	}

	// Open the NFB device (a software representation of a FPGA card)
	if ((dev = nfb_open("0")) == NULL) {
		fprintf(stderr, "Can't open device file.\n");
		goto close_files;
	}

	// First, find component for reset inside an FPGAs' Device Tree.
	// THe component is identified by its "compatible string" which, in this
	// case, is "ziti,minimal,multicore_debug_core", the first component
	// found (index 0) is chosen to be initialized.
	comp_offs = nfb_comp_find(dev, "ziti,minimal,multicore_debug_core",0);
	if (comp_offs < 0) {
		fprintf(stderr, "Couldn't find component.\n");
		goto close_nfb_dev;
	}

	// Open the component we found in previous step(creates software
	// representation of an FPGA component) to be controlled
	comp = nfb_comp_open(dev,comp_offs);
	if (comp == NULL) {
		fprintf(stderr, "Can't open component file.\n");
		goto close_nfb_dev;
	}

	/* Secondly, open F2H queues for data receive */
	for (int i = 0; i < QUEUE_COUNT; i++) {
		rxq[i] = ndp_open_rx_queue(dev, i);
		if (rxq[i] == NULL) {
			fprintf(stderr, "Can't open queue %d\n", i);
			goto close_nfb_comp;
		}
	}

	/* Here the queues have been found and a software representation
	  of each has been initilaized in the rxq array. The queues, however,
	 have to be started (enabled in the FPGA design) in order to transmit
	 data. */

	/* Start F2H queues */
	for (int i = 0; i < QUEUE_COUNT; i++) {
		ret = ndp_queue_start(rxq[i]);
		if (ret != 0) {
			fprintf(stderr, "Unable to start queue %d\n", i);
			goto close_ndp_queues;
		}
	}

	/* ====================================================
	 Put system to a reset
	 =================================================== */
	// Reset the Manycore system. This sends a value of logical 1 on the
	// addres 0x00 in "comp". If a register is initialized on this address,
	// the register is set to 1.
	nfb_comp_write32(comp,0,1);

	/* ====================================================
	 Data receive
	 =================================================== */
	/* Create threads for packet reception. The parallel reception is used
	  since the sequential reception does not work for some reason. */
	for (int i = 0; i < QUEUE_COUNT; i++) {
		thread_data[i].rxq = rxq[i];
		thread_data[i].pkts_per_row_total = &pkts_per_row_remain[i];
		thread_data[i].fileptr = fileptr_1[i];
		pthread_create(&threads[i], NULL, packet_reception, (void *)&thread_data[i]);
	}

	/* Wait for all threads to finish */
	for (int i = 0; i < QUEUE_COUNT; i++) {
		pthread_join(threads[i], NULL);
	}

	// Because everything ran smoothly, return the ret variable to the
	// neutral value.
	ret = 0;

	/* ====================================================
	  Cleanup
	 =================================================== */
	// In the end, all counters should be 0.
	for (int i = 0; i < QUEUE_COUNT; i++)
		printf("Pkt counter %d: %d\n", i, pkts_per_row_remain[i]);

stop_ndp_queues:
	for (int i = 0; i < QUEUE_COUNT; i++)
		ndp_queue_stop(rxq[i]);
close_ndp_queues:
	for (int i = 0; i < QUEUE_COUNT; i++)
		ndp_close_rx_queue(rxq[i]);
close_nfb_comp:
	nfb_comp_close(comp);
close_nfb_dev:
	// Close the device
	nfb_close(dev);
close_files:
	for (int i = 0; i < QUEUE_COUNT; i++)
		fclose(fileptr_1[i]);

	return ret;
}
