module videogen(
  input clk,
  input resetn,

  output [23:0] data,
  output hsync,
  output vsync,
  output data_en
);
  // current target: 640x480 50fps
  // input clk: 25 MHz = 800 * 625 * 50

  // hctr: 800
  logic[9:0] hctr;
  // vctr: 625
  logic[9:0] vctr;

  always_ff @(posedge clk) begin
    if(!resetn) begin
      hctr <= 10'h0;
      vctr <= 10'h0;
    end else begin
      if(hctr == 799) begin
        hctr <= 10'h0;
        if(vctr == 624) begin
          vctr <= 10'h0;
        end else begin
          vctr <= vctr + 10'h1;
        end
      end else begin
        hctr <= hctr + 10'h1;
      end
    end
  end

  logic hblank;
  logic vblank;
  assign hblank = hctr >= 640;
  assign vblank = vctr >= 480;
  assign data_en = ~(hblank || vblank);
  assign hsync = hctr >= 680 && hctr < 760;
  assign vsync = vctr >= 500 && vctr < 600;
  
  localparam W = 640;
  localparam W4 = W / 4;
  localparam W2 = W / 2;
  localparam H = 480;
  localparam H1 = H / 4;
  localparam H2 = H / 2;
  localparam H3 = H * 3 / 4;
  localparam TRISLOPE8 = 12;
  
  logic xsign;
  logic[9:0] xnorm;
  logic[9:0] ynorm;
  always_comb begin
    if(hctr >= W2) begin
      xnorm = hctr - W2;
      xsign = 0;
    end else begin
      xnorm = W2 - hctr;
      xsign = 1;
    end
    ynorm = vctr - H1;
  end
  logic tricutoff;
  assign tricutoff = xnorm * TRISLOPE8 / 8 <= vctr - H1;
  
  logic[7:0] red_dist;
  logic[7:0] green_dist;
  logic[7:0] blue_dist;
  assign green_dist = (W4 * ynorm + H2 * xnorm) * 255 / (W * H / 4);
  assign blue_dist = (W4 * ynorm - H2 * xnorm) * 255 / (W * H / 4);
  assign red_dist = 255 - green_dist - blue_dist;
  always_comb begin
    if(vctr >= H1 && vctr <= H3 && tricutoff) begin
      if(xsign) begin
        data[7:0] = blue_dist;
        data[15:8] = green_dist;
        data[23:16] = red_dist;
      end else begin
        data[7:0] = green_dist;
        data[15:8] = blue_dist;
        data[23:16] = red_dist;
      end
    end else begin
      data[23:0] = 24'h00_00_00;
    end
  end

endmodule