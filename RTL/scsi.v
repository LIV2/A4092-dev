`timescale 1ns / 1ps

module SCSI(
    input CLK,
    input RESET_n,
    output reg DTACK
    );

always @(posedge CLK or negedge RESET_n) begin
  if (!RESET_n) begin
    DTACK <= 0;
  end else begin
    DTACK <= 1;
  end
end

endmodule
