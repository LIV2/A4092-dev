`timescale 1ns / 1ps

//
// MODULE: scsi_slave
// DESCRIPTION: U304
//

module scsi_slave (
    input wire CLK,
    input wire CLKI,
    input wire IORST_n,
    input wire SCSI_n,
    input wire READ,
    input wire [3:0] DS_n,
    input wire DOE,
    input wire DTACK_n,
    input wire STERM_n,
    input wire MYBUS_n,
    input wire A2, // FIXME
    input wire scsi_cycle,
    input wire slave_cycle,

    // --- Outputs
    output wire SCSI_SREG_n,
    output wire SCSI_DS_n,
    output wire SCSI_AS_n,
    output wire [1:0] SIZ,
    output wire [1:0] ADDRL
);

// --- SCSI Slave Interface (replaces U304) --- 
reg ssync_n; 
reg as_latch_n; 
reg ds_latch_n; 
reg sreg_latch_n; 
  
// This block generates the necessary strobes and sizing signals for the 
// NCR 53C710 when the CPU is accessing it (slave mode). 
always @(posedge CLKI or negedge IORST_n) begin 
    if (!IORST_n) begin 
        ssync_n <= 1'b1; 
        as_latch_n <= 1'b1; 
        ds_latch_n <= 1'b1; 
        sreg_latch_n <= 1'b1; 
    end else begin 
        // Synchronize start of SCSI cycle 
        ssync_n <= !(scsi_cycle && DOE && (|DS_n != 4'b1111) && slave_cycle); 
        // Generate Address Strobe 
        as_latch_n <= ssync_n; 
        // Generate Data Strobe 
        ds_latch_n <= !(!ssync_n & READ) && !(as_latch_n & !READ); 
        // Generate Register Select 
        sreg_latch_n <= !(!as_latch_n & CLK) && !(!as_latch_n & !sreg_latch_n); 
    end 
end 

assign SCSI_AS_n = as_latch_n; 
assign SCSI_DS_n = !scsi_cycle ? 1'b1 : ds_latch_n; 
assign SCSI_SREG_n = sreg_latch_n; 

// DOE is driven active during master-mode writes.


endmodule
