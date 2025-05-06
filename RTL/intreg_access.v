`timescale 1ns / 1ps

module intreg_access (
    input wire CLK,
    input wire RESET_n,
    input wire [27:0] ADDR,
    input wire READ,
    input wire FCS_n,
    input wire slave_cycle,
    input wire configured,
    input wire NCR_INT,

    output reg int_dtack,
    output reg INT_n,
    output reg [3:0] DOUT
);

// INTREG = 0x900000, INTVEC = 0x900004
wire match_intreg = slave_cycle && configured && (ADDR[27:1] == (28'h900000 >> 1));
wire match_intvec = slave_cycle && configured && (ADDR[27:1] == (28'h900004 >> 1));

reg int_pending;

always @(posedge CLK or negedge RESET_n) begin
    if (!RESET_n) begin
        int_pending <= 0;
        int_dtack <= 0;
        INT_n <= 1;
        DOUT <= 4'hF;
    end else begin
        // latch interrupt edge from NCR
        if (NCR_INT)
            int_pending <= 1;

        // clear on read to INTREG
        if (!FCS_n && READ && match_intreg)
            int_pending <= 0;

        // drive INT_n low if interrupt is pending
        INT_n <= ~int_pending;

        // data output for readback
        if (!FCS_n && READ) begin
            if (match_intvec)
                DOUT <= 4'h1; // INTVEC = 0x18 → DOUT = 0x1 (upper nibble)
            else
                DOUT <= 4'hF;
        end

        // dtack logic
        case (int_dtack)
            1'b0:
                if (!FCS_n && READ && (match_intreg || match_intvec))
                    int_dtack <= 1;
            1'b1:
                if (FCS_n)
                    int_dtack <= 0;
        endcase
    end
end

endmodule

