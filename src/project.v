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
  assign uio_out = 8'b00000000;
  assign uio_oe  = 8'b00000000;

  wire [1:0] game_track = uio_in[1:0];
  wire [1:0] game_speed = uio_in[3:2];

  wire hard_reset = ~rst_n;
  wire user_reset = ui_in[4];
  wire gameplay_reset = hard_reset | user_reset;

  // Suppress unused signals warning
  wire _unused_ok = &{ena, ui_in[7:5], uio_in[7:4]};

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
    .game_track(game_track),
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
    .reset(gameplay_reset),
    .game_speed(game_speed),
    .ctrl(mt_ctrl)
  );

  reg[3:0] steer;
  always @(posedge vsync) begin
    steer <= ui_in[3:0];
  end

  wire gt0 = game_track[0];
  wire gt1 = game_track[1];
  wire gt_or   = gt1 | gt0;
  wire gt_and  = gt1 & gt0;
  wire gt_xor  = gt1 ^ gt0;
  wire gt_xnor = ~gt_xor;
  wire gt_nor  = ~gt_or;
  wire ngt0 = ~gt0;
  wire ngt1 = ~gt1;

  wire [9:0] reset_y1 = {1'b0, 1'b1, 1'b0,  ~gt_and, gt_xnor, gt0,  4'b0000};
  wire [9:0] reset_y2 = {1'b0, 1'b1, 1'b0,   1'b1,   ngt1,    ngt0, 4'b0000};
  wire [9:0] reset_y3 = {1'b0, 1'b1, gt_nor, gt_or,  gt_xor,  gt0,  4'b0000};
  wire [9:0] reset_y4 = {1'b0, 1'b1, ngt1,   gt1,    gt1,     ngt0, 4'b0000};

  wire sp1on, sp2on, sp3on, sp4on;
  motor_core motor1( .RESET_Y(reset_y1), .game_speed(game_speed), .ctrl(mt_ctrl), .clk(clk), .steer(steer[0]), .hpos(pix_x), .vpos(pix_y), .hsync(hsync), .track_in(trkon), .spron(sp1on) );
  motor_core motor2( .RESET_Y(reset_y2), .game_speed(game_speed), .ctrl(mt_ctrl), .clk(clk), .steer(steer[1]), .hpos(pix_x), .vpos(pix_y), .hsync(hsync), .track_in(trkon), .spron(sp2on) );
  motor_core motor3( .RESET_Y(reset_y3), .game_speed(game_speed), .ctrl(mt_ctrl), .clk(clk), .steer(steer[2]), .hpos(pix_x), .vpos(pix_y), .hsync(hsync), .track_in(trkon), .spron(sp3on) );
  motor_core motor4( .RESET_Y(reset_y4), .game_speed(game_speed), .ctrl(mt_ctrl), .clk(clk), .steer(steer[3]), .hpos(pix_x), .vpos(pix_y), .hsync(hsync), .track_in(trkon), .spron(sp4on) );

  reg[3:0] moto_arm;
  reg[3:0] moto_lead;
  wire armwin = pix_y[8] & pix_x[8] & pix_x[7];
  wire[3:0] armsig = {4{armwin}} & {sp4on,sp3on,sp2on,sp1on};
  wire[3:0] leadsig = {4{goalmsk}} & moto_arm & {sp4on,sp3on,sp2on,sp1on};
  wire nr = ~mt_ctrl[0]; // ~reset
  wire setlead = |{leadsig};
  wire lead_arm_mask = nr & ~setlead;
  always @(posedge clk) begin
    moto_lead <= (moto_lead & {4{lead_arm_mask}}) | leadsig;
    moto_arm <= (moto_arm | armsig) & {4{lead_arm_mask}};
  end

  wire p1on = sp1on | (goal & moto_lead[0]);
  wire p2on = sp2on | (goal & moto_lead[1]);
  wire p3on = sp3on | (goal & moto_lead[2]);
  wire p4on = sp4on | (goal & moto_lead[3]);

  wire mR = p1on | p4on;
  wire mG1 = p2on | p3on | p4on;
  wire mG0 = p2on | p4on;
  wire mB = p3on;
  // 1001xxxxx
  // 1010
  // 10011xxxx
  // 10100xxxx
  //wire goalmsk = pix_y[8] & ~trkon & pix_x[8] & ~pix_x[7] & (pix_x[5] ^ pix_x[6]);
  wire goalmsk = pix_y[8] & ~trkon & pix_x[8] & ~pix_x[7] & (pix_x[6] ^ pix_x[5]) & (pix_x[6] ^ pix_x[4]);
  wire goal = goalmsk & (pix_x[3] ^ pix_y[3]) & mt_ctrl[14];  // ... & deathmsk
  wire mGr = goal & ~|{moto_lead};
  assign R = {2{video_active}} & {mR, mR|goal};
  assign G = {2{video_active}} & {mG1, mG0|trkon|mGr};
  assign B = {2{video_active}} & {mB, mB|goal};
  
  // Suppress unused signals warning
  wire _unused_ok_ = &{uio_in};

endmodule
