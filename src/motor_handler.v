

// DXY operation
//
//  x7 x6 x5 x4 x3 x2 x1 x0 y7 y6 y5 y4 y3 y2 y1 y0
//        || cc                                  vv
//  x7 x6 x5 x4 x3 x2 x1 x0 y7 y6 y5 y4 y3 y2 y1 y0     011   y0-x5-x4  (start)
//  Y0 x7 x6 x5 x4 x3 x2 x1 x0 y7 y6 y5 y4 y3 y2 y1     010   y1-x6-C
//  Y1 Y0 x7 x6 x5 x4 x3 x2 x1 x0 y7 y6 y5 y4 y3 y2     010   y2-x7-C       E<=x7
//  Y2 Y1 Y0 x7 x6 x5 x4 x3 x2 x1 x0 y7 y6 y5 y4 y3     110   y3-E-C
//  Y3 y2 y1 y0 x7 x6 x5 x4 x3 x2 x1 x0 y7 y6 y5 y4     110   y4-E-C
//  Y4 Y3 Y2 Y1 Y0 x7 x6 x5 x4 x3 x2 x1 x0 y7 y6 y5     110   y5-E-C
//  Y5 Y4 Y3 Y2 Y1 Y0 x7 x6 x5 x4 x3 x2 x1 x0 y7 y6     110   y6-E-C
//  Y6 Y5 Y4 Y3 Y2 Y1 Y0 x7 x6 x5 x4 x3 x2 x1 x0 y7     110   y7-E-C
//  Y7 Y6 Y5 Y4 Y3 Y2 Y1 Y0 x7 x6 x5 x4 x3 x2 x1 x0     001   x0+Y5+Y4  (start)
//  X0 Y7 Y6 Y5 Y4 Y3 Y2 Y1 Y0 x7 x6 x5 x4 x3 x2 x1     000   x1+Y6+C
//  X1 X0 Y7 Y6 Y5 Y4 Y3 Y2 Y1 Y0 x7 x6 x5 x4 x3 x2     000   x2+Y7+C       E<=Y7
//  X2 X1 X0 Y7 Y6 Y5 Y4 Y3 Y2 Y1 Y0 x7 x6 x5 x4 x3     100   x3+E+C 
//  X3 X2 X1 X0 Y7 Y6 Y5 Y4 Y3 Y2 Y1 Y0 x7 x6 x5 x4     100   x4+E+C 
//  X4 X3 X2 X1 X0 Y7 Y6 Y5 Y4 Y3 Y2 Y1 Y0 x7 x6 x5     100   x5+E+C 
//  X5 X4 X3 X2 X1 X0 Y7 Y6 Y5 Y4 Y3 Y2 Y1 Y0 x7 x6     100   x6+E+C 
//  X6 X5 X4 X3 X2 X1 X0 Y7 Y6 Y5 Y4 Y3 Y2 Y1 Y0 x7     100   x7+E+C 
//  X7 X6 X5 X4 X3 X2 X1 X0 Y7 Y6 Y5 Y4 Y3 Y2 Y1 Y0               (end state)
//

module motor_handler(
  input wire[9:0]   hpos,
  input wire[9:0]   vpos,
  input wire        hsync,
  input wire        vsync,
  input wire        clk,
  input wire        reset,
  input wire[1:0]   game_speed,
  output wire[14:0] ctrl
);
  reg[1:0] reshold;
  always @(posedge vsync) begin
    reshold <= {reshold[0]|reset, reset};
  end

  // vpos       hpos
  // 9876543210 9876543210
  // 011110101_ __________  VSYNC
  // 1000001100 1100011111  MAX
  // 1000000000 0000sssstt  s:dxystep   t:dxytick
  // 10000001ii 0iissssstt  i:movidx    s:movstep   t:movtick
  // 1000000001 0__ssssstt  s:movstep   t:movtick             (test)
  //
  reg turn_frame;
  wire turn_15x = game_speed[1] & ~game_speed[0];
  wire turn_2x = game_speed[1] & game_speed[0];
  wire extra_turn_pass = turn_2x | (turn_15x & turn_frame);
  wire dxyen = vpos[9] & ~|{vpos[8:1],hpos[9:6]} & (~vpos[0] | extra_turn_pass);
  wire[3:0] dxystep = hpos[5:2];
  //wire moven = vpos[9] & ~|{vpos[8:1]} & vpos[0] & ~|{hpos[9]};   //(test)
  wire moven = vpos[9] & ~|{vpos[8:3],hpos[9]} & vpos[2];
  wire[4:0] movstep = hpos[6:2];
  wire[3:0] movidx = {vpos[1:0],hpos[8:7]};
  wire[3:0] movgate = {movidx[3], ~movidx[3] & movidx[2], ~|{movidx[3:2]} & movidx[1], ~|{movidx[3:1]} & movidx[0]};
  reg dxyclk;
  reg movclk;
  reg[1:0] spdcnt;

  reg[2:0] movop;
  always @* begin
    case (movstep[4:0])
        5'b00000: movop = 3'b011;
        5'b00001: movop = 3'b001;
        5'b00010: movop = 3'b001;
        5'b00011: movop = 3'b001;
        5'b00100: movop = 3'b001;
        5'b00101: movop = 3'b101;
        5'b00110: movop = 3'b101;
        5'b00111: movop = 3'b101;
        5'b01000: movop = 3'b100;
        5'b01001: movop = 3'b100;
        5'b01010: movop = 3'b100;
        5'b01011: movop = 3'b100;
        5'b01100: movop = 3'b100;
        5'b01101: movop = 3'b011;
        5'b01110: movop = 3'b001;
        5'b01111: movop = 3'b001;
        5'b10000: movop = 3'b001;
        5'b10001: movop = 3'b001;
        5'b10010: movop = 3'b101;
        5'b10011: movop = 3'b101;
        5'b10100: movop = 3'b101;
        5'b10101: movop = 3'b100;
        5'b10110: movop = 3'b100;
        5'b10111: movop = 3'b100;
        5'b11000: movop = 3'b100;
        5'b11001: movop = 3'b100;
        5'b11010: movop = 3'b100;
        5'b11011: movop = 3'bxxx;        
        5'b11100: movop = 3'bxxx;        
        5'b11101: movop = 3'bxxx;        
        5'b11110: movop = 3'bxxx;        
        5'b11111: movop = 3'bxxx;        
    endcase
  end  

  always @(posedge clk) begin
    dxyclk <= (dxyen | (moven & movop[0]) ) & (hpos[1:0]==2);
    movclk <= moven & (movstep<27) & (hpos[1:0]==2);
  end
  always @(posedge vsync) begin
    spdcnt <= {spdcnt[0], ~spdcnt[1]};
    turn_frame <= ~turn_frame;
  end
  wire speed_clk = turn_2x ? vsync : spdcnt[1];

  assign ctrl = {
    hpos[0] ^ vpos[0],                      // [14] deathmask
    speed_clk,                              // [13] spdclk
    movgate,                                // [12:9] mov index
    movop[2],                               // [8] mov echo
    movop[1],                               // [7] mov start
    movclk,                                 // [6] movclk
    dxyen,                                  // [5] dxy mask
    dxystep[2] | (dxystep[1] & dxystep[0]), // [4] dxy echo
    ~dxystep[3],                            // [3] dxy SUB
    ~|{dxystep[2:0]},                       // [2] dxy start
    dxyclk,                                 // [1] dxyclk
    |{reshold}                              // [0] reset
  };

  // Suppress unused signals warning
  wire _unused_ok_ = &{hsync};

endmodule
