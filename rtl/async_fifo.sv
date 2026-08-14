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

`ifndef SYNTHESIS
    initial begin : p_check_parameters
        if (DATA_WIDTH == 0) begin
            $fatal(1, "async_fifo: DATA_WIDTH must be > 0");
        end
        if (DEPTH < 2) begin
            $fatal(1, "async_fifo: DEPTH (%0d) must be >= 2", DEPTH);
        end
        if (!is_power_of_two(DEPTH)) begin
            $fatal(1, "async_fifo: DEPTH (%0d) must be a power of 2", DEPTH);
        end
        if (SYNC_STAGES < 2) begin
            $fatal(1, "async_fifo: SYNC_STAGES (%0d) must be >= 2", SYNC_STAGES);
        end
        if (ALMOST_FULL_THRESHOLD > DEPTH) begin
            $fatal(1, "async_fifo: ALMOST_FULL_THRESHOLD (%0d) exceeds DEPTH (%0d)", ALMOST_FULL_THRESHOLD, DEPTH);
        end
        if (ALMOST_EMPTY_THRESHOLD > DEPTH) begin
            $fatal(1, "async_fifo: ALMOST_EMPTY_THRESHOLD (%0d) exceeds DEPTH (%0d)", ALMOST_EMPTY_THRESHOLD, DEPTH);
        end
    end
`endif

    async_fifo_reset_control #(
        .SYNC_STAGES(SYNC_STAGES),
        .SAFE_RESET_ENABLE(SAFE_RESET_ENABLE)
    ) u_reset_control (
        .wr_clk         (wr_clk),
        .wr_rst_n       (wr_rst_n),
        .rd_clk         (rd_clk),
        .rd_rst_n       (rd_rst_n),
        .wr_domain_rst_n(wr_domain_rst_n),
        .rd_domain_rst_n(rd_domain_rst_n),
        .wr_active      (wr_active),
        .rd_active      (rd_active)
    );

    cdc_sync_gray #(
        .WIDTH  (PTR_WIDTH),
        .STAGES (SYNC_STAGES)
    ) u_sync_rd_gray_to_wr (
        .dst_clk    (wr_clk),
        .dst_rst_n  (wr_domain_rst_n),
        .gray_async (rd_gray_q),
        .gray_sync  (rd_gray_wr_sync)
    );

    cdc_sync_gray #(
        .WIDTH  (PTR_WIDTH),
        .STAGES (SYNC_STAGES)
    ) u_sync_wr_gray_to_rd (
        .dst_clk    (rd_clk),
        .dst_rst_n  (rd_domain_rst_n),
        .gray_async (wr_gray_q),
        .gray_sync  (wr_gray_rd_sync)
    );

    assign wr_fire = wr_en && !wr_full_q && wr_active;
    assign rd_fire = rd_en && !rd_empty_q && rd_active;
    assign mem_wr_en = wr_fire;

    always_comb begin
        wr_bin_next = wr_bin_q;
        if (wr_fire) begin
            wr_bin_next = wr_bin_q + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
        end
        wr_gray_next = bin_to_gray(wr_bin_next);

        wr_full_next = (wr_gray_next == (rd_gray_wr_sync ^ FULL_COMPARE_MASK));
    end

    always_comb begin
        rd_bin_next = rd_bin_q;
        if (rd_fire) begin
            rd_bin_next = rd_bin_q + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
        end
        rd_gray_next = bin_to_gray(rd_bin_next);

        rd_empty_next = (rd_gray_next == wr_gray_rd_sync);
    end

    always_ff @(posedge wr_clk or negedge wr_domain_rst_n) begin
        if (!wr_domain_rst_n) begin
            wr_bin_q    <= '0;
            wr_gray_q   <= '0;
            wr_full_q   <= 1'b0;
            wr_overflow <= 1'b0;
        end else begin
            wr_bin_q    <= wr_bin_next;
            wr_gray_q   <= wr_gray_next;
            wr_full_q   <= wr_full_next;
            wr_overflow <= wr_active && wr_en && wr_full_q;
        end
    end

    always_ff @(posedge rd_clk or negedge rd_domain_rst_n) begin
        if (!rd_domain_rst_n) begin
            rd_bin_q      <= '0;
            rd_gray_q     <= '0;
            rd_empty_q    <= 1'b1;
            rd_valid_q    <= 1'b0;
            rd_underflow  <= 1'b0;
        end else begin
            rd_bin_q      <= rd_bin_next;
            rd_gray_q     <= rd_gray_next;
            rd_empty_q    <= rd_empty_next;
            rd_valid_q    <= rd_fire;
            rd_underflow  <= rd_active && rd_en && rd_empty_q;
        end
    end

    async_fifo_mem #(
        .DATA_WIDTH     (DATA_WIDTH),
        .DEPTH          (DEPTH),
        .FTWT_ENABLE      (FWFT_ENABLE)
    ) u_async_fifo_mem (
        .wr_clk     (wr_clk),
        .wr_en      (mem_wr_en),
        .wr_addr    (wr_bin_q[ADDR_WIDTH-1:0]),
        .wr_data    (wr_data),
        .rd_clk     (rd_clk),
        .rd_rst_n   (rd_domain_rst_n),
        .rd_en      (rd_fire),
        .rd_addr    (rd_bin_q[ADDR_WIDTH-1:0]),
        .rd_data    (rd_data)
    );

    generate
        for (genvar gray_bit = 0; gray_bit < PTR_WIDTH; gray_bit++) begin : g_gray_to_binary
            assign rd_bin_wr_sync[gray_bit] = ^ rd_gray_wr_sync[PTR_WIDTH-1:gray_bit];
            assign wr_bin_rd_sync[gray_bit] = ^ wr_gray_rd_sync[PTR_WIDTH-1:gray_bit];
        end
    endgenerate

    assign wr_level_calc = (wr_bin_q - rd_bin_wr_sync);
    assign rd_level_calc = (wr_bin_rd_sync - rd_bin_q);

    assign wr_full          = wr_full_q || !wr_active;
    assign rd_empty         = rd_empty_q || !rd_active;
    assign wr_level         = wr_active ? wr_level_calc : '0;
    assign rd_level         = rd_active ? rd_level_calc : '0;
    assign wr_almost_full   = !wr_active || (wr_level_calc >= ALMOST_FULL_THRESHOLD);
    assign rd_almost_empty  = !rd_active || (rd_level_calc <= ALMOST_EMPTY_THRESHOLD);

    generate
        if (FWFT_ENABLE) begin : g_fwft_valid
            assign rd_valid = !rd_empty_q && rd_active;
        end else begin : g_standard_valid
            assign rd_valid = rd_valid_q;
        end
    endgenerate
endmodule

`default_nettype wire