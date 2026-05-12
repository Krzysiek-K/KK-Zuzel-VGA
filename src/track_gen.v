`default_nettype none

module track_gen(
  input  wire [9:0] hpos,
  input  wire [9:0] vpos,
  input  wire       clk,      // clock
  input  wire [1:0] game_track,
  output wire       trkout
);

  reg[5:0] xreg;
  reg[5:0] yreg;
  reg trkcmpy;
  reg trkcapt;

  wire gt0 = game_track[0];
  wire gt1 = game_track[1];

  reg[6:0] opcode;
  always @* begin
    case (hpos[2:0])
        3'd0: opcode = 7'b01_100_1_1;                 //  ABS   ix>>3,  40,   iy>>3
        3'd1: opcode = 7'b01_101_1_0;                 //  ABS   ry,     30,   rx
        3'd2: opcode = {2'b00, 1'b0, game_track, 2'b10}; //  MSK   ry,     track, rx
        3'd3: opcode = 7'b10_xx0_0_0;                 //  SRT   ry,     rx,   rx
        3'd4: opcode = 7'b01_xx1_0_0;                 //  ABS   ry, ~(rx>>1), rx
        3'd5: opcode = 7'bxx_xxx_x_x;
        3'd6: opcode = 7'bxx_xxx_x_x;
        3'd7: opcode = 7'bxx_xxx_x_x;
    endcase
  end

  wire acsel = opcode[0];         // 0:(Y,X)    1:(H/8,V/8)
  wire bsel = opcode[1];          // 0:f(x)     1:imm
  wire xsrc = opcode[2];          // 0:rx       1:~(rx>>1)
  wire[2:0] imm_sel = opcode[4:2];
  wire[1:0] mode = opcode[6:5];   // 00:MSK     01:ABS      10:SRT

  wire imm20 = imm_sel[2] & imm_sel[0];
  wire imm2n0 = imm_sel[2] & ~imm_sel[0];

  // Input values selection + ALU
  wire[6:0] a_in = acsel ? hpos[9:3] : {1'b0, yreg};
  wire[5:0] c_in = acsel ? vpos[8:3] : xreg;
  wire[6:0] b_imm_in = {1'b0, imm2n0, imm_sel[1] | imm20, ~imm_sel[1], imm_sel[0], ~imm2n0, imm_sel[1]};
  wire[6:0] b_x_in = xsrc ? {2'b11, ~xreg[5:1]} : {1'b0, xreg};
  wire[6:0] b_in = bsel ? b_imm_in : b_x_in;
  wire[6:0] sub_result = a_in - b_in;
  wire sign = sub_result[6];
  wire nsign = ~sign;

  // X output
  wire xxor = sign & mode[0];                 // ABS:sign  /  MSK:0  /  SRT:any
  wire xmask = (mode[0] | nsign) & ~mode[1];  // ABS:1  /  MSK:nsign  /  SRT:0
  wire[5:0] sub_abs = sub_result[5:0] ^ {xxor,xxor,xxor,xxor,xxor,xxor};
  wire[5:0] sub_mask = sub_abs & {xmask,xmask,xmask,xmask,xmask,xmask};
  wire[5:0] x_sort = sign ? a_in[5:0] : b_in[5:0];
  wire[5:0] x_out = sub_mask | (x_sort & {mode[1],mode[1],mode[1],mode[1],mode[1],mode[1]});

  // Y output
  wire ysel = sign | ~mode[1];
  wire[5:0] y_out = ysel ? c_in : a_in[5:0];
  wire y_eq_7_or_6 = y_out[4] & y_out[3] & (y_out[2] ^ gt0);
  wire y_ge_16_or_20 = y_out[5] | (y_out[4] & (gt0 | y_out[3] | y_out[2]));
  wire trkcmpy_next = gt1 ? y_ge_16_or_20 : y_eq_7_or_6;

  wire cmp_x_edge = x_out[4:3] == 2'b00;
  wire cmp_x_outer24 = (gt1 | gt0) & (x_out[5] | (x_out[4] & x_out[3]));
  wire cmp_x_outer11 = gt1 & gt0 & x_out[4] & x_out[2];

  always @(posedge clk) begin
    xreg <= x_out;
    yreg <= y_out;
    trkcmpy <= trkcmpy_next;
    if(hpos[2:0]==4) begin
      trkcapt <= cmp_x_edge | trkcmpy | cmp_x_outer24 | cmp_x_outer11;
    end
  end

  assign trkout = trkcapt;

  //// Suppress unused signals warning
  wire _unused_ok_ = &{vpos[9], vpos[2:0]};

endmodule
