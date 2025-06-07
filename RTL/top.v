`timescale 1ns / 1ps

//
// MODULE: A4092 (top.v)
// DESCRIPTION:
// Final version incorporating all discussed fixes: interrupt logic, DMA architecture,
// SCSI slave interface, and correct FCS signal generation and buffering.
//
module A4092(
    // Address Bus
    input  wire [31:0] A,
    // Data Bus
    inout wire [31:0] D,
    // External 50MHz Clock
    input  wire CLK_50M,
    // Internal 25MHz Clock
    output reg CLK,
    // 
    input  wire IORST_n,

    // Zorro Bus Interface
    inout  wire [3:0] DS_n,
    input  wire [2:0] FC,
    input  wire Z_LOCK, // Zorro LOCK signal
    input  wire Z_7M, // 7MHz clock for arbitration
    inout  wire FCS_n, // Is input and output (driven during DMA)
    output wire DOE,
    input  wire READ,
    inout  wire DTACK_n,
    output wire INT2_n,
    input  wire CFGIN_n,
    output wire CFGOUT_n,
    output wire SLAVE_n,
    output wire CINH_n,
    inout  wire MTCR_n, // Is input for IACK, output for master
    input  wire BERR_n,
    input  wire BGn, // Zorro Bus Grant
    output wire BRn, // Zorro Bus Request
    input wire SENSEZ3_n,

    // Buffer Control
    output wire DBLT,
    output wire DBOE_n,
    output wire ABOEL_n,
    output wire ABOEH_n,
    output wire D2Z_n,
    output wire Z2D_n,

    // SCSI Chip Interface
    input  wire SLACK_n,  // SCSI ack during slave access
    input  wire SINT_n,   // SCSI interrupt
    input  wire SBR_n,    // SCSI bus request (for DMA)
    input  wire [1:0] SIZ, // Sizing bits from SCSI (for DMA)
    output wire SBG_n,    // SCSI bus grant (for DMA)
    output wire BMASTER,  // Buffered MASTER signal
    output reg  MASTER_n, // SCSI chip is master of local bus
    output wire SCSI_AS_n, // Address Strobe to SCSI chip (PLD_AS)
    output wire SCSI_DS_n, // Data Strobe to SCSI chip (PLD_DS)
    output wire SCSI_SREG_n, // Register select to SCSI chip
    output wire SCSI_STERM_n,

    // ROM Interface
    output wire ROM_OE_n,
    output wire ROM_CE_n,
    output wire ROM_WE_n,

    // Alternative SPI Interface
    input SPI_MISO,
    output reg SPI_MOSI,
    output reg SPI_CLK,
    output reg SPI_CS_n,

    // Board Control
    output wire SID_n,
    output wire DIP_EXT_TERM,

    // Unused:
    // We _never_ issue a CBACK, since BURST isn't supported
    input CBREQ_n,
    output CBACK_n,
    output MTACK_n,
    input Z_FCS

);

`include "globalparams.vh"

// --- Wires and Registers ---
wire CLKI;
reg  [27:8] ADDR;
reg  autoconfig_addr_match;
reg  scsi_addr_match;
wire match = autoconfig_addr_match || scsi_addr_match;
wire configured;
wire validspace = FC[1] ^ FC[0];
wire shutup;
reg  [1:0] z3_state;
reg  dtack;
reg  scsi_cycle;
reg  autoconfig_cycle;

// Connections to Sub-modules
wire bfcs; // The internal, buffered FCS signal
wire autoconfig_dtack;
wire [3:0] autoconfig_dout;
wire autoconfig_cfgout;
wire [3:0] scsi_base_addr;
wire scsi_dtack;
wire rom_dtack;
wire sid_dtack;
wire iack_slave_n;
wire iack_dtack_n;
wire [7:0] iack_dout;
wire DBOE_n_int;
wire ABOEL_n_int;
wire ABOEH_n_int;
wire D2Z_n_int;
wire Z2D_n_int;
wire DBLT_int;
`ifndef USE_DIP_SWITCH
wire [7:0] dip_shadow;
`endif

wire slave_cycle = !MASTER_n && !BMASTER;
wire [27:0] full_addr = {ADDR, A[7:0]};

wire dma_fcs_n, dma_doe;
wire [3:0] dma_ds_n;
assign FCS_n = BMASTER ? dma_fcs_n : 1'bz;
assign DS_n  = BMASTER ? dma_ds_n  : 4'bzzzz;
assign DOE   = (BMASTER && !READ) || (slave_cycle && !READ && !bfcs);


// --- Clock Generation ---
always @(posedge CLK_50M)
  CLK <= ~CLK;

assign CLKI = ~CLK;

// --- Address Latching and Matching ---
always @(negedge FCS_n or negedge IORST_n) begin
  if (!IORST_n) begin
    ADDR <= 0;
    scsi_addr_match <= 0;
    autoconfig_addr_match <= 0;
  end else begin
    MASTER_n <= READ;
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

// --- Main Zorro Slave State Machine ---
always @(posedge CLK or negedge IORST_n) begin
  if (!IORST_n) begin
    z3_state         <= Z3_IDLE;
    dtack            <= 1'b0;
    scsi_cycle       <= 1'b0;
    autoconfig_cycle <= 1'b0;
  end else begin
    // Use the new internal 'bfcs' for cycle detection
    case (z3_state)
      Z3_IDLE: begin
          dtack <= 0;
          if (!bfcs && match && validspace) begin
            z3_state         <= Z3_START;
            autoconfig_cycle <= autoconfig_addr_match;
            scsi_cycle       <= scsi_addr_match;
          end
        end
      Z3_START: begin
          if (bfcs) begin
            z3_state <= Z3_IDLE;
          end else if (READ || (|DS_n != 4'b1111)) begin
            z3_state <= Z3_DATA;
          end
        end
      Z3_DATA: begin
          if (bfcs) begin
            z3_state <= Z3_IDLE;
          end else if ((autoconfig_dtack && autoconfig_cycle) ||
                       (scsi_dtack && scsi_cycle) ||
                       (rom_dtack) || (sid_dtack) || !iack_dtack_n) begin
            z3_state <= Z3_END;
          end
        end
      Z3_END: begin
          if (bfcs) begin
            z3_state         <= Z3_IDLE;
            scsi_cycle       <= 0;
            autoconfig_cycle <= 0;
            dtack            <= 0;
          end else begin
            z3_state         <= Z3_END;
            dtack            <= 1;
          end
        end
    endcase
  end
end

// --- Top-Level Bus Assignments ---
assign DTACK_n  = dtack ? 1'b0 : 1'bz;
assign SLAVE_n  = !((slave_cycle && configured) || !iack_slave_n);
assign CFGOUT_n = (SENSEZ3_n) ? autoconfig_cfgout : CFGIN_n;
assign CINH_n   = !(slave_cycle && configured);
assign DBLT     = DBLT_int;

// --- Data Bus Multiplexer for Read Cycles ---
// The CPLD drives the data bus (D) only during a READ cycle when one of
// its internal registers/logic is selected and ready. Otherwise, D is tristated.

// Autoconfig data is driven on D[31:28].
// This happens when it's an autoconfig cycle, dtack is active (meaning data phase), and it's a READ.
assign D[31:28] = (autoconfig_cycle && dtack && READ) ? autoconfig_dout : 4'bzzzz;

// Bits D[27:8] are not driven by this CPLD during any read cycle it handles.
// So, they are always tristated from the CPLD's perspective.
assign D[27:8]  = 20'bzzzzzzzzzzzzzzzzzzzz; // 20 bits

// Interrupt Vector (iack_dout) or SCSI ID (dip_shadow) are driven on D[7:0].
// The conditions `!iack_dtack_n` and `sid_dtack` already imply a READ cycle
// from their respective modules.
assign D[7:0]   = !iack_dtack_n ? iack_dout :        // Interrupt vector has priority
`ifndef USE_DIP_SWITCH
                  sid_dtack     ? dip_shadow :
`endif
                                  8'bzzzzzzzz;       // Tristate if neither

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

// --- Module Instantiations ---

Autoconfig AUTOCONFIG (
  .scsi_base_addr(scsi_base_addr),
  .ADDRL({ADDR[8], A[7:2]}),
  .FCS_n(!bfcs),
  .CLK(CLK),
  .READ(READ),
  .DIN(D[31:28]),
  .RESET_n(IORST_n),
  .CFGOUT_n(autoconfig_cfgout),
  .autoconfig_cycle(autoconfig_cycle),
  .dtack(autoconfig_dtack),
  .configured(configured),
  .DOUT(autoconfig_dout),
  .z3_state(z3_state),
  .shutup(shutup)
);

scsi_access SCSI_ACCESS (
  .CLK(CLK),
  .RESET_n(IORST_n),
  .ADDR(full_addr[23:17]),
  .FCS_n(!bfcs),
  .slave_cycle(slave_cycle),
  .configured(configured),
  .SLACK_n(SLACK_n),
  .scsi_dtack(scsi_dtack)
);

rom_access ROM_ACCESS (
  .CLK(CLK),
  .RESET_n(IORST_n),
  .ADDR(ADDR[23:17]),
  .READ(READ),
  .FCS_n(!bfcs),
  .slave_cycle(slave_cycle),
  .configured(configured),
  .shutup(shutup),
  .rom_dtack(rom_dtack),
  .ROM_CE_n(ROM_CE_n),
  .ROM_OE_n(ROM_OE_n),
  .ROM_WE_n(ROM_WE_n)
);

sid_access SID_ACCESS (
  .CLK(CLK),
  .RESET_n(IORST_n),
  .ADDR(full_addr[23:17]),
  .READ(READ),
`ifndef USE_DIP_SWITCH
  .DIN(D[7:0]),
  .DOUT(dip_shadow),
  .dip_ext_term(DIP_EXT_TERM),
`endif
  .FCS_n(!bfcs),
  .slave_cycle(slave_cycle),
  .configured(configured),
  .sid_dtack(sid_dtack),
  .SID_n(SID_n)
);

intreg_access INTREG_ACCESS (
  .CLK(CLK),
  .RESET_n(IORST_n),
  .FCS_n(!bfcs),
  .configured(configured),
  .FC(FC),
  .ADDR(full_addr[23:17]),
  .LOCK(Z_LOCK),
  .READ(READ),
  .DS0_n(DS_n[0]),
  .MTCR_n(MTCR_n),
  .NCR_INT(SINT_n),
  .INT2_n(INT2_n),
  .iack_slave_n(iack_slave_n),
  .iack_dtack_n(iack_dtack_n),
  .DOUT(iack_dout)
);

buffer_control BUFFER_CONTROL (
  .CLK(CLK),
  .RESET_n(IORST_n),
  .READ(READ),
  .slave_cycle(slave_cycle),
  .configured(configured),
  .BMASTER(BMASTER),
  .MASTER_n(MASTER_n),
  .ADDR(full_addr[23:17]),
  .FCS_n(!bfcs),
  .DBOE_n(DBOE_n_int),
  .ABOEL_n(ABOEL_n_int),
  .ABOEH_n(ABOEH_n_int),
  .D2Z_n(D2Z_n_int),
  .Z2D_n(Z2D_n_int)
);

zorro_master_arbiter ZMA (
  .CLK(Z_7M),
  .RESET_n(IORST_n),
  .FCS(!bfcs),
  .DTACK(~DTACK_n),
  .RST(~IORST_n),
  .EBG_n(BGn), // Connected to actual bus grant
  .SBR_n(SBR_n),
  .MASTER(MASTER_n),
  .SBG_n(SBG_n),
  .BMASTER(BMASTER),
  .EBR_n(BRn) // Drives bus request
);

zorro_dma_master ZDMA (
  .CLK(CLK),
  .RESET_n(IORST_n),
  .BMASTER(BMASTER),
  .READ(READ),
  .SIZ(SIZ),
  .A(A[1:0]),
  .SCSI_AS_n(SCSI_AS_n),
  .ZORRO_FCS_n(FCS_n),
  .ZORRO_DTACK_n(DTACK_n),
  .DMA_DOE(dma_doe),
  .DMA_DS_n(dma_ds_n),
  .DMA_FCS_n(dma_fcs_n),
  .SCSI_STERM_n(SCSI_STERM_n),
  .BFCS_out(bfcs)
);

endmodule
