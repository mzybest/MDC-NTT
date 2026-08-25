// Four-lane Montgomery pool shared by mutually exclusive top-level phases.
module peripheral_mont_pool #(
    parameter int QW = 64,
    parameter int MONT_LAT = 14,
    parameter bit USE_WL_MONT = 1'b1
) (
    input  logic          clk,
    input  logic          rst_n,

    input  logic          pre_valid,
    input  logic [QW-1:0] pre_a0,
    input  logic [QW-1:0] pre_a1,
    input  logic [QW-1:0] pre_b0,
    input  logic [QW-1:0] pre_b1,
    input  logic [QW-1:0] pre_factor0,
    input  logic [QW-1:0] pre_factor1,
    output logic          pre_out_valid0,
    output logic          pre_out_valid1,
    output logic          pre_out_valid2,
    output logic          pre_out_valid3,
    output logic [QW-1:0] pre_out0,
    output logic [QW-1:0] pre_out1,
    output logic [QW-1:0] pre_out2,
    output logic [QW-1:0] pre_out3,

    input  logic          point_valid,
    input  logic [QW-1:0] point_a0,
    input  logic [QW-1:0] point_a1,
    input  logic [QW-1:0] point_b0,
    input  logic [QW-1:0] point_b1,
    output logic          point_out_valid0,
    output logic          point_out_valid1,
    output logic [QW-1:0] point_out0,
    output logic [QW-1:0] point_out1,

    input  logic          post_valid,
    input  logic [QW-1:0] post_a0,
    input  logic [QW-1:0] post_a1,
    input  logic [QW-1:0] post_factor0,
    input  logic [QW-1:0] post_factor1,
    output logic          post_out_valid0,
    output logic          post_out_valid1,
    output logic [QW-1:0] post_out0,
    output logic [QW-1:0] post_out1
);
  localparam logic [1:0] OP_PRE = 2'd0;
  localparam logic [1:0] OP_POINT = 2'd1;
  localparam logic [1:0] OP_POST = 2'd2;

  logic request_valid;
  logic [1:0] request_op;
  logic [QW-1:0] mul_a0, mul_a1, mul_a2, mul_a3;
  logic [QW-1:0] mul_b0, mul_b1, mul_b2, mul_b3;
  logic mul_in_valid0, mul_in_valid1, mul_in_valid2, mul_in_valid3;
  logic mul_out_valid0, mul_out_valid1, mul_out_valid2, mul_out_valid3;
  logic [QW-1:0] mul_y0, mul_y1, mul_y2, mul_y3;
  logic op_out_valid;
  logic [1:0] op_out;

  always_comb begin
    request_valid = pre_valid || point_valid || post_valid;
    request_op = OP_PRE;
    mul_in_valid0 = 1'b0;
    mul_in_valid1 = 1'b0;
    mul_in_valid2 = 1'b0;
    mul_in_valid3 = 1'b0;
    mul_a0 = '0;
    mul_a1 = '0;
    mul_a2 = '0;
    mul_a3 = '0;
    mul_b0 = '0;
    mul_b1 = '0;
    mul_b2 = '0;
    mul_b3 = '0;

    if (pre_valid) begin
      request_op = OP_PRE;
      mul_in_valid0 = 1'b1;
      mul_in_valid1 = 1'b1;
      mul_in_valid2 = 1'b1;
      mul_in_valid3 = 1'b1;
      mul_a0 = pre_a0;
      mul_a1 = pre_a1;
      mul_a2 = pre_b0;
      mul_a3 = pre_b1;
      mul_b0 = pre_factor0;
      mul_b1 = pre_factor1;
      mul_b2 = pre_factor0;
      mul_b3 = pre_factor1;
    end else if (point_valid) begin
      request_op = OP_POINT;
      mul_in_valid0 = 1'b1;
      mul_in_valid1 = 1'b1;
      mul_a0 = point_a0;
      mul_a1 = point_a1;
      mul_b0 = point_b0;
      mul_b1 = point_b1;
    end else if (post_valid) begin
      request_op = OP_POST;
      mul_in_valid0 = 1'b1;
      mul_in_valid1 = 1'b1;
      mul_a0 = post_a0;
      mul_a1 = post_a1;
      mul_b0 = post_factor0;
      mul_b1 = post_factor1;
    end
  end

  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_MONT)) u_mul0 (
      .clk(clk), .rst_n(rst_n), .in_valid(mul_in_valid0),
      .a(mul_a0), .b(mul_b0), .out_valid(mul_out_valid0), .y(mul_y0)
  );
  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_MONT)) u_mul1 (
      .clk(clk), .rst_n(rst_n), .in_valid(mul_in_valid1),
      .a(mul_a1), .b(mul_b1), .out_valid(mul_out_valid1), .y(mul_y1)
  );
  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_MONT)) u_mul2 (
      .clk(clk), .rst_n(rst_n), .in_valid(mul_in_valid2),
      .a(mul_a2), .b(mul_b2), .out_valid(mul_out_valid2), .y(mul_y2)
  );
  mont_mul_select #(.QW(QW), .USE_WL_MONT(USE_WL_MONT)) u_mul3 (
      .clk(clk), .rst_n(rst_n), .in_valid(mul_in_valid3),
      .a(mul_a3), .b(mul_b3), .out_valid(mul_out_valid3), .y(mul_y3)
  );

  delay_line #(.DW(2), .DEPTH(MONT_LAT)) u_op_delay (
      .clk(clk), .rst_n(rst_n), .in_valid(request_valid), .din(request_op),
      .out_valid(op_out_valid), .dout(op_out)
  );

  always_comb begin
    pre_out_valid0 = 1'b0;
    pre_out_valid1 = 1'b0;
    pre_out_valid2 = 1'b0;
    pre_out_valid3 = 1'b0;
    point_out_valid0 = 1'b0;
    point_out_valid1 = 1'b0;
    post_out_valid0 = 1'b0;
    post_out_valid1 = 1'b0;
    pre_out0 = mul_y0;
    pre_out1 = mul_y1;
    pre_out2 = mul_y2;
    pre_out3 = mul_y3;
    point_out0 = mul_y0;
    point_out1 = mul_y1;
    post_out0 = mul_y0;
    post_out1 = mul_y1;

    if (op_out_valid) begin
      case (op_out)
        OP_PRE: begin
          pre_out_valid0 = mul_out_valid0;
          pre_out_valid1 = mul_out_valid1;
          pre_out_valid2 = mul_out_valid2;
          pre_out_valid3 = mul_out_valid3;
        end
        OP_POINT: begin
          point_out_valid0 = mul_out_valid0;
          point_out_valid1 = mul_out_valid1;
        end
        OP_POST: begin
          post_out_valid0 = mul_out_valid0;
          post_out_valid1 = mul_out_valid1;
        end
        default: begin end
      endcase
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && ((pre_valid && point_valid) ||
                  (pre_valid && post_valid) ||
                  (point_valid && post_valid)))
      $fatal(1, "peripheral Montgomery pool phase overlap");
    if (rst_n && op_out_valid) begin
      if (!mul_out_valid0 || !mul_out_valid1)
        $fatal(1, "peripheral Montgomery pool tag/data latency mismatch");
      if ((op_out == OP_PRE) && (!mul_out_valid2 || !mul_out_valid3))
        $fatal(1, "peripheral Montgomery pool Pre lane latency mismatch");
      if ((op_out != OP_PRE) && (mul_out_valid2 || mul_out_valid3))
        $fatal(1, "peripheral Montgomery pool idle lane produced valid");
    end
  end
`endif
endmodule
