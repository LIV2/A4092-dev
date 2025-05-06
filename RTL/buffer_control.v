`timescale 1ns / 1ps

module buffer_control (
    input wire CLK,
    input wire RESET_n,
    input wire READ,
    input wire slave_cycle,
    input wire configured,
    input wire BMASTER,
    input wire MASTER,
    input wire [27:0] ADDR,
    input wire FCS_n,

    output reg DBOE_n,
    output reg ABOEL_n,
    output reg ABOEH_n,
    output reg D2Z_n,
    output reg Z2D_n
);

// From GAL U205/U206 behavior:
// Buffer enable depends on bus direction and control timing

wire scsi_region = configured && slave_cycle && (ADDR[27:23] >= 5'h08 && ADDR[27:23] < 5'h48);

always @(posedge CLK or negedge RESET_n) begin
    if (!RESET_n) begin
        DBOE_n <= 1;
        ABOEL_n <= 1;
        ABOEH_n <= 1;
        D2Z_n <= 1;
        Z2D_n <= 1;
    end else begin
        // Drive direction for external data buffers:
        // NCR → Zorro = READ from SCSI region (NCR drives bus)
        // Zorro → NCR = WRITE to SCSI region (Zorro drives bus)

        if (scsi_region && !FCS_n) begin
            // Address buffer enables (both banks)
            ABOEL_n <= 0;
            ABOEH_n <= 0;

            if (READ) begin
                // NCR → Zorro
                DBOE_n <= 0;
                D2Z_n <= 0;
                Z2D_n <= 1;
            end else begin
                // Zorro → NCR
                DBOE_n <= 1;
                D2Z_n <= 1;
                Z2D_n <= 0;
            end
        end else begin
            // Default inactive state
            DBOE_n <= 1;
            ABOEL_n <= 1;
            ABOEH_n <= 1;
            D2Z_n <= 1;
            Z2D_n <= 1;
        end
    end
end

endmodule
