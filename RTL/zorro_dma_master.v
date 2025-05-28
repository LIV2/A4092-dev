`timescale 1ns / 1ps

// Combined DMA FSM for Zorro III Master cycles driven by NCR53C710
// Replaces U202 GAL in A4091, supports both DMA read and write

module zorro_dma_master (
    input wire CLK,
    input wire RESET_n,
    input wire START_DMA,
    input wire READ,              // 1 = DMA read from Zorro (to NCR), 0 = DMA write to Zorro (from NCR)
    input wire [31:0] ADDR,
    output reg [2:0] FC,
    output reg [1:0] SIZ,
    output reg AS_n,
    output reg [3:0] DS_n,
    output reg DTACK_ACK,        // Signal to NCR that DMA cycle finished
    input wire DTACK_n,
    output reg BRn,
    input wire BGn,
    output reg ACTIVE            // High when FSM is in active transfer
    // No DATA bus connection!
);

localparam [3:0]
    IDLE         = 4'd0,
    REQUEST_BUS  = 4'd1,
    WAIT_FOR_BG  = 4'd2,
    SETUP_CYCLE  = 4'd3,
    ASSERT_SIGS  = 4'd4,
    WAIT_DTACK   = 4'd5,
    END_CYCLE    = 4'd6,
    RELEASE_BUS  = 4'd7;

reg [3:0] state, next_state;
reg [31:0] addr_latch;

// DS_n generation example:
// This is minimal and should match your Zorro/68030 bus spec for SCSI cycles
always @(*) begin
    DS_n = 4'b1111;
    if (state == ASSERT_SIGS) begin
        // Example: DS3 is asserted for every transfer
        DS_n = 4'b1110;
        // Optionally use more sophisticated logic here
    end
end

always @(posedge CLK or negedge RESET_n) begin
    if (!RESET_n) begin
        state <= IDLE;
        addr_latch <= 32'h0;
    end else begin
        state <= next_state;
        if (state == SETUP_CYCLE) begin
            addr_latch <= ADDR;
        end
    end
end

always @(*) begin
    next_state = state;
    BRn = 1;
    AS_n = 1;
    FC = 3'b001;     // For data cycles (adjust as needed)
    SIZ = 2'b10;     // 32-bit, adjust if needed
    DTACK_ACK = 0;
    ACTIVE = 1'b1;

    case (state)
        IDLE: begin
            ACTIVE = 0;
            if (START_DMA)
                next_state = REQUEST_BUS;
        end

        REQUEST_BUS: begin
            BRn = 0;
            if (!BGn)
                next_state = WAIT_FOR_BG;
        end

        WAIT_FOR_BG: begin
            BRn = 0;
            next_state = SETUP_CYCLE;
        end

        SETUP_CYCLE: begin
            // Latch addr, prep other signals
            next_state = ASSERT_SIGS;
        end

        ASSERT_SIGS: begin
            AS_n = 0;
            // Set up DS_n, FC, SIZ as appropriate
            next_state = WAIT_DTACK;
        end

        WAIT_DTACK: begin
            AS_n = 0;
            if (!DTACK_n)
                next_state = END_CYCLE;
        end

        END_CYCLE: begin
            DTACK_ACK = 1;
            next_state = RELEASE_BUS;
        end

        RELEASE_BUS: begin
            next_state = IDLE;
        end

        default: next_state = IDLE;
    endcase
end

endmodule

