`default_nettype none

module cdc_sync_gray #(
    parameter int unsigned STAGES = 2,
    parameter int unsigned WIDTH  = 2
)(
    input  wire logic             dst_clk,
    input  wire logic             dst_rst_n,
    input  wire logic [WIDTH-1:0] gray_async,
    output logic      [WIDTH-1:0] gray_sync
);
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [WIDTH-1:0] sync_ff [0:STAGES-1];

`ifdef SYNTHESIS
    initial begin : p_check_parameters
        if (WIDTH < 2) begin
            $fatal(1, "cdc_sync_gray: WIDTH (%0d) must be >= 2", WIDTH);
        end
        if (STAGES < 2) begin
            $fatal(1, "cdc_sync_gray: STAGES (%0d) must be >= 2", STAGES);
        end
    end
`endif

    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            sync_ff[0] <= '0;
        end else begin
            sync_ff[0] <= gray_async;
        end
    end

    genvar stage;
    generate
        for (stage = 1; stage < STAGES; stage++) begin : g_sync_stages
            always_ff @(posedge dst_clk or negedge dst_rst_n) begin
                if (!dst_rst_n) begin
                    sync_ff[stage] <= '0;
                end else begin
                    sync_ff[stage] <= sync_ff[stage-1];
                end
            end
        end
    endgenerate

    assign gray_sync = sync_ff[STAGES-1];
endmodule

`default_nettype wire