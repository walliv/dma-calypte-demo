// Copyright 2024 Universitaet Heidelberg, Institut fuer Technische Informatik (ZITI)
// SPDX-License-Identifier: Apache-2.0

/* This program provides and example to how transmit data from a host to
   the H2F controller inside and FPGA.

   Compilation
	Prerequisities: You have a nfb-framework package installed on your
	machine.

	gcc pkt_transmit.c -o pkt_transmit.o -lnfb
        */

#include <stdio.h>
#include <err.h>

// Necessary header files
#include <nfb/nfb.h>
#include <nfb/ndp.h>

#define NDP_PACKET_COUNT 64
#define QUEUE_COUNT 4

int main(int argc, char *argv[])
{
	int ret = -1;
	struct nfb_device *dev;
	struct ndp_queue *txq[QUEUE_COUNT];
	struct ndp_packet pkts[NDP_PACKET_COUNT];

	/* =====================================================
	  Initialization
	 ==================================================== */
	/* Get handle to NFB device for futher operation */
	if ((dev = nfb_open("0")) == NULL)
		errx(1, "Can't open device file");

	/* Open H2F queues for data transmit */
	for (int i = 0; i < QUEUE_COUNT; i++) {
		txq[i] = ndp_open_tx_queue(dev, i);
		if (txq[i] == NULL) {
			fprintf(stderr, "Can't open queue %d\n", i);
		        goto close_nfb_dev;
		}
	}

	/* Start H2F queues */
	for (int i = 0; i < QUEUE_COUNT; i++) {
		ret = ndp_queue_start(txq[i]);
		if (ret != 0) {
			fprintf(stderr, "Unable to start queue %d\n", i);
		        goto close_ndp_queues;
		}
	}

	/* =====================================================
	 Data send
	 ==================================================== */
	for (int i = 0; i < NDP_PACKET_COUNT; i++) {
		/* Specify length of each packet within the pkts structure.
		  This length is in bytes. */
		pkts[i].data_length = 64;
		// TODO: Specify the length of packet metadata. Set to 0 for
		// this time.
		pkts[i].header_length = 0;
	}

	// Send sequentially over all queues. The parallel send on multiple
	// queues is also possible.
	for (int i = 0; i < QUEUE_COUNT; i++) {

	        /* Request placeholders for packets in the specific queue. This
		  will validate the pointers inside each packet in pkts array.
		  */
		ret = ndp_tx_burst_get(txq[i], pkts, NDP_PACKET_COUNT);
		if (ret != NDP_PACKET_COUNT)
			warnx("Requested %d packet placeholders to send, got %d", NDP_PACKET_COUNT, ret);

		/* After a successfull return (greater than 0) from the
		   ndp_tx_burst_get function, the pointer to data inside
		   each packet in pkts structure is validated and can be now
		   used to write data to it. */
		for (int j = 0; j < ret; j++) {
		        // Here are some examples of how the data can be filled.
		        // The "data" pointer inside the ndp_packet structure is
		        // of type unsigned char."

			/* Fill data space with some values */
			memset(pkts[j].data, 0, pkts[j].data_length);
			/* Pretend IPv4*/
			pkts[j].data[13] = 0x08;
		}

		/* Request to sent the data to the H2F controller. Unless the
		ndp_tx_burst_put function is called, the packets are not send.
		Always check to follow the call of ndp_tx_burst_get with
		ndp_tx_burst_put. */
		ndp_tx_burst_put(txq[i]);
	}

	// Because everything ran smoothly, return the ret variable to the
	// neutral value.
	ret = 0;

	/* ====================================================
	  Cleanup
	 =================================================== */
stop_ndp_queues:
	for (int i = 0; i < QUEUE_COUNT; i++)
		ndp_queue_stop(txq[i]);

close_ndp_queues:
	for (int i = 0; i < QUEUE_COUNT; i++)
		ndp_close_tx_queue(txq[i]);

close_nfb_dev:
	// Close the device
	nfb_close(dev);

	return ret;
}
