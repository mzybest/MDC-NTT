// 64x64 integer multiplier tiled to Xilinx-style 24x17 DSP shapes.
// Latency is 4 cycles in the local valid-pipeline convention.
module intmul_64x64_24x17 (
    input  logic          clk,
    input  logic          rst_n,
    input  logic [63:0]   a,
    input  logic [63:0]   b,
    output logic [127:0]  p
);
  logic [23:0] a0, a1, a2;
  logic [16:0] b0, b1, b2, b3;

  (* use_dsp = "yes" *) logic [40:0] p00_s1, p01_s1, p02_s1;
  (* use_dsp = "yes" *) logic [40:0] p10_s1, p11_s1, p12_s1;
  (* use_dsp = "yes" *) logic [40:0] p20_s1, p21_s1, p22_s1;
  (* use_dsp = "yes" *) logic [40:0] p30_s1, p31_s1, p32_s1;

  logic [127:0] sum0_s2, sum1_s2, sum2_s2, sum3_s2;
  logic [127:0] sum01_s3, sum23_s3;

  assign a0 = a[23:0];
  assign a1 = a[47:24];
  assign a2 = {8'b0, a[63:48]};

  assign b0 = b[16:0];
  assign b1 = b[33:17];
  assign b2 = b[50:34];
  assign b3 = {4'b0, b[63:51]};

  function automatic logic [127:0] sh_pp(
      input logic [40:0] pp,
      input int unsigned sh
  );
    sh_pp = ({87'b0, pp} << sh);
  endfunction

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      p00_s1 <= '0; p01_s1 <= '0; p02_s1 <= '0;
      p10_s1 <= '0; p11_s1 <= '0; p12_s1 <= '0;
      p20_s1 <= '0; p21_s1 <= '0; p22_s1 <= '0;
      p30_s1 <= '0; p31_s1 <= '0; p32_s1 <= '0;
      sum0_s2 <= '0; sum1_s2 <= '0; sum2_s2 <= '0; sum3_s2 <= '0;
      sum01_s3 <= '0; sum23_s3 <= '0;
      p <= '0;
    end else begin
      p00_s1 <= a0 * b0;
      p01_s1 <= a1 * b0;
      p02_s1 <= a2 * b0;

      p10_s1 <= a0 * b1;
      p11_s1 <= a1 * b1;
      p12_s1 <= a2 * b1;

      p20_s1 <= a0 * b2;
      p21_s1 <= a1 * b2;
      p22_s1 <= a2 * b2;

      p30_s1 <= a0 * b3;
      p31_s1 <= a1 * b3;
      p32_s1 <= a2 * b3;

      sum0_s2 <= sh_pp(p00_s1, 0)  + sh_pp(p01_s1, 24) + sh_pp(p02_s1, 48);
      sum1_s2 <= sh_pp(p10_s1, 17) + sh_pp(p11_s1, 41) + sh_pp(p12_s1, 65);
      sum2_s2 <= sh_pp(p20_s1, 34) + sh_pp(p21_s1, 58) + sh_pp(p22_s1, 82);
      sum3_s2 <= sh_pp(p30_s1, 51) + sh_pp(p31_s1, 75) + sh_pp(p32_s1, 99);

      sum01_s3 <= sum0_s2 + sum1_s2;
      sum23_s3 <= sum2_s2 + sum3_s2;
      p <= sum01_s3 + sum23_s3;
    end
  end
endmodule
