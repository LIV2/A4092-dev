`timescale 1ns / 1ps

module A4092(
    input [31:0] ADDR,   // Only bits [8:0], 17,18,19, and 23-31 are used
    input CLK_50M,
    output AS_n,
    input PLD_DS_n,
    output [3:0] DS_n,
    input IORST,
    input [2:0] FC,
    input Z_7M,
    input FCS_n,
    output DOE,
    input READ,
    input [1:0] SIZ,
    input NACK,
    output INT_n,
    output MTCR_n,
    output SID_n,
    input [31:0] D, // Only [8:0] and [31:24] are used
    output CLK,
    input BMASTER,
    output DBLT,
    output DBOE_n,
    output ABOEL_n,
    output ABOEH_n,
    output D2Z_n,
    output Z2D_n,
    input MASTER,
    input SLACK,
    input NCR_INT,
    input SREG,
    output STERM_n,
    input ROM_OE,
    input SBR,
    input SBG,
    output CBACK_n,
    input CBREQ,
    input BERR_n,
    input BGn,
    input BRn,
    input Z_FCS,
    input LOCK,
    inout DTACK_n,
    output MTACK_n,
    output INT2_n,
    input CFGIN_n,
    output CFGOUT_n,
    output SLAVE_n,
    input SENSEZ3,
    output CINH_n
    );

Autoconfig AUTOCONFIG (
  .AS_n (AS_n),
  .RESET_n (IORST),
  .cfgout (CFGOUT_n)
);

SCSI SCSI (
  .CLK (CLK_50M),
  .RESET_n (IORST),
  .DTACK (DTACK_n)
);

endmodule
