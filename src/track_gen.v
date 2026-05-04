`default_nettype none

module track_gen(
  input  wire [9:0] hpos,
  input  wire [9:0] vpos,
  input  wire       clk,      // clock
  output wire       trkout
);

  reg[6:0] xreg;
  reg[6:0] yreg;
  reg trkcmpy;
  reg trkcapt;

  //wire[5:0] opcode = 6'b011011;   // X_ABS(ix>>3, 40, iy>>3)
  //wire[5:0] opcode = 6'b011011;   // X_ABS(ix>>3, 40, iy>>3)
  reg[5:0] opcode;
  always @* begin
    case (hpos[2:0])
        3'd0: opcode = 6'b011011;   //  ABS   ix>>3,  40,   iy>>3
        3'd1: opcode = 6'b010110;   //  ABS   ry,     30,   rx
        3'd2: opcode = 6'b000010;   //  MSK   ry,     10,   rx
        3'd3: opcode = 6'b10x000;   //  SRT   ry,     rx,   rx
        3'd4: opcode = 6'b01x100;   //  ABS   ry, ~(rx>>1), rx
        3'd5: opcode = 6'bxxxxxx;
        3'd6: opcode = 6'bxxxxxx;
        3'd7: opcode = 6'bxxxxxx;
    endcase
  end

  wire acsel = opcode[0];         // 0:(Y,X)    1:(H/8,V/8)
  wire bsel = opcode[1];          // 0:f(x)     1:40/30/10
  wire[1:0] bval = opcode[3:2];   // 10:40      01:30       00:10
  wire[1:0] mode = opcode[5:4];   // 00:MSK     01:ABS      10:SRT

  // 7'b0101000  40  10
  // 7'b0011110  30  01
  // 7'b0001010  10  00
  //    0AB1Ba0

  // Input values selection + ALU
  wire[6:0] a_in = acsel ? hpos[9:3] : yreg;
  wire[6:0] c_in = acsel ? vpos[9:3] : xreg;
  wire[6:0] b_imm_in = {1'b0, bval[1], bval[0], 1'b1, bval[0], ~bval[1], 1'b0 };  // 40/30/10
  wire[6:0] b_x_in = bval[0] ? {1'b1, ~xreg[6:1]} : xreg;
  wire[6:0] b_in = bsel ? b_imm_in : b_x_in;
  wire[6:0] sub_result = a_in - b_in;
  wire sign = sub_result[6];
  wire nsign = ~sign;

  // X output
  wire xxor = sign & mode[0];                 // ABS:sign  /  MSK:0  /  SRT:any
  wire xmask = (mode[0] | nsign) & ~mode[1];  // ABS:1  /  MSK:nsign  /  SRT:0
  wire[6:0] sub_abs = sub_result[6:0] ^ {xxor,xxor,xxor,xxor,xxor,xxor,xxor};
  wire[6:0] sub_mask = sub_abs[6:0] & {xmask,xmask,xmask,xmask,xmask,xmask,xmask};
  wire[6:0] x_sort = sign ? a_in : b_in;
  wire[6:0] x_out = sub_mask | (x_sort & {mode[1],mode[1],mode[1],mode[1],mode[1],mode[1],mode[1]});

  // Y output
  wire ysel = sign | ~mode[1];
  wire[6:0] y_out = ysel ? c_in : a_in;

  always @(posedge clk) begin
    xreg <= x_out;
    yreg <= y_out;
    trkcmpy <= (y_out[4:2] == 7);
    if(hpos[2:0]==4) begin
      trkcapt <= (x_out[4:3]==0) | trkcmpy;
    end
  end

  assign trkout = trkcapt;

  //// Suppress unused signals warning
  wire _unused_ok_ = &{vpos[2:0]};

endmodule
