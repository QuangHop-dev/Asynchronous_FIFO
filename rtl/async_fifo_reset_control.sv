`default_nettype none

module async_fifo_reset_control #(
    parameter int unsigned SYNC_STAGES = 2,
    parameter bit          SAFE_RESET_ENABLE = 1'b1
)(
    input  wire logic wr_clk,
    input  wire logic wr_rst_n,
    input  wire logic rd_clk,
    input  wire logic rd_rst_n,

    output logic      wr_domain_rst_n,
    output logic      rd_domain_rst_n,
    output logic      wr_active,
    output logic      rd_active
);
`ifdef SYNTHESIS
    initial begin : p_check_parameters
        if (SYNC_STAGES < 2) begin
            $fatal(1, "async_fifo_reset_control: SYNC_STAGES (%0d) must be >= 2", SYNC_STAGES);
        end
    end
`endif

    generate
        if (SAFE_RESET_ENABLE) begin : g_safe_reset
            logic wr_ready;
            logic rd_ready;
            (* ASYNC_REG = "TRUE" *) logic [SYNC_STAGES-1:0] rd_ready_wr_ff;
            (* ASYNC_REG = "TRUE" *) logic [SYNC_STAGES-1:0] wr_ready_rd_ff;

            reset_sync #(
                .STAGES(SYNC_STAGES)
            ) u_wr_reset_sync (
                .clk(wr_clk),
                .arst_n(wr_rst_n),
                .arst_aux_n(rd_rst_n),
                .srst_n(wr_domain_rst_n)
            );

            reset_sync #(
                .STAGES(SYNC_STAGES)
            ) u_rd_reset_sync (
                .clk(rd_clk),
                .arst_n(rd_rst_n),
                .arst_aux_n(wr_rst_n),
                .srst_n(rd_domain_rst_n)
            );

            always_ff @(posedge wr_clk or negedge wr_domain_rst_n) begin
                if (!wr_domain_rst_n) begin
                    wr_ready <= 1'b0;
                end else begin
                    wr_ready <= 1'b1;
                end
            end

            always_ff @(posedge rd_clk or negedge rd_domain_rst_n) begin
                if (!rd_domain_rst_n) begin
                    rd_ready <= 1'b0;
                end else begin
                    rd_ready <= 1'b1;
                end
            end

            always_ff @(posedge wr_clk or negedge wr_domain_rst_n) begin
                if (!wr_domain_rst_n) begin
                    rd_ready_wr_ff[0] <= 1'b0;
                end else begin
                    rd_ready_wr_ff[0] <= rd_ready;
                end
            end

            always_ff @(posedge rd_clk or negedge rd_domain_rst_n) begin
                if (!rd_domain_rst_n) begin
                    wr_ready_rd_ff[0] <= 1'b0;
                end else begin
                    wr_ready_rd_ff[0] <= wr_ready;
                end
            end

            for (genvar ready_stage = 1; ready_stage < SYNC_STAGES; ready_stage++) begin : g_ready_sync_stage
                always_ff @(posedge wr_clk or negedge wr_domain_rst_n) begin
                    if (!wr_domain_rst_n) begin
                        rd_ready_wr_ff[ready_stage] <= 1'b0;
                    end else begin
                        rd_ready_wr_ff[ready_stage] <= rd_ready_wr_ff[ready_stage-1];
                    end
                end

                always_ff @(posedge rd_clk or negedge rd_domain_rst_n) begin
                    if (!rd_domain_rst_n) begin
                        wr_ready_rd_ff[ready_stage] <= 1'b0;
                    end else begin
                        wr_ready_rd_ff[ready_stage] <= wr_ready_rd_ff[ready_stage-1];
                    end
                end
            end

            assign wr_active = wr_domain_rst_n && wr_ready && rd_ready_wr_ff[SYNC_STAGES-1];
            assign rd_active = rd_domain_rst_n && rd_ready && wr_ready_rd_ff[SYNC_STAGES-1];

        end else begin : g_basic_reset
        
            reset_sync #(
                .STAGES(SYNC_STAGES)
            ) u_wr_reset_sync (
                .clk(wr_clk),
                .arst_n(wr_rst_n),
                .arst_aux_n(1'b1),
                .srst_n(wr_domain_rst_n)
            );

            reset_sync #(
                .STAGES(SYNC_STAGES)
            ) u_rd_reset_sync (
                .clk(rd_clk),
                .arst_n(rd_rst_n),
                .arst_aux_n(1'b1),
                .srst_n(rd_domain_rst_n)
            );

            assign wr_active = wr_domain_rst_n;
            assign rd_active = rd_domain_rst_n;
        end
    endgenerate
endmodule

`default_nettype wire