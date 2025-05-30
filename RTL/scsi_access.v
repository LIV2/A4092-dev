`timescale 1ns / 1ps

module scsi_access (
    input wire CLK,
    input wire RESET_n,
    input wire [23:17] ADDR,
    input wire READ,
    input wire FCS_n,
    input wire slave_cycle,
    input wire configured,

    output reg scsi_dtack
);

// SCSI region: everything from 0x800000 to 0x87FFFF (512KB)

wire scsi_region = slave_cycle && configured && (ADDR[23:17] >= 8'h40 && ADDR[23:17] < 8'h44);

reg [1:0] scsi_state;

always @(posedge CLK or negedge RESET_n) begin
    if (!RESET_n) begin
        scsi_state <= 0;
        scsi_dtack <= 0;
    end else begin
        case (scsi_state)
            2'd0: begin
                scsi_dtack <= 0;
                if (!FCS_n && scsi_region)
                    scsi_state <= 2'd1;
            end
            2'd1: scsi_state <= 2'd2;
            2'd2: begin
                scsi_dtack <= 1;
                if (FCS_n)
                    scsi_state <= 2'd0;
            end
        endcase
    end
end

endmodule

