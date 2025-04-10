module Autoconfig (
    input AS_n,
    input RESET_n,
    output reg cfgout
);

always @(posedge AS_n or negedge RESET_n) begin
  if (!RESET_n) begin
    cfgout <= 0;
  end else begin
    cfgout <= 1;
  end
end

endmodule
