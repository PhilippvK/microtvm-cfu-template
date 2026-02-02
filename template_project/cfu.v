`timescale 1ns/1ps

module Cfu (
    input wire         cmd_valid,
    output wire        cmd_ready,
    input wire [9:0]   cmd_payload_function_id,
    input wire [31:0]  cmd_payload_inputs_0,
    input wire [31:0]  cmd_payload_inputs_1,
    output reg         rsp_valid,
    input              rsp_ready,
    output reg [31:0]  rsp_payload_outputs_0,
    input              reset,
    input              clk
);

    reg signed [7:0] clusters_2 [0:1];
    reg signed [7:0] clusters_4 [0:3];
    reg signed [7:0] clusters_16 [0:15];
    reg signed [7:0] active_clusters [0:31];
    integer i, j;
    reg signed [7:0] acts [0:7];
    reg signed [7:0] ws   [0:7];
    reg signed [15:0] prod [0:7];
    reg [1:0] active_cluster_chunk_idx;
    reg [1:0] alu_mac_count;
    reg [1:0] mac16_count;
    reg [31:0] weight_code_packed;
    reg [4:0]  last_cluster_num;
    reg        c16_toggle;
    reg signed [31:0] total_mac;
    reg signed [31:0] sum_0, sum_1, sum_2, sum_3, sum_4, sum_5, sum_6, sum_7;

    wire [6:0] funct7 = cmd_payload_function_id[9:3];
    localparam [6:0] CFU_FUNCT7_SET_CODEBOOK_2   = 7'h20;
    localparam [6:0] CFU_FUNCT7_SET_CODEBOOK_4   = 7'h28;
    localparam [6:0] CFU_FUNCT7_SET_CODEBOOK_16  = 7'h38;
    localparam [6:0] CFU_FUNCT7_PUSH_WEIGHTS     = 7'h10;
    localparam [6:0] CFU_FUNCT7_ALU_MAC          = 7'h40;
    localparam [6:0] CFU_FUNCT7_ALU_RST          = 7'h48;
    localparam [6:0] CFU_FUNCT7_MAC_READ         = 7'h50;
    localparam [6:0] CFU_FUNCT7_DEBUG_DUMP       = 7'h52;
    localparam [6:0] CFU_FUNCT7_MAC_READ_NO_RESET = 7'h54;

    assign cmd_ready = (!rsp_valid); // Do not accept new commands until response is accepted

    always @(posedge clk) begin
        if (reset) begin
            active_cluster_chunk_idx <= 0;
            alu_mac_count <= 0;
            mac16_count <= 0;
            total_mac <= 0;
            clusters_2[0] <= 0; clusters_2[1] <= 0;
            clusters_4[0] <= 0; clusters_4[1] <= 0; clusters_4[2] <= 0; clusters_4[3] <= 0;
            for (i = 0; i < 16; i = i + 1) clusters_16[i] <= 0;
            for (i = 0; i < 32; i = i + 1) active_clusters[i] <= 0;
            weight_code_packed <= 0;
            last_cluster_num <= 4;
            c16_toggle <= 0;
            sum_0 <= 0; sum_1 <= 0; sum_2 <= 0; sum_3 <= 0;
            sum_4 <= 0; sum_5 <= 0; sum_6 <= 0; sum_7 <= 0;
            rsp_valid <= 0;
            rsp_payload_outputs_0 <= 0;
        end
        else begin
            // Handle response handshake
            if (rsp_valid && rsp_ready)
                rsp_valid <= 0;

            // Only accept new commands when not holding a response
            if (cmd_valid && !rsp_valid) begin
                rsp_valid <= 1'b1;

                if (funct7 == CFU_FUNCT7_SET_CODEBOOK_2) begin
                    clusters_2[0] <= $signed(cmd_payload_inputs_0[7:0]);
                    clusters_2[1] <= $signed(cmd_payload_inputs_0[15:8]);
                    last_cluster_num <= 2;
                    rsp_payload_outputs_0 <= 32'hAABB2202;
                end
                else if (funct7 == CFU_FUNCT7_SET_CODEBOOK_4) begin
                    clusters_4[0] <= $signed(cmd_payload_inputs_0[7:0]);
                    clusters_4[1] <= $signed(cmd_payload_inputs_0[15:8]);
                    clusters_4[2] <= $signed(cmd_payload_inputs_0[23:16]);
                    clusters_4[3] <= $signed(cmd_payload_inputs_0[31:24]);
                    last_cluster_num <= 4;
                    rsp_payload_outputs_0 <= 32'hAABB4404;
                end
                else if (funct7 == CFU_FUNCT7_SET_CODEBOOK_16) begin
                    if (!c16_toggle) begin
                        clusters_16[0] <= $signed(cmd_payload_inputs_0[7:0]);
                        clusters_16[1] <= $signed(cmd_payload_inputs_0[15:8]);
                        clusters_16[2] <= $signed(cmd_payload_inputs_0[23:16]);
                        clusters_16[3] <= $signed(cmd_payload_inputs_0[31:24]);
                        clusters_16[4] <= $signed(cmd_payload_inputs_1[7:0]);
                        clusters_16[5] <= $signed(cmd_payload_inputs_1[15:8]);
                        clusters_16[6] <= $signed(cmd_payload_inputs_1[23:16]);
                        clusters_16[7] <= $signed(cmd_payload_inputs_1[31:24]);
                        rsp_payload_outputs_0 <= 32'hAABB16A0;
                    end else begin
                        clusters_16[8]  <= $signed(cmd_payload_inputs_0[7:0]);
                        clusters_16[9]  <= $signed(cmd_payload_inputs_0[15:8]);
                        clusters_16[10] <= $signed(cmd_payload_inputs_0[23:16]);
                        clusters_16[11] <= $signed(cmd_payload_inputs_0[31:24]);
                        clusters_16[12] <= $signed(cmd_payload_inputs_1[7:0]);
                        clusters_16[13] <= $signed(cmd_payload_inputs_1[15:8]);
                        clusters_16[14] <= $signed(cmd_payload_inputs_1[23:16]);
                        clusters_16[15] <= $signed(cmd_payload_inputs_1[31:24]);
                        rsp_payload_outputs_0 <= 32'hAABB16B1;
                    end
                    c16_toggle <= ~c16_toggle;
                    last_cluster_num <= 16;
                end
                else if (funct7 == CFU_FUNCT7_PUSH_WEIGHTS) begin
                    weight_code_packed <= cmd_payload_inputs_0;
                    if (last_cluster_num == 2) begin
                        for (i = 0; i < 32; i = i + 1)
                            active_clusters[i] <= clusters_2[(cmd_payload_inputs_0 >> i) & 1];
                    end
                    else if (last_cluster_num == 4) begin
                        for (i = 0; i < 16; i = i + 1)
                            active_clusters[i] <= clusters_4[cmd_payload_inputs_0[(2*i)+1 -: 2]];
                        for (i = 0; i < 16; i = i + 1)
                            active_clusters[16 + i] <= clusters_4[cmd_payload_inputs_1[(2*i)+1 -: 2]];
                    end
                    else if (last_cluster_num == 16) begin
                        for (i = 0; i < 8; i = i + 1) begin
                            active_clusters[i] <= clusters_16[cmd_payload_inputs_0[i*4 +: 4]];
                            active_clusters[8 + i] <= clusters_16[cmd_payload_inputs_1[i*4 +: 4]];
                        end
                    end

                    rsp_payload_outputs_0 <= 32'hDEAD0000;
                    active_cluster_chunk_idx <= active_cluster_chunk_idx + 1;
                end
                else if (funct7 == CFU_FUNCT7_ALU_MAC) begin
                    if (last_cluster_num == 16) begin
                        // For 16 clusters: use active_clusters[0..7] first, [8..15] next
                        for (j = 0; j < 4; j = j+1) begin
                            acts[j]   = $signed(cmd_payload_inputs_0 >> (8*j));
                            ws[j]     = active_clusters[mac16_count*8 + j];
                        end
                        for (j = 0; j < 4; j = j+1) begin
                            acts[j+4] = $signed(cmd_payload_inputs_1 >> (8*j));
                            ws[j+4]   = active_clusters[mac16_count*8 + j + 4];
                        end
                        // Increment mac16_count, reset after two calls
                        if (mac16_count == 1)
                            mac16_count <= 0;
                        else
                            mac16_count <= mac16_count + 1;
                    end else begin
                        // For 2/4 clusters, chunk by alu_mac_count
                        for (j = 0; j < 4; j = j+1) begin
                            acts[j]   = $signed(cmd_payload_inputs_0 >> (8*j));
                            ws[j]     = active_clusters[alu_mac_count*8+j];
                        end
                        for (j = 0; j < 4; j = j+1) begin
                            acts[j+4] = $signed(cmd_payload_inputs_1 >> (8*j));
                            ws[j+4]   = active_clusters[alu_mac_count*8+j+4];
                        end
                        alu_mac_count <= alu_mac_count + 1;
                    end

                    // Common accumulation for both
                    for (j = 0; j < 8; j = j+1) begin
                        prod[j] = ws[j] * (acts[j] + 128);
                    end
                    sum_0 <= sum_0 + prod[0];
                    sum_1 <= sum_1 + prod[1];
                    sum_2 <= sum_2 + prod[2];
                    sum_3 <= sum_3 + prod[3];
                    sum_4 <= sum_4 + prod[4];
                    sum_5 <= sum_5 + prod[5];
                    sum_6 <= sum_6 + prod[6];
                    sum_7 <= sum_7 + prod[7];
                    rsp_payload_outputs_0 <= 32'hABCD0001;
                end
                /*
                else if (funct7 == CFU_FUNCT7_ALU_MAC) begin
                    for (j = 0; j < 4; j = j+1) begin
                        acts[j]   = $signed(cmd_payload_inputs_0 >> (8*j));
                        ws[j]     = active_clusters[alu_mac_count*8+j];
                    end
                    for (j = 0; j < 4; j = j+1) begin
                        acts[j+4] = $signed(cmd_payload_inputs_1 >> (8*j));
                        ws[j+4]   = active_clusters[alu_mac_count*8+j+4];
                    end
                    for (j = 0; j < 8; j = j+1) begin
                        prod[j] = ws[j] * (acts[j] + 128);
                    end
                    sum_0 <= sum_0 + prod[0];
                    sum_1 <= sum_1 + prod[1];
                    sum_2 <= sum_2 + prod[2];
                    sum_3 <= sum_3 + prod[3];
                    sum_4 <= sum_4 + prod[4];
                    sum_5 <= sum_5 + prod[5];
                    sum_6 <= sum_6 + prod[6];
                    sum_7 <= sum_7 + prod[7];
                    alu_mac_count <= alu_mac_count + 1;
                    rsp_payload_outputs_0 <= 32'hABCD0001;
                end
                */
               else if (funct7 == CFU_FUNCT7_MAC_READ) begin
                   rsp_payload_outputs_0 <= sum_0 + sum_1 + sum_2 + sum_3 +
                       sum_4 + sum_5 + sum_6 + sum_7;
               end
                else if (funct7 == CFU_FUNCT7_MAC_READ_NO_RESET) begin
                    rsp_payload_outputs_0 <= sum_0 + sum_1 + sum_2 + sum_3 +
                                             sum_4 + sum_5 + sum_6 + sum_7;
                end
                else if (funct7 == CFU_FUNCT7_ALU_RST) begin
                    total_mac <= 0;
                    sum_0 <= 0; sum_1 <= 0; sum_2 <= 0; sum_3 <= 0;
                    sum_4 <= 0; sum_5 <= 0; sum_6 <= 0; sum_7 <= 0;
                    alu_mac_count <= 0;
                    mac16_count <= 0;
                    active_cluster_chunk_idx <= 0;
                    rsp_payload_outputs_0 <= 0;
                end
                else if (funct7 == CFU_FUNCT7_DEBUG_DUMP) begin
                    rsp_payload_outputs_0 <= active_clusters[cmd_payload_inputs_0[4:0]];
                end
                else begin
                    rsp_payload_outputs_0 <= 0;
                end
            end

            // Clear sums and indices only AFTER MAC_READ is acknowledged
            if (rsp_valid && rsp_ready && funct7 == CFU_FUNCT7_MAC_READ) begin
                sum_0 <= 0; sum_1 <= 0; sum_2 <= 0; sum_3 <= 0;
                sum_4 <= 0; sum_5 <= 0; sum_6 <= 0; sum_7 <= 0;
                alu_mac_count <= 0;
                mac16_count <= 0;
                active_cluster_chunk_idx <= 0;
            end
        end
    end

endmodule

