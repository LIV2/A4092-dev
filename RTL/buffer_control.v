`timescale 1ns / 1ps

//
// MODULE: buffer_control
// DESCRIPTION:
// Buffer control logic based on A4091 GAL U205
//

module buffer_control (
    input wire CLK,
    input wire RESET_n,

    // --- Control Signals ---
    input wire READ,
    input wire FCS_n,
    input wire DOE,
    input wire DTACK_n,

    // --- Master/Slave Cycle Controls ---
    input wire MYBUS,       // A4091 owns the Zorro bus (active high)
    input wire MASTER_n,    // SCSI chip is local master (active low)
    input wire SLAVE_n,     // Board is selected as a slave (active low)

    // --- Outputs to Transceivers ---
    output reg DBOE_n,
    output reg ABOEL_n,
    output reg ABOEH_n,
    output reg D2Z_n,
    output reg Z2D_n,
    output reg DBLT
);

    // --- CORRECT cycle definitions based on u205.pld ---
    wire master_cycle =  MYBUS && !MASTER_n;
    wire slave_cycle  = !MYBUS &&  MASTER_n;

    // Logic from u205.pld, qualified by correct cycle types
    wire dboe_logic = (slave_cycle  && !SLAVE_n && !READ && !FCS_n) |   // Slave Write
                      (slave_cycle  && !SLAVE_n &&  READ && !FCS_n &&  DOE) |    // Slave Read
                      (master_cycle &&  SLAVE_n && !READ && !FCS_n &&  DOE) |    // Master Write
                      (master_cycle &&  SLAVE_n &&  READ && !FCS_n);           // Master Read

    wire d2z_logic  = (slave_cycle  &&  READ && !FCS_n && !SLAVE_n) |   // Slave Read -> Data to Zorro
                      (master_cycle && !READ && !FCS_n &&  SLAVE_n);     // Master Write -> Data to Zorro

    wire z2d_logic  = (slave_cycle  && !READ && !FCS_n && !SLAVE_n) |   // Slave Write -> Zorro to Data
                      (master_cycle &&  READ && !FCS_n &&  SLAVE_n);     // Master Read -> Zorro to Data

    wire dblt_latch = ((slave_cycle && !SLAVE_n) || (master_cycle && SLAVE_n)) &&
                      !FCS_n && !DTACK_n && DOE;

    always @(posedge CLK or negedge RESET_n) begin
        if (!RESET_n) begin
            DBOE_n  <= 1'b1;
            ABOEL_n <= 1'b1;
            ABOEH_n <= 1'b1;
            D2Z_n   <= 1'b1;
            Z2D_n   <= 1'b1;
            DBLT    <= 1'b0;
        end else begin
            // Buffers are disabled unless a valid master or slave cycle is active
            DBOE_n <= !dboe_logic;
            D2Z_n  <= !d2z_logic;
            Z2D_n  <= !z2d_logic;

            // Address Buffers
            if (slave_cycle) begin
                ABOEL_n <= 1'b0; // Enabled
                ABOEH_n <= 1'b0; // Enabled
            end else if (master_cycle) begin
                // ABOEH goes high (disabled) after FCS asserts
                if (!FCS_n) begin
                    ABOEH_n <= 1'b1;
                end else begin
                    ABOEH_n <= 1'b0;
                end
                // ABOEL remains enabled throughout the master cycle
                ABOEL_n <= 1'b0;
            end else begin
                // During arbitration or idle states, address buffers are enabled
                // to allow the host to see the address space.
                ABOEL_n <= 1'b0;
                ABOEH_n <= 1'b0;
            end

            // Data Latch
            if (dblt_latch) begin
                DBLT <= 1'b1;
            end else if (FCS_n) begin
                DBLT <= 1'b0;
            end
        end
    end
endmodule
