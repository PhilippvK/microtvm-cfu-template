`timescale 1ns/1ps

// Alternative to cfu.v: compile only one file defining Cfu.
// Implements the multilane CoreDSL ISA. cycles controls MAC phases only:
// cycles = 1/2/4/8 uses 8/4/2/1 signed multipliers per lane (four lanes).
module Cfu #(
    parameter integer cycles = 4
) (
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
    // Keep dimensions valid even for an unsupported parameter, so the
    // time-zero check can report the error instead of dividing by zero.
    localparam VALID_CYCLES =
        (cycles == 1 || cycles == 2 || cycles == 4 || cycles == 8);
    localparam integer MULS_PER_LANE = VALID_CYCLES ? (8 / cycles) : 8;
    localparam [2:0] LAST_PHASE = cycles[2:0] - 3'd1;
    initial begin
        if (!VALID_CYCLES)
            $fatal(1, "Cfu cycles must be 1, 2, 4, or 8");
    end

    localparam [6:0] SET_CODEBOOK_2  = 7'h20;
    localparam [6:0] SET_CODEBOOK_4  = 7'h28;
    localparam [6:0] SET_CODEBOOK_16 = 7'h38;
    localparam [6:0] PUSH_WEIGHTS   = 7'h10;
    localparam [6:0] ALU_MAC        = 7'h40;
    localparam [6:0] ALU_RST        = 7'h48;
    localparam [6:0] MAC_READ       = 7'h50;
    localparam [6:0] DEBUG_DUMP     = 7'h52;
    localparam [6:0] MAC_READ_NO_RESET = 7'h54;

    // One codebook is active at a time. Load it before each microkernel;
    // modes 2 and 4 use only the first 2 and 4 entries, respectively.
    reg signed [7:0] clusters [0:15];
    reg [4:0] last_cluster_num;
    reg signed [7:0] active_clusters [0:3][0:31];
    reg signed [31:0] sums [0:3][0:7];
    reg [1:0] mac_count [0:3];

    // Phase zero runs on acceptance. While busy, phase is the next phase.
    reg busy;
    reg [2:0] phase;
    reg [63:0] saved_activations;
    reg [3:0] saved_lane_mask;
    wire [6:0] funct7 = cmd_payload_function_id[9:3];
    wire [2:0] funct3 = cmd_payload_function_id[2:0];
    wire [1:0] lane = funct3[1:0];
    wire single_lane = !funct3[2];
    reg [3:0] lane_mask;

    always @* begin
        case (funct3)
            3'b000: lane_mask = 4'b0001;
            3'b001: lane_mask = 4'b0010;
            3'b010: lane_mask = 4'b0100;
            3'b011: lane_mask = 4'b1000;
            3'b100: lane_mask = 4'b0011;
            3'b101: lane_mask = 4'b1100;
            3'b110: lane_mask = 4'b1111;
            default: lane_mask = 4'b0000;
        endcase
    end

    assign cmd_ready = !busy && !rsp_valid && !reset;
    wire accept_cmd = cmd_valid && cmd_ready;
    wire [63:0] activations = busy ? saved_activations :
                             {cmd_payload_inputs_1, cmd_payload_inputs_0};
    wire [3:0] mac_mask = busy ? saved_lane_mask : lane_mask;
    // Parameter-selected wiring keeps cycles=1 entirely static and avoids
    // an arithmetic multiplier in the phase/index path.
    wire [2:0] phase_offset = (cycles == 1) ? 3'd0 :
                              !busy ? 3'd0 :
                              (cycles == 2) ? 3'd4 :
                              (cycles == 4) ? {phase[1:0], 1'b0} : phase;
    wire last_phase = (cycles == 1) || (busy && phase == LAST_PHASE);
    wire signed [15:0] products [0:3][0:MULS_PER_LANE-1];

    // Each physical multiplier processes one element per phase. Together
    // the phases cover elements 0..7 exactly once for each enabled lane.
    genvar g_lane, g_mul;
    generate
        for (g_lane = 0; g_lane < 4; g_lane = g_lane + 1) begin : lanes
            for (g_mul = 0; g_mul < MULS_PER_LANE; g_mul = g_mul + 1) begin : multipliers
                wire [2:0] element = phase_offset + g_mul;
                wire [4:0] weight_index = {mac_count[g_lane], element};
                wire signed [7:0] act = activations[element * 8 +: 8];
                wire signed [7:0] weight_value = active_clusters[g_lane][weight_index];
                assign products[g_lane][g_mul] = act * weight_value;
            end
        end
    endgenerate

    wire signed [31:0] lane_sum = sums[lane][0] + sums[lane][1] +
        sums[lane][2] + sums[lane][3] + sums[lane][4] + sums[lane][5] +
        sums[lane][6] + sums[lane][7];
    wire signed [7:0] debug_weight = active_clusters[lane][cmd_payload_inputs_0[4:0]];
    integer i, j;

    always @(posedge clk) begin
        if (reset) begin
            busy <= 0;
            phase <= 0;
            saved_activations <= 0;
            saved_lane_mask <= 0;
            rsp_valid <= 0;
            rsp_payload_outputs_0 <= 0;
            last_cluster_num <= 4;
            for (i = 0; i < 16; i = i + 1) clusters[i] <= 0;
            for (i = 0; i < 4; i = i + 1) begin
                mac_count[i] <= 0;
                for (j = 0; j < 32; j = j + 1) active_clusters[i][j] <= 0;
                for (j = 0; j < 8; j = j + 1) sums[i][j] <= 0;
            end
        end else begin
            if (rsp_valid && rsp_ready)
                rsp_valid <= 0;

            // Keep the weight-group counter fixed until all phases finish.
            if (busy || (accept_cmd && funct7 == ALU_MAC && lane_mask != 0)) begin
                for (i = 0; i < 4; i = i + 1) begin
                    if (mac_mask[i]) begin
                        for (j = 0; j < MULS_PER_LANE; j = j + 1)
                            sums[i][phase_offset + j[2:0]] <= sums[i][phase_offset + j[2:0]] +
                                {{16{products[i][j][15]}}, products[i][j]};
                        // Advance only after all eight products are processed.
                        if (last_phase) begin
                            if (last_cluster_num == 16)
                                mac_count[i] <= {1'b0, ~mac_count[i][0]};
                            else
                                mac_count[i] <= mac_count[i] + 2'd1;
                        end
                    end
                end
                if (last_phase) begin
                    busy <= 0;
                    phase <= 0;
                    rsp_payload_outputs_0 <= 32'hABCD0001;
                    rsp_valid <= 1;
                end else begin
                    busy <= 1;
                    phase <= busy ? phase + 3'd1 : 3'd1;
                    if (!busy) begin
                        saved_activations <= {cmd_payload_inputs_1, cmd_payload_inputs_0};
                        saved_lane_mask <= lane_mask;
                    end
                end
            end else if (accept_cmd) begin
                // All other operations respond at the acceptance edge.
                // Reserved encodings acknowledge zero without changing state.
                rsp_valid <= 1;
                rsp_payload_outputs_0 <= 0;
                case (funct7)
                    SET_CODEBOOK_2: if (funct3 == 0) begin
                        clusters[0] <= $signed(cmd_payload_inputs_0[7:0]);
                        clusters[1] <= $signed(cmd_payload_inputs_0[15:8]);
                        last_cluster_num <= 2;
                        rsp_payload_outputs_0 <= 32'hAABB2202;
                    end
                    SET_CODEBOOK_4: if (funct3 == 0) begin
                        for (j = 0; j < 4; j = j + 1)
                            clusters[j] <= $signed(cmd_payload_inputs_0[j*8 +: 8]);
                        last_cluster_num <= 4;
                        rsp_payload_outputs_0 <= 32'hAABB4404;
                    end
                    SET_CODEBOOK_16: if (funct3 == 0 || funct3 == 1) begin
                        // Explicit low/high halves, with no implicit toggle.
                        for (j = 0; j < 4; j = j + 1) begin
                            clusters[funct3*8 + j] <= $signed(cmd_payload_inputs_0[j*8 +: 8]);
                            clusters[funct3*8 + j + 4] <= $signed(cmd_payload_inputs_1[j*8 +: 8]);
                        end
                        last_cluster_num <= 16;
                        rsp_payload_outputs_0 <= (funct3 == 0) ? 32'hAABB16A0 : 32'hAABB16B1;
                    end
                    PUSH_WEIGHTS: if (single_lane) begin
                        if (last_cluster_num == 2) begin
                            for (j = 0; j < 32; j = j + 1)
                                active_clusters[lane][j] <= clusters[{3'b000, cmd_payload_inputs_0[j]}];
                        end else if (last_cluster_num == 4) begin
                            for (j = 0; j < 16; j = j + 1) begin
                                active_clusters[lane][j] <= clusters[{2'b00, cmd_payload_inputs_0[j*2 +: 2]}];
                                active_clusters[lane][j+16] <= clusters[{2'b00, cmd_payload_inputs_1[j*2 +: 2]}];
                            end
                        end else begin // Mode 16; mode can only be 2, 4 or 16.
                            for (j = 0; j < 8; j = j + 1) begin
                                active_clusters[lane][j] <= clusters[cmd_payload_inputs_0[j*4 +: 4]];
                                active_clusters[lane][j+8] <= clusters[cmd_payload_inputs_1[j*4 +: 4]];
                            end
                            for (j = 16; j < 32; j = j + 1) active_clusters[lane][j] <= 0;
                        end
                        mac_count[lane] <= 0;
                        rsp_payload_outputs_0 <= 32'hDEAD0000;
                    end
                    ALU_RST: begin
                        for (i = 0; i < 4; i = i + 1) begin
                            if (lane_mask[i]) begin
                                mac_count[i] <= 0;
                                for (j = 0; j < 8; j = j + 1) sums[i][j] <= 0;
                            end
                        end
                    end
                    MAC_READ, MAC_READ_NO_RESET: if (single_lane) begin
                        rsp_payload_outputs_0 <= lane_sum;
                        if (funct7 == MAC_READ) begin
                            // Capture the old sum and clear at acceptance, not
                            // when the response is acknowledged by the CPU.
                            mac_count[lane] <= 0;
                            for (j = 0; j < 8; j = j + 1) sums[lane][j] <= 0;
                        end
                    end
                    DEBUG_DUMP: if (single_lane)
                        rsp_payload_outputs_0 <= {{24{debug_weight[7]}}, debug_weight};
                    default: begin end
                endcase
            end
        end
    end
endmodule
