`default_nettype none

module reset_sync #(
    parameter int unsigned STAGES = 2
)(
    input  wire logic clk,
    input  wire logic arst_n,
    input  wire logic arst_aux_n,
    output logic      srst_n
);
    (* ASYNC_REG = "TRUE" *) logic [STAGES-1:0] sync_ff;

`ifdef SYNTHESIS
    initial begin : p_check_parameters
        if (STAGES < 2) begin
            $fatal(1, "reset_sync: STAGES (%0d) must be >= 2", STAGES);
        end
    end
`endif

    always_ff @(posedge clk or negedge arst_n or negedge arst_aux_n) begin
        if (!arst_n || !arst_aux_n) begin
            sync_ff <= '0;
        end else begin
            sync_ff <= {sync_ff[STAGES-2:0], 1'b1};
        end
    end

    assign srst_n = sync_ff[STAGES-1];
endmodule

``default_nettype wire