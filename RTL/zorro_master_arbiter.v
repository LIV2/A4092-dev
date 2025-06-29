`timescale 1ns / 1ps

//
// MODULE: zorro_master_arbiter
// DESCRIPTION:
// Implementation of the Zorro III bus arbiter from U303.
//
module zorro_master_arbiter (
    // --- Inputs ---
    input wire CLK,     // This should be the 7MHz arbitration clock (Z_7M)
    input wire RESET_n,
    input wire FCS,     // Zorro FCS
    input wire EBG_n,   // Zorro Bus Grant (active low)
    input wire SBR_n,   // SCSI Bus Request (active low)
    input wire MASTER,  // SCSI chip is local master (active high, inverted from MASTER_n)

    // --- Outputs ---
    output wire MYBUS_n, // A4091 owns the Zorro bus (active low)
    output wire SBG_n,   // SCSI Bus Grant (active low)
    output wire BMASTER, // Buffered MASTER signal
    output wire EBR_n   // Zorro Bus Request (active low)
);

    // Internal state from U303
    reg reged;          // Latches that we are registered as a Z3 master
    reg ebr;            // The registered bus request signal
    reg rchng;          // A change in registration is required
    reg ssbr;           // Synchronized SCSI Bus Request
    reg mybus;          // Internal, active-high version of MYBUS

    assign BMASTER = MASTER;
    assign EBR_n = ~ebr;
    assign MYBUS_n = ~mybus;

    // SCSI Bus Grant logic from u303.pld
    assign SBG_n = !( (~FCS && SBR_n && ~EBG_n) || (SBG_n && SBR_n) || (SBG_n && MASTER) );

    always @(posedge CLK or negedge RESET_n) begin
        if (!RESET_n) begin
            reged   <= 1'b0;
            ebr     <= 1'b0;
            rchng   <= 1'b0;
            ssbr    <= 1'b0;
            mybus   <= 1'b0;
        end else begin
            // Synchronize the SCSI Bus Request
            ssbr <= ~SBR_n;

            // RCHNG: A change of registration is necessary
            rchng <= (~reged && ssbr && ~ebr) || (reged && ~MASTER && ~ebr);

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
        end
    end
endmodule
