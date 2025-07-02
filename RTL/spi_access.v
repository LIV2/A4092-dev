module spi_access (
    input wire [20:0] ADDR,
    input wire SPI_MISO,
    output wire SPI_CLK,
    output wire SPI_MOSI,
    output wire SPI_CS_n,
    output wire spi_dtack,
    output wire [7:0] DOUT
);

    assign SPI_CLK = 1'b0;
    assign SPI_MOSI = 1'b0;
    assign SPI_CS_n = 1'b1;

    assign spi_dtack = 1'b0;
    assign DOUT = 8'b10100101;

endmodule
