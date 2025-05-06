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
    output reg INT_n
);

// INTREG is at 0x900000 within the Z3 BAR
wire intreg_match = slave_cycle && configured && (ADDR[27:1] == 27'h900000 >> 1);

reg int_pending;

always @(posedge CLK or negedge RESET_n) begin
    if (!RESET_n) begin
        int_pending <= 0;
        int_dtack <= 0;
        INT_n <= 1;
    end else begin
        // latch interrupt edge from NCR
        if (NCR_INT)
            int_pending <= 1;

        // clear on read to INTREG
        if (!FCS_n && READ && intreg_match)
            int_pending <= 0;

        // output level for INT_n (active low)
        INT_n <= ~int_pending;

        // dtack: one-cycle delay on INTREG read
        case (int_dtack)
            1'b0:
                if (!FCS_n && READ && intreg_match)
                    int_dtack <= 1;
            1'b1:
                if (FCS_n)
                    int_dtack <= 0;
        endcase
    end
end

endmodule

