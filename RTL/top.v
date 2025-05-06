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
    input ROM_OE,
    input SBR,
    input SBG,
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
    output CINH_n,
    output ROM_WE_n,
    output MTCR_n,
    output CBACK_n,
    output STERM_n
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

// Address latching
reg [27:8] ADDR;
reg autoconfig_addr_match;
reg scsi_addr_match;
wire match = autoconfig_addr_match || scsi_addr_match;
wire configured;
wire validspace = FC[1] ^ FC[0];
wire shutup;

// Latch address bits 27-8 on FCS_n asserted
// 
always @(negedge FCS_n or negedge IORST_n)
begin
  if (!IORST_n) begin
    ADDR                  <= 0;
    scsi_addr_match       <= 0;
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
wire [27:0] full_addr = {ADDR, A[7:0]};
wire rom_dtack;
wire sid_dtack;
wire int_dtack;
wire [3:0] intreg_dout;
wire MTCR_n_int;
wire CBACK_n_int;
wire STERM_n_int;
// buffer control
wire DBOE_n_int;
wire ABOEL_n_int;
wire ABOEH_n_int;
wire D2Z_n_int;
wire Z2D_n_int;


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
          end else if ((autoconfig_dtack && autoconfig_cycle) ||
		       (scsi_dtack && scsi_cycle) ||
		       rom_dtack ||
		       sid_dtack ||
		       int_dtack) begin
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


// Autoconf
wire [3:0] scsi_base_addr;
wire [3:0] autoconfig_dout;
wire autoconfig_cfgout;

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

// | **Offset**            | **Size** | **Function**          | **Module**      |
// | --------------------- | -------- | --------------------- | --------------- |
// | `0x000000`–`0x07FFFF` | 512 KB   | Flash ROM             | `rom_access`    |
// | `0x080000`–`0x0BFFFF` | 256 KB   | **Unused / Reserved** |                 |
// | `0x0C0000`–`0x0FFFFF` | 256 KB   | SCSI ID read          | `sid_access`    |
// | `0x100000`–`0x8FFFFF` | \~7.5 MB | SCSI registers (710)  | `scsi`          |
// | `0x900000`            | 4 bytes  | INTREG                | `intreg_access` |
// | `0x900004`            | 4 bytes  | INTVEC                | `intreg_access` |
// | `0x900008`–`0xFFFFFF` | 6.25 MB+ | **Unused / Reserved** |                 |

scsi_access SCSI_ACCESS (
  .CLK(CLK),
  .RESET_n(IORST_n),
  .ADDR(full_addr),
  .READ(READ),
  .FCS_n(FCS_n_sync[1]),
  .slave_cycle(!MASTER && !BMASTER),
  .configured(configured),
  .scsi_dtack(scsi_dtack)
);

rom_access ROM_ACCESS (
  .CLK(CLK),
  .RESET_n(IORST_n),
  .ADDR(ADDR),
  .READ(READ),
  .FCS_n(FCS_n_sync[1]),
  .slave_cycle(!MASTER && !BMASTER), // or use a named wire `slave_cycle`
  .configured(configured),
  .shutup(shutup),

  .rom_dtack(rom_dtack),
  .rom_selected(), // optional, used if you want to debug or route match logic
  .ROM_CE_n(ROM_CE_n),
  .ROM_OE_n(ROM_OE_n),
  .ROM_WE_n(ROM_WE_n)
);

sid_access SID_ACCESS (
  .CLK(CLK),
  .RESET_n(IORST_n),
  .ADDR({ADDR, A[7:0]}),
  .READ(READ),
  .FCS_n(FCS_n_sync[1]),
  .slave_cycle(!MASTER && !BMASTER),
  .configured(configured),
  .sid_dtack(sid_dtack),
  .SID_n(SID_n)
);

assign MTCR_n  = MTCR_n_int;
assign CBACK_n = CBACK_n_int;
assign STERM_n = STERM_n_int;

assign D[31:28] = (autoconfig_cycle) ? autoconfig_dout :
                  (int_dtack)        ? intreg_dout     :
                  4'hF;

assign DBOE_n  = DBOE_n_int;
assign ABOEL_n = ABOEL_n_int;
assign ABOEH_n = ABOEH_n_int;
assign D2Z_n   = D2Z_n_int;
assign Z2D_n   = Z2D_n_int;

intreg_access INTREG_ACCESS (
  .CLK(CLK),
  .RESET_n(IORST_n),
  .ADDR({ADDR, A[7:0]}),
  .READ(READ),
  .FCS_n(FCS_n_sync[1]),
  .slave_cycle(!MASTER && !BMASTER),
  .configured(configured),
  .NCR_INT(NCR_INT),
  .int_dtack(int_dtack),
  .INT_n(INT_n),
  .DOUT(intreg_dout),
  .MTCR_n(MTCR_n_int),
  .CBACK_n(CBACK_n_int),
  .STERM_n(STERM_n_int)
);

buffer_control BUFFER_CONTROL (
  .CLK(CLK),
  .RESET_n(IORST_n),
  .READ(READ),
  .slave_cycle(!MASTER && !BMASTER),
  .configured(configured),
  .BMASTER(BMASTER),
  .MASTER(MASTER),
  .ADDR({ADDR, A[7:0]}),
  .FCS_n(FCS_n_sync[1]),
  .DBOE_n(DBOE_n_int),
  .ABOEL_n(ABOEL_n_int),
  .ABOEH_n(ABOEH_n_int),
  .D2Z_n(D2Z_n_int),
  .Z2D_n(Z2D_n_int)
);

endmodule
