/*
Copyright 2022 Matthew Harlum

Licensed under
Creative Commons Attribution-ShareAlike 4.0 International License.

You should have received a copy of the license along with this
work. If not, see <http://creativecommons.org/licenses/by-sa/4.0/>.
*/

module Autoconfig (
    input autoconfig_cycle,
    input [6:0] ADDRL,
    input FCS_n,
    input CLK,
    input READ,
    input [7:0] DIN,
    input RESET_n,
    output reg [7:0] scsi_base_addr,
    output reg CFGOUT_n,
    output reg dtack,
    output reg configured,
    output reg shutup,
    output reg [3:0] DOUT
);

localparam  Z3_IDLE  = 2'd0,
            Z3_START = 2'd1,
            Z3_DATA  = 2'd2,
            Z3_END   = 2'd3;

`ifndef makedefines
`define SERIAL 32'd0
`endif

localparam [15:0] mfg_id  = 16'd514; // Open Amiga hardware registry ID https://github.com/oahr/oahr
localparam [7:0]  prod_id = 8'd84;
localparam [31:0] serial  = `SERIAL;

// Register Config in/out at end of bus cycle
always @(posedge FCS_n or negedge RESET_n)
begin
  if (!RESET_n) begin
    CFGOUT_n <= 1'b1;
  end else begin
    CFGOUT_n <= !configured && !shutup;
  end
end

always @(posedge CLK or negedge RESET_n)
begin
  if (!RESET_n) begin
    DOUT[3:0]          <= 4'b0;
    configured         <= 1'b0;
    dtack              <= 1'b0;
    shutup             <= 1'b0;
    scsi_base_addr[3:0] <= 4'b0000;
  end else if (autoconfig_cycle == 1) begin
    dtack <= 1;
    if (READ) begin
      case ({ADDRL[5:0],ADDRL[6]})
//      7'h00:   DOUT[3:0] <= 4'b1001;        // Type: Zorro III // disable Autoboot until card is working...
        7'h00:   DOUT[3:0] <= 4'b1000;        // Type: Zorro III
        7'h01:   DOUT[3:0] <= 4'b0000;        // 16 MB
        7'h02:   DOUT[3:0] <= ~prod_id[7:4];  // Product number
        7'h03:   DOUT[3:0] <= ~prod_id[3:0];  // Product number
        7'h04:   DOUT[3:0] <= ~4'b0011;       // IO device, Size Extension, Zorro III
        7'h05:   DOUT[3:0] <= ~4'b0000;       // Logical size matches physical size
        7'h08:   DOUT[3:0] <= ~mfg_id[15:12]; // Manufacturer ID
        7'h09:   DOUT[3:0] <= ~mfg_id[11:8];  // Manufacturer ID
        7'h0A:   DOUT[3:0] <= ~mfg_id[7:4];   // Manufacturer ID
        7'h0B:   DOUT[3:0] <= ~mfg_id[3:0];   // Manufacturer ID
        7'h0C:   DOUT[3:0] <= ~serial[31:28]; // Serial number
        7'h0D:   DOUT[3:0] <= ~serial[27:24]; // Serial number
        7'h0E:   DOUT[3:0] <= ~serial[23:20]; // Serial number
        7'h0F:   DOUT[3:0] <= ~serial[19:16]; // Serial number
        7'h10:   DOUT[3:0] <= ~serial[15:12]; // Serial number
        7'h11:   DOUT[3:0] <= ~serial[11:8];  // Serial number
        7'h12:   DOUT[3:0] <= ~serial[7:4];   // Serial number
        7'h13:   DOUT[3:0] <= ~serial[3:0];   // Serial number
        7'h14:   DOUT[3:0] <= ~4'b0000;       // ROM vector
        7'h15:   DOUT[3:0] <= ~4'b0010;       // ROM vector
        7'h16:   DOUT[3:0] <= ~4'b0000;       // ROM vector
        7'h17:   DOUT[3:0] <= ~4'b0000;       // ROM vector
        7'h20:   DOUT[3:0] <= 4'h0;
        7'h21:   DOUT[3:0] <= 4'h0;
        default: DOUT[3:0] <= 4'hF;
      endcase
    end else begin
      if (ADDRL[5:0] == 6'h13) begin
        // Shutup
        shutup <= 1;
      end else if (ADDRL[5:0] == 6'h11) begin
        // Write base address
        scsi_base_addr <= DIN[7:0];
        configured    <= 1;
      end
    end
  end else begin
    dtack <= 0;
  end
end

endmodule
