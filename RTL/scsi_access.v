`timescale 1ns / 1ps

//
// MODULE: scsi_access
// DESCRIPTION:
// Handles access to the SCSI chip region.
// Generates scsi_dtack based on chip select and SLACK_n from the SCSI controller.
//
module scsi_access (
    input wire CLK,
    input wire RESET_n,
    input wire scsi_region,
    // input wire READ,          // READ is not used in this specific dtack generation logic
    input wire FCS_n,        // Zorro Full Cycle Strobe (active low)
    input wire slave_cycle,  // Indicates a Zorro slave cycle
    input wire configured,   // Indicates the card has been configured
    input wire SLACK_n,      // NEW: Acknowledge from the SCSI chip (active low)

    output reg scsi_dtack    // DTACK signal for the Zorro bus (active high for this module's output)
);

// State machine for DTACK generation
localparam IDLE         = 2'b00;
localparam WAIT_SLACK   = 2'b01;
localparam ASSERT_DTACK = 2'b10;

reg [1:0] scsi_state;

always @(posedge CLK or negedge RESET_n) begin
    if (!RESET_n) begin
        scsi_state <= IDLE;
        scsi_dtack <= 1'b0;
    end else begin
        case (scsi_state)
            IDLE: begin
                scsi_dtack <= 1'b0;
                if (!FCS_n && scsi_region) begin // Cycle starts for SCSI region
                    scsi_state <= WAIT_SLACK;
                end
            end

            WAIT_SLACK: begin
                scsi_dtack <= 1'b0; // Keep DTACK de-asserted
                if (FCS_n) begin // Cycle aborted or ended before SLACK
                    scsi_state <= IDLE;
                end else if (!SLACK_n) begin // SCSI chip is ready
                    scsi_state <= ASSERT_DTACK;
                end
                // Stay in WAIT_SLACK if SLACK_n is still high and cycle is active
            end

            ASSERT_DTACK: begin
                scsi_dtack <= 1'b1; // Assert DTACK
                if (FCS_n) begin   // Cycle ends
                    scsi_state <= IDLE;
                end
                // Stay in ASSERT_DTACK until FCS_n goes high
            end

            default: begin
                scsi_state <= IDLE;
                scsi_dtack <= 1'b0;
            end
        endcase
    end
end

endmodule
