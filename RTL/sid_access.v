`timescale 1ns / 1ps

module sid_access (
    input wire CLK,
    input wire RESET_n,
    input wire idreg_region,

    input wire READ,
`ifndef USE_DIP_SWITCH
    input wire [7:0] DIN,
    output reg [7:0] DOUT,
    output wire dip_ext_term,
`endif
    input wire FCS_n,
    input wire slave_cycle,
    input wire configured,

    output reg sid_dtack,
    output wire SID_n
);

// SID is located at 0x8C0000-0x8FFFFF within the 16MB Z3 BAR
assign SID_n = !(
    idreg_region
`ifdef USE_DIP_SWITCH
    && READ
`endif
);

// SID DTACK logic: one-cycle delay when selected
reg [1:0] sid_state;

`ifndef USE_DIP_SWITCH
// One-byte DIP shadow register
reg [7:0] dip_shadow;

assign dip_ext_term = dip_shadow[0];
`endif

always @(posedge CLK or negedge RESET_n) begin
    if (!RESET_n) begin
        sid_state <= 2'd0;
        sid_dtack <= 0;
`ifndef USE_DIP_SWITCH
	DOUT <= 8'hFF;
	dip_shadow <= 8'h00;
`endif
    end else begin
        case (sid_state)
            2'd0: begin
                sid_dtack <= 0;
                if (!SID_n && !FCS_n)
                    sid_state <= 2'd1;
            end
            2'd1: begin
                sid_dtack <= 1;
`ifdef USE_DIP_SWITCH
                if (FCS_n)
                    sid_state <= 2'd0;
`else
		sid_state <= 2'd2;

                if (READ)
                    DOUT <= dip_shadow;
                else
                    dip_shadow <= DIN;
`endif
            end
`ifndef USE_DIP_SWITCH
	    2'd2: begin
                if (FCS_n) begin
                    sid_dtack <= 0;
                    sid_state <= 0;
                end
            end
`endif
        endcase
    end
end

endmodule

