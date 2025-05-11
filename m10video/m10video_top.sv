module open_drain_pin(
  inout pin,
  output data_in,
  input data_out
);
assign pin = data_out ? 1'bZ : 1'b0;
assign data_in = pin;
endmodule

module clkdiv256(
  input logic clk_in,
  output logic clk_out
);
  logic[7:0] ctr;
  assign clk_out = ctr[7];
  always_ff @(posedge clk_in) begin
    ctr <= ctr + 8'b1;
  end
endmodule

module clkdiv2(
  input logic clk_in,
  output logic clk_out
);
  logic clk;
  assign clk_out = clk;
  always_ff @(posedge clk_in) begin
    clk = ~clk;
  end
endmodule

module m10video_top(
  //Reset and Clocks
  input           max10_resetn,
  input           clk50m_max10,
  input           clk100m_lpddr2,
  
  //User IO: LED/PB/DIPSW
  inout  [9:0]    user_io,
  output [4:0]    user_led,
  input  [3:0]    user_pb,
  input  [5:0]    user_dipsw,

  //HDMI TX
  output          hdmi_video_clk,
  output [23:0]   hdmi_video_din,
  output          hdmi_hsync,
  output          hdmi_vsync,
  output          hdmi_video_data_en,
  input           hdmi_intr,
  inout           hdmi_sda,
  output          hdmi_scl
);

  // SDA in/out buffer
  logic sda_in;
  logic sda_out;
  open_drain_pin sda_opendrain(.pin(hdmi_sda), .data_in(sda_in), .data_out(sda_out));

  // ADV7513 I2C controller
  logic hdmi_ready;
  logic hdmi_err;
  logic hdmi_conf;
  logic hdmi_waiting_hpd;
  logic hdmi_waiting_pwron;
  logic i2c_clk;
  clkdiv256 i2c_clkgen(clk50m_max10, i2c_clk);
  hdmi_i2c_ctrl i2c_ctrl(
    .clk(i2c_clk),
    .resetn(max10_resetn),
    .sda_in(sda_in),
    .sda_out(sda_out),
    .scl(hdmi_scl),
    .waiting_pwron(hdmi_waiting_pwron),
    .waiting_hpd(hdmi_waiting_hpd),
    .conf(hdmi_conf),
    .ready(hdmi_ready),
    .err(hdmi_err)
  );
  assign user_led[0] = ~hdmi_err;
  assign user_led[1] = ~hdmi_ready;
  assign user_led[2] = ~hdmi_conf;
  assign user_led[3] = ~hdmi_waiting_hpd;
  assign user_led[4] = ~hdmi_waiting_pwron;

  // Video Generator
  logic vid_clk;
  clkdiv2 vid_clkgen(clk50m_max10, vid_clk);
  videogen vid_gen(
    .clk(vid_clk),
    .resetn(max10_resetn && hdmi_ready),
    .data(hdmi_video_din),
    .hsync(hdmi_hsync),
    .vsync(hdmi_vsync),
    .data_en(hdmi_video_data_en)
  );
  assign hdmi_video_clk = vid_clk;
endmodule