`timescale 1ns / 1ps

module sid_access (
    input wire CLK,
    input wire RESET_n,
    input wire [27:0] ADDR,
    input wire READ,
    input wire FCS_n,
    input wire slave_cycle,
    input wire configured,

    output reg sid_dtack,
    output wire SID_n
);

// SID is located at 0x8C0000-0x8FFFFF within the 16MB Z3 BAR
// Match A[27:18] == 0x23 (for 0x8C0000)
assign SID_n = !(
    slave_cycle &&
    configured &&
    READ &&
    (ADDR[27:18] == 10'b1000110000)
);

// SID DTACK logic: one-cycle delay when selected
reg [1:0] sid_state;

always @(posedge CLK or negedge RESET_n) begin
    if (!RESET_n) begin
        sid_state <= 2'd0;
        sid_dtack <= 0;
    end else begin
        case (sid_state)
            2'd0: begin
                sid_dtack <= 0;
                if (!SID_n && !FCS_n)
                    sid_state <= 2'd1;
            end
            2'd1: begin
                sid_dtack <= 1;
                if (FCS_n)
                    sid_state <= 2'd0;
            end
        endcase
    end
end

endmodule

