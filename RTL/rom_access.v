module rom_access (
    input wire CLK,
    input wire RESET_n,
    input wire [23:17] ADDR,
    input wire READ,
    input wire FCS_n,
    input wire slave_cycle,
    input wire configured,
    input wire shutup,

    output reg rom_dtack,
    output wire rom_selected,
    output wire ROM_CE_n,
    output wire ROM_OE_n,
    output wire ROM_WE_n
);

    // Match ROM space (0x000000 - 0x7FFFFF)
    assign rom_selected = slave_cycle && (ADDR[23:17] < 8'h40);

    // Control ROM chip selects
    assign ROM_CE_n = !(rom_selected && !shutup);
    assign ROM_OE_n = !(rom_selected && READ && !FCS_n && !shutup);
    assign ROM_WE_n = !(rom_selected && !READ && !FCS_n && configured && !shutup);

    // NACK timing FSM (3 state delay like U207)
    reg [1:0] rom_state;

    always @(posedge CLK or negedge RESET_n) begin
        if (!RESET_n) begin
            rom_state  <= 2'd0;
            rom_dtack  <= 1'b0;
        end else begin
            case (rom_state)
                2'd0: begin
                    rom_dtack <= 0;
                    if (rom_selected && !FCS_n)
                        rom_state <= 2'd1;
                end
                2'd1: rom_state <= 2'd2;
                2'd2: begin
                    rom_dtack <= 1;
                    if (FCS_n)
                        rom_state <= 2'd0;
                end
                default: rom_state <= 2'd0;
            endcase
        end
    end

endmodule
