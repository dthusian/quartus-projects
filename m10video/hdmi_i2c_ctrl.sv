typedef enum {WAITING_PWRON, WAITING_HPD, CONFIGURE, READY, ERR} i2c_state;

// address, mask, value
localparam bit[23:0] adv_config[0:14] = '{
  // required setup (9)
  'h41_40_00,
  'h98_ff_03,
  'h9a_e0_e0,
  'h9c_ff_30,
  'h9d_03_01,
  'ha2_ff_a4,
  'ha3_ff_a4,
  'he0_ff_d0,
  'hf9_ff_00,
  // config (5)
  'h15_0f_00, // RGB 4:4:4 mode
  'h16_b0_30, // 4:4:4 output, 8b per channel
  'h17_02_02, // 16:9 mode
  'h18_80_00, // CSC disable
  'haf_02_02, // HDMI mode
  // extra config (1) (not quickstart)
  'hba_e0_60  // extra delay = 0
};

localparam bit[6:0] i2c_addr = 'h39;

localparam bit[7:0] hpd_register = 8'h42;

/*
I2C register write:
- 1 bit = 3 cycles
- cycle 0
  - start bit: 1b *
  - i2c addr: 7b *
  - w: 1b *
  - sack: 1b *
  - reg addr: 8b *
  - sack: 1b *
  - wait: 5b *
- cycle 24:
  - start bit: 1b *
  - i2c addr: 7b *
  - r: 1b *
  - sack: 1b *
  - reg data: 8b *
  - mack: 1b *
  - stop: 1b *
  - wait: 4b *
- cycle 48:
  - start bit: 1b *
  - i2c addr: 7b *
  - w: 1b *
  - sack: 1b *
  - reg addr: 8b *
  - sack: 1b *
  - reg data: 8b *
  - sack: 1b *
  - stop: 1b *
  - wait: 3b *
- 80 cycles total
*/

module hdmi_i2c_ctrl(
  input logic clk,
  input logic resetn,

  // I2C interface
  input logic sda_in,
  output logic sda_out,
  output logic scl,
  
  // output signals
  output logic waiting_pwron,
  output logic waiting_hpd,
  output logic conf,
  output logic ready,
  output logic err
);
  // general architecture:
  // - first always_ff block controls the cycle counters,
  // - second always_comb block converts cycle counters into i2c output signals
  // - third always_ff block does combinational parts needed for i2c (e.g. reading reg data and acks)
  
  // state
  i2c_state state;
  logic[1:0] clkdiv;
  logic[6:0] xact_ctr;
  logic[7:0] cmd_ctr;
  logic[7:0] input_reg;
  logic set_hpd;
  logic set_err;

  always_ff @(posedge clk) begin
    if(!resetn) begin
      state <= WAITING_PWRON;
      clkdiv <= 0;
      xact_ctr <= 0;
      cmd_ctr <= 0;
    end else if(state == WAITING_PWRON || state == WAITING_HPD || state == CONFIGURE) begin
      if(clkdiv == 'h2) begin
        clkdiv <= 2'b0;
        if((state == WAITING_PWRON && xact_ctr == 127)
          || (state == WAITING_HPD && xact_ctr == 47)
          || (state == CONFIGURE && xact_ctr == 79)) begin
          xact_ctr <= 7'b0;
          if((state == WAITING_PWRON && cmd_ctr == 255)) begin
            cmd_ctr <= 8'b0;
            state <= WAITING_HPD;
          end else if((state == WAITING_HPD && set_hpd)) begin
            cmd_ctr <= 8'b0;
            state <= CONFIGURE;
          end else if(state == CONFIGURE && set_err) begin
            cmd_ctr <= 8'b0;
            state <= ERR;
          end else if((state == CONFIGURE && cmd_ctr == 14)) begin
            cmd_ctr <= 8'b0;
            if(set_err) begin
              state <= ERR;
            end else begin
              state <= READY;
            end
          end else begin
            cmd_ctr <= cmd_ctr + 9'b1;
          end
        end else begin
          xact_ctr <= xact_ctr + 7'b1;
        end
      end else begin
        clkdiv <= clkdiv + 2'b1;
      end
    end
  end
  
  always_comb begin
    if(state == WAITING_PWRON || state == READY || state == ERR) begin
      sda_out <= 1;
      scl <= 1;
    end else if(state == WAITING_HPD || state == CONFIGURE) begin
      // scl
      if(xact_ctr == 0 || xact_ctr == 24 || xact_ctr == 48) begin
        scl <= clkdiv == 0;
      end else if(xact_ctr == 19 || xact_ctr == 43 || xact_ctr == 76) begin
        scl <= clkdiv == 2;
      end else if((xact_ctr >= 20 && xact_ctr < 24)
                || (xact_ctr >= 44 && xact_ctr < 48)
                || (xact_ctr >= 77)) begin
        scl <= 1;
      end else begin
        scl <= clkdiv == 1;
      end
      // sda
      if(xact_ctr == 0 || xact_ctr == 24 || xact_ctr == 48 // start bits
        || xact_ctr == 43 || xact_ctr == 76 // stop bits
        || xact_ctr == 8 || xact_ctr == 56) begin // w bits
        sda_out <= 0;
      end else if((xact_ctr >= 1 && xact_ctr < 8)) begin
        sda_out <= i2c_addr[6 - (xact_ctr - 1)];
      end else if((xact_ctr >= 25 && xact_ctr < 32)) begin
        sda_out <= i2c_addr[6 - (xact_ctr - 25)];
      end else if((xact_ctr >= 49 && xact_ctr < 56)) begin
        sda_out <= i2c_addr[6 - (xact_ctr - 49)];
      end else if((xact_ctr >= 10 && xact_ctr < 18)) begin
        if(state == WAITING_HPD) begin
          sda_out <= hpd_register[7 - (xact_ctr - 10)];
        end else begin
          sda_out <= adv_config[cmd_ctr][7 - (xact_ctr - 10) + 16];
        end
      end else if((xact_ctr >= 58 && xact_ctr < 66)) begin
        sda_out <= adv_config[cmd_ctr][7 - (xact_ctr - 58) + 16];
      end else if((xact_ctr >= 67 && xact_ctr < 75)) begin
        if(adv_config[cmd_ctr][7 - (xact_ctr - 67) + 8]) begin
          sda_out <= adv_config[cmd_ctr][7 - (xact_ctr - 67)];
        end else begin
          sda_out <= input_reg[7 - (xact_ctr - 67)];
        end
      end else begin
        sda_out <= 1;
      end
    end else begin
      sda_out <= 1;
      scl <= 1;
    end
  end
  
  always_ff @(posedge clk) begin
    if(!resetn) begin
      input_reg <= 0;
    end
    if(state == CONFIGURE || state == WAITING_HPD) begin
      if(clkdiv == 0) begin
        if(xact_ctr == 9 || xact_ctr == 18 || xact_ctr == 24+9
          || xact_ctr == 48+9 || xact_ctr == 48+18 || xact_ctr == 48+27) begin
          set_err <= set_err || sda_in;
        end else if(xact_ctr >= 34 || xact_ctr < 42) begin
          input_reg[7 - (xact_ctr - 34)] <= sda_in;
        end
      end
    end else if(state == WAITING_PWRON) begin
      set_err <= 0;
    end
  end
  
  assign set_hpd = input_reg[6];
  assign waiting_pwron = state == WAITING_PWRON;
  assign waiting_hpd = state == WAITING_HPD;
  assign conf = state == CONFIGURE;
  assign ready = state == READY;
  assign err = state == ERR;
  
endmodule