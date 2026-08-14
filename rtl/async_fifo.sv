`default_nettype none

module async_fifo #(
    parameter int unsigned DATA_WIDTH               = 32,
    parameter int unsigned DEPTH                    = 16,
    parameter int unsigned SYNC_STAGES              = 2,
    parameter int unsigned ALMOST_FULL_THRESHOLD    = DEPTH - 1,
    parameter int unsigned ALMOST_EMPTY_THRESHOLD   = 1,
    parameter bit          FWFT_ENABLE              = 1'b0,
    parameter bit          SAFE_RESET_ENABLE        = 1'b1,
    localparam int unsigned ADDR_WIDTH               = $clog2(DEPTH),
    localparam int unsigned PTR_WIDTH                = ADDR_WIDTH + 1,
    localparam int unsigned LEVEL_WIDTH              = $clog2(DEPTH+1)
)(
    input  wire logic                   wr_clk,
    input  wire logic                   wr_rst_n,
    input  wire logic                   wr_en,
    input  wire logic [DATA_WIDTH-1:0]  wr_data,
    //---
    output logic                        wr_full,
    output logic                        wr_almost_full,
    output logic      [LEVEL_WIDTH-1:0] wr_level,
    output logic                        wr_overflow,

    input  wire logic                   rd_clk,
    input  wire logic                   rd_rst_n,
    input  wire logic                   rd_en,
    //---
    output logic      [DATA_WIDTH-1:0]  rd_data,
    output logic                        rd_valid,
    output logic                        rd_empty,
    output logic                        rd_almost_empty,
    output logic      [LEVEL_WIDTH-1:0] rd_level,
    output logic                        rd_underflow
);
    import async_fifo_pkg::is_power_of_two;

    localparam logic [PTR_WIDTH-1:0] FULL_COMPARE_MASK = {2'b11, {(PTR_WIDTH-2){1'b0}}};

    logic wr_domain_rst_n;
    logic rd_domain_rst_n;
    logic wr_active;
    logic rd_active;

    logic [PTR_WIDTH-1:0] wr_bin_q;
    logic [PTR_WIDTH-1:0] wr_bin_next;
    logic [PTR_WIDTH-1:0] wr_gray_q;
    logic [PTR_WIDTH-1:0] wr_gray_next;
    logic [PTR_WIDTH-1:0] rd_bin_q;
    logic [PTR_WIDTH-1:0] rd_bin_next;
    logic [PTR_WIDTH-1:0] rd_gray_q;
    logic [PTR_WIDTH-1:0] rd_gray_next;
    logic [PTR_WIDTH-1:0] rd_gray_wr_sync;
    logic [PTR_WIDTH-1:0] wr_gray_rd_sync;
    logic [PTR_WIDTH-1:0] rd_bin_wr_sync;
    logic [PTR_WIDTH-1:0] wr_bin_rd_sync;

    logic wr_full_q;
    logic wr_full_next;
    logic rd_empty_q;
    logic rd_empty_next;
    logic rd_valid_q;
    logic wr_fire;
    logic rd_fire;
    logic mem_wr_en;
    logic [LEVEL_WIDTH-1:0] wr_level_calc;
    logic [LEVEL_WIDTH-1:0] rd_level_calc;

    function automatic logic [PTR_WIDTH-1:0] bin_to_gray(input logic [PTR_WIDTH-1:0] value);
        return (value >> 1) ^ value;
    endfunction

`ifdef SYNTHESIS
    initial begin : p_check_parameters
        if (!is_power_of_two(DEPTH)) begin
            $fatal(1, "async_fifo: DEPTH (%0d) must be a power of 2", DEPTH);
        end
        if (DATA_WIDTH < 1) begin
            $fatal(1, "async_fifo: DATA_WIDTH (%0d) must be >= 1", DATA_WIDTH);
        end
        if (SYNC_STAGES < 2) begin
            $fatal(1, "async_fifo: SYNC_STAGES (%0d) must be >= 2", SYNC_STAGES);
        end
        if (ALMOST_FULL_THRESHOLD < 1 || ALMOST_FULL_THRESHOLD > DEPTH) begin
            $fatal(1, "async_fifo: ALMOST_FULL_THRESHOLD (%0d) must be in the range [1, %0d]", ALMOST_FULL_THRESHOLD, DEPTH);
        end
        if (ALMOST_EMPTY_THRESHOLD < 1 || ALMOST_EMPTY_THRESHOLD > DEPTH) begin
            $fatal(1, "async_fifo: ALMOST_EMPTY_THRESHOLD (%0d) must be in the range [1, %0d]", ALMOST_EMPTY_THRESHOLD, DEPTH);
        end
    end

`default_nettype wire