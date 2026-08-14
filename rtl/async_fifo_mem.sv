`default_nettype none

module async_fifo_mem #(
    parameter int unsigned DATA_WIDTH   = 32,
    parameter int unsigned DEPTH        = 16,
    parameter bit          FWFT_ENABLE  = 1'b0,
    parameter int unsigned ADDR_WIDTH   = $clog2(DEPTH)
)(
    input  wire logic                   wr_clk,
    input  wire logic                   wr_en,
    input  wire logic [DATA_WIDTH-1:0]  wr_data,
    input  wire logic [ADDR_WIDTH-1:0]  wr_addr,

    input  wire logic                   rd_clk,
    input  wire logic                   rd_rst_n,
    input  wire logic                   rd_en,
    input  wire logic [ADDR_WIDTH-1:0]  rd_addr,
    output logic      [DATA_WIDTH-1:0]  rd_data
);
    logic [DATA_WIDTH-1:0] mem [DEPTH-1:0];

    always_ff @(posedge wr_clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
    end

    generate
        if (FWFT_ENABLE) begin : g_fwft_read
            assign rd_data = mem[rd_addr];
        end else begin : g_standard_read
            always_ff @(posedge rd_clk or negedge rd_rst_n) begin
                if (!rd_rst_n) begin
                    rd_data <= '0;
                end else if (rd_en) begin
                    rd_data <= mem[rd_addr];
                end
            end
        end
    endgenerate    
endmodule

`default_nettype wire 