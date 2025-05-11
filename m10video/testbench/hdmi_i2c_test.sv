

module testbench();

  logic clk;
  logic resetn;
  logic sda_in;
  logic sda_out;
  logic scl;
  logic ready;
  logic err;
  
  logic[1:0] ctr = 0;

  hdmi_i2c_ctrl dut(clk, resetn, sda_in, sda_out, scl, ready, err);

  always #1 clk = ~clk;

  initial begin
    clk = 0;
    resetn = 0;
    #6;
    resetn = 1;
  end
  
  always_ff @(posedge scl) begin
    if(ctr == 2'b10) begin
      ctr = 2'b00;
    end else begin
      ctr = ctr + 2'b01;
    end
  end
  assign sda_in = ~ctr[0];
  
endmodule