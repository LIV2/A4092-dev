module spi_access (
    input wire SPI_MISO,
    output wire SPI_CLK,
    output wire SPI_MOSI,
    output wire SPI_CS_n
);

    assign SPI_CLK = 1'b0;
    assign SPI_MOSI = 1'b0;
    assign SPI_CS_n = 1'b1;

endmodule
