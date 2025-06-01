`timescale 1ns / 1ps

module zorro_master_arbiter (
    input wire CLK,
    input wire RESET_n,
    input wire FCS,
    input wire DTACK,
    input wire RST,
    input wire EBG_n,
    input wire SBR_n,
    input wire MASTER,

    output wire SBG_n,
    output wire BMASTER,
    output wire EBR_n
);

// Internal state
reg blockbg;
reg reged;
reg ebr;
reg smaster;
reg dmaster;
reg ssbr;
reg rchng;

assign BMASTER = MASTER;

// Internal EBG logic
wire ebg = ~MASTER && ~reged && ~SBR_n;

assign SBG_n = !((~FCS && ~DTACK && ~RST && ~SBR_n && ~ebg && !blockbg) ||
                 (~SBR_n && reged && ~RST && !blockbg) ||
                 (~MASTER && reged && ~RST && !blockbg));

always @(posedge CLK or negedge RESET_n) begin
    if (!RESET_n) begin
        reged <= 0;
        ebr <= 0;
        blockbg <= 0;
        smaster <= 0;
        dmaster <= 0;
        ssbr <= 0;
        rchng <= 0;
    end else begin
        // Synchronizers
        smaster <= MASTER;
        dmaster <= smaster;
        ssbr <= ~SBR_n;

        // BLOCKBG logic
        blockbg <= MASTER || (blockbg && reged) || (blockbg && ~ebg);

        // Registration change condition
        rchng <= (~reged && ssbr && ~ebr) || (reged && ~smaster && ~ebr && dmaster);

        // Toggle EBR when a change is needed
        if (rchng && ~ebr && ~RST)
            ebr <= 1;
        else
            ebr <= 0;

        // Toggle REGED on EBR
        if (~RST) begin
            if (~reged && ebr)
                reged <= 1;
            else if (reged && ~ebr)
                reged <= 0;
        end else begin
            reged <= 0;
        end
    end
end

endmodule

