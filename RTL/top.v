`timescale 1ns / 1ps

module A4092(
    input [31:0] A,   // Only bits [8:0], 17,18,19, and 23-31 are used
    input CLK_50M,
    output AS_n,
    input PLD_DS_n,
    output [3:0] DS_n,
    input IORST_n,
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
    output reg MASTER,
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

`include "globalparams.vh"

// Synchronizers
reg [1:0] DS0_n_sync;
reg [1:0] DS1_n_sync;
reg [1:0] DS2_n_sync;
reg [1:0] DS3_n_sync;
reg [1:0] FCS_n_sync;

always @(posedge CLK or negedge IORST_n)
begin
  if (!IORST_n) begin
    DS0_n_sync[1:0] <= 2'b11;
    DS1_n_sync[1:0] <= 2'b11;
    DS2_n_sync[1:0] <= 2'b11;
    DS3_n_sync[1:0] <= 2'b11;
    FCS_n_sync[1:0] <= 2'b11;
  end else begin
    DS0_n_sync[1:0] <= {DS0_n_sync[0], DS_n[0]};
    DS1_n_sync[1:0] <= {DS1_n_sync[0], DS_n[1]};
    DS2_n_sync[1:0] <= {DS2_n_sync[0], DS_n[2]};
    DS3_n_sync[1:0] <= {DS3_n_sync[0], DS_n[3]};
    FCS_n_sync[1:0] <= {FCS_n_sync[0], FCS_n};
  end
end

// Autoconf
wire [3:0] autoconfig_dout;
wire autoconfig_cfgout;

wire [3:0] scsi_base_addr;

reg [27:8] ADDR;
reg autoconfig_addr_match;
reg scsi_addr_match;

wire match = autoconfig_addr_match || scsi_addr_match;
wire configured;
wire validspace = FC[1] ^ FC[0]; // 1 when FC indicates user/supervisor data/program space
wire shutup;

// Latch address bits 27-8 on FCS_n asserted
// 
always @(negedge FCS_n or negedge IORST_n)
begin
  if (!IORST_n) begin
    ADDR                  <= 20'b0;
    scsi_addr_match        <= 0;
    autoconfig_addr_match <= 0;
  end else begin
    MASTER <= READ; // CEAB for address bits
    ADDR[27:8] <= A[27:8];

    if (A[31:28] == scsi_base_addr && configured) begin
      scsi_addr_match <= 1;
    end else begin
      scsi_addr_match <= 0;
    end

    if ({A[31:24]} == 8'hFF && !configured && !shutup && !CFGIN_n) begin
      autoconfig_addr_match <= 1;
    end else begin
      autoconfig_addr_match <= 0;
    end
  end
end

reg [1:0] z3_state;
reg dtack;
reg scsi_cycle;
reg autoconfig_cycle;
wire autoconfig_dtack;
wire scsi_dtack;

always @(posedge CLK or negedge IORST_n)
begin
  if (!IORST_n) begin
    z3_state         <= Z3_IDLE;
    dtack            <= 1'b0;
    scsi_cycle        <= 1'b0;
    autoconfig_cycle <= 1'b0;
  end else begin
    case (z3_state)
      Z3_IDLE:
        begin
          dtack <= 0;
          if (!FCS_n_sync[1] && match && validspace) begin
            z3_state         <= Z3_START;
            autoconfig_cycle <= autoconfig_addr_match;
            scsi_cycle        <= scsi_addr_match;
          end else begin
            autoconfig_cycle <= 0;
            scsi_cycle        <= 0;
            z3_state         <= Z3_IDLE;
          end
        end
      Z3_START:
        begin
          if (FCS_n_sync[1]) begin
            z3_state <= Z3_IDLE;
          end else if (READ || (!DS0_n_sync[1] || !DS1_n_sync[1] || !DS2_n_sync[1] || !DS3_n_sync[1]) && DOE) begin
            z3_state <= Z3_DATA;
          end else begin
            z3_state <= Z3_START;
          end
        end
      Z3_DATA:
        begin
          if (FCS_n_sync[1]) begin
            z3_state <= Z3_IDLE;
          end else if (autoconfig_dtack && autoconfig_cycle || scsi_dtack && scsi_cycle) begin
            z3_state <= Z3_END;
          end
        end
      Z3_END:
        begin
          if (FCS_n_sync[1]) begin
            z3_state <= Z3_IDLE;
            scsi_cycle <= 0;
            autoconfig_cycle <= 0;
            dtack <= 0;
          end else begin
            z3_state <= Z3_END;
            dtack <= 1;
          end
        end
    endcase
  end
end

Autoconfig AUTOCONFIG (
  .scsi_base_addr (scsi_base_addr),
  .ADDRL ({ADDR[8], A[7:2]}),
  .FCS_n (FCS_n_sync[1]),
  .CLK (CLK),
  .READ (READ),
  .DIN (D[31:28]),
  .RESET_n (IORST_n),
  .CFGOUT_n (autoconfig_cfgout),
  .autoconfig_cycle (autoconfig_cycle),
  .dtack (autoconfig_dtack),
  .configured (configured),
  .DOUT (autoconfig_dout),
  .z3_state (z3_state),
  .shutup (shutup)
);

SCSI SCSI (
  .CLK (CLK_50M),
  .RESET_n (IORST_n),
  .DTACK (DTACK_n)
);

endmodule
