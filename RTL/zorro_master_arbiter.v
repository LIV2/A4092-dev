`timescale 1ns / 1ps

//
// MODULE: zorro_master_arbiter
// DESCRIPTION:
// Implementation of the Zorro III bus arbiter from U303.
//
module zorro_master_arbiter (
    // --- Inputs ---
    input wire C7M,      // This should be the 7MHz arbitration clock (Z_7M)
    input wire RESET_n,
    input wire MASTER_n, // SCSI chip is local master (active high, inverted from MASTER_n)
    input wire SBR_n,    // SCSI Bus Request (active low)
    input wire EBG_n,    // Zorro Bus Grant (active low)
    input wire FCS,      // Zorro FCS
    input wire DTACK_n,

    // --- Outputs ---
    output wire MYBUS_n, // A4091 owns the Zorro bus (active low)
    output wire SBG_n,   // SCSI Bus Grant (active low)
    output wire EBR_n,   // Zorro Bus Request (active low)
    output wire BMASTER  // Buffered MASTER signal
);

    // Internal state from U303
    reg reged;          // Latches that we are registered as a Z3 master
    reg ebr;            // The registered bus request signal
    reg rchng;          // A change in registration is required
    reg ssbr;           // Synchronized SCSI Bus Request
    reg mybus;          // Internal, active-high version of MYBUS
    reg blockbg;        // after 1st sbg must block any further till unregistered and ebg deasserts
    reg sbg_reg;        // A register to hold the state of SBG_n

    reg smaster;
    reg dmaster;

    // wires for combinational logic
    wire sbg_next;
    wire blockbg_next;

    // SCSI Bus Grant logic from u303.pld
    // Describe the NEXT state using purely combinational logic
    assign blockbg_next = ~MASTER_n || (blockbg && reged) || (blockbg && ~EBG_n);

    assign sbg_next = ( (~FCS && DTACK_n && ~SBR_n && ~EBG_n && ~blockbg_next) ||
                        (sbg_reg && ~SBR_n && ~blockbg_next) ||
                        (sbg_reg && MASTER_n && ~blockbg_next) ) && RESET_n;


    assign MYBUS_n = ~mybus;
    assign SBG_n = ~sbg_reg;
    assign EBR_n = ~ebr;
    assign BMASTER = ~MASTER_n;

 //   assign sbg_reg = ( (~FCS && DTACK_n && RESET_n && ~SBR_n && ~EBG_n && ~blockbg) ||
 //                      (sbg_reg && ~SBR_n && RESET_n && ~blockbg) ||
	//	       (sbg_reg && MASTER_n && RESET_n && ~blockbg) );

//    assign blockbg = ~MASTER_n || (blockbg && reged) || (blockbg && ~EBG_n);

    always @(posedge C7M or negedge RESET_n) begin
        if (!RESET_n) begin
            reged   <= 1'b0;
            ebr     <= 1'b0;
            rchng   <= 1'b0;
            ssbr    <= 1'b0;
            mybus   <= 1'b0;
	    smaster <= 1'b0;
            dmaster <= 1'b0;
	    sbg_reg <= 1'b0;
	    blockbg <= 1'b0;
        end else begin
            smaster <= ~MASTER_n;
            dmaster <= smaster;

            // Synchronize the SCSI Bus Request
            ssbr <= ~SBR_n;

            // RCHNG: A change of registration is necessary
	    rchng <= (~reged && ssbr && ~ebr) || (reged && ~smaster && ~ebr && dmaster);

            // EBR: Zorro Bus Request is toggled to register/unregister
            if (rchng && ~ebr)
                ebr <= 1'b1;
            else
                ebr <= 1'b0;

            // REGED: The actual registration indicator
            if (~reged && ebr)
                reged <= 1'b1;
            else if (reged && ~ebr)
                reged <= 1'b0;

            // MYBUS: We own the bus when registered and granted
            if (reged && ~EBG_n)
                mybus <= 1'b1;
            else if (!FCS) // Hold the bus until the cycle completes
                mybus <= mybus;
            else
                mybus <= 1'b0;

	    // Update the registers with their next state on the clock edge
            sbg_reg <= sbg_next;
            blockbg <= blockbg_next;
        end
    end
endmodule
