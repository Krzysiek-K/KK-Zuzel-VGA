/*
 * Copyright (c) 2024 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_KK_VGA01(
  input  wire [7:0] ui_in,    // Dedicated inputs
  output wire [7:0] uo_out,   // Dedicated outputs
  input  wire [7:0] uio_in,   // IOs: Input path
  output wire [7:0] uio_out,  // IOs: Output path
  output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
  input  wire       ena,      // always 1 when the design is powered, so you can ignore it
  input  wire       clk,      // clock
  input  wire       rst_n     // reset_n - low to reset
);

  // VGA signals
  wire hsync;
  wire vsync;
  wire [1:0] R;
  wire [1:0] G;
  wire [1:0] B;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  // TinyVGA PMOD
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  // Unused outputs assigned to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;

  // Suppress unused signals warning
  wire _unused_ok = &{ena, ui_in, uio_in};

  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(video_active),
    .hpos(pix_x),
    .vpos(pix_y)
  );

  wire trkon;
  track_gen track(
    .hpos(pix_x),
    .vpos(pix_y),
    .clk(clk),
    .trkout(trkon)
  );

  // verilator lint_off UNOPTFLAT
  wire[14:0] mt_ctrl;
  // verilator lint_on UNOPTFLAT
  motor_handler mctrl(
    .hpos(pix_x),
    .vpos(pix_y),
    .hsync(hsync),
    .vsync(vsync),
    .clk(clk),
    .reset(~rst_n),
    .ctrl(mt_ctrl)
  );

  reg[3:0] steer;
  always @(posedge vsync) begin
    steer <= ui_in[3:0];
  end

  // RESET_Y min/max = 295..456
  wire sp1on, sp2on, sp3on, sp4on;
  motor_core motor1( .RESET_Y(10'd322), .ctrl(mt_ctrl), .clk(clk), .steer(steer[0]), .hpos(pix_x), .vpos(pix_y), .hsync(hsync), .track_in(trkon), .spron(sp1on) );
  motor_core motor2( .RESET_Y(10'd355), .ctrl(mt_ctrl), .clk(clk), .steer(steer[1]), .hpos(pix_x), .vpos(pix_y), .hsync(hsync), .track_in(trkon), .spron(sp2on) );
  motor_core motor3( .RESET_Y(10'd388), .ctrl(mt_ctrl), .clk(clk), .steer(steer[2]), .hpos(pix_x), .vpos(pix_y), .hsync(hsync), .track_in(trkon), .spron(sp3on) );
  motor_core motor4( .RESET_Y(10'd421), .ctrl(mt_ctrl), .clk(clk), .steer(steer[3]), .hpos(pix_x), .vpos(pix_y), .hsync(hsync), .track_in(trkon), .spron(sp4on) );

  wire mR = sp1on | sp4on;
  wire mG1 = sp2on | sp3on | sp4on;
  wire mG0 = sp2on | sp4on;
  wire mB = sp3on;
  // 1001xxxxx
  // 1010
  // 10011xxxx
  // 10100xxxx
  //wire goalmsk = pix_y[8] & ~trkon & pix_x[8] & ~pix_x[7] & (pix_x[5] ^ pix_x[6]);
  wire goalmsk = pix_y[8] & ~trkon & pix_x[8] & ~pix_x[7] & (pix_x[6] ^ pix_x[5]) & (pix_x[6] ^ pix_x[4]);
  wire goal = goalmsk & (pix_x[3] ^ pix_y[3]);
  assign R = video_active ? {mR, mR|goal} : 2'b00;
  assign G = video_active ? {mG1, mG0|trkon|goal} : 2'b00;
  assign B = video_active ? {mB, mB|goal} : 2'b00;
  
  // Suppress unused signals warning
  //wire _unused_ok_ = &{moving_x, pix_y};

endmodule
