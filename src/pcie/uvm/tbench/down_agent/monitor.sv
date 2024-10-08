//-- monitor.sv
//-- Copyright (C) 2023 CESNET z. s. p. o.
//-- Author(s): Daniel Kriz <danielkriz@cesnet.cz>

//-- SPDX-License-Identifier: BSD-3-Clause

class monitor extends uvm_monitor;
    `uvm_component_utils(uvm_down_hdr::monitor)

    // Used to send transactions to all connected components.
    uvm_analysis_port #(sequence_item) analysis_port;

    sequence_item item;

    // Creates new instance of this class.
    function new (string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // Instantiates child components.
    function void build_phase(uvm_phase phase);
        analysis_port = new("analysis port", this);
        item          = sequence_item::type_id::create("item");
    endfunction

endclass

