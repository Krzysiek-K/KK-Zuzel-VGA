`ifndef HVSYNC_GENERATOR_H
`define HVSYNC_GENERATOR_H

/*
Video sync generator, used to drive a VGA monitor.
Timing from: https://en.wikipedia.org/wiki/Video_Graphics_Array
To use:
- Wire the hsync and vsync signals to top level outputs
- Add a 3-bit (or more) "rgb" output to the top level
*/

module hvsync_generator(clk, reset, hsync, vsync, display_on, hpos, vpos);

  input clk;
  input reset;
  output reg hsync, vsync;
  output display_on;
  output reg [9:0] hpos;
  output reg [9:0] vpos;

  // Fixed 640x480 VGA timing:
  // hmax=799, vmax=524, hsync=656..751, vsync=490..491, display=640x480.
  wire hmax = hpos[9] & hpos[8] & ~hpos[7] & ~hpos[6] & ~hpos[5] & hpos[4] & hpos[3] & hpos[2] & hpos[1] & hpos[0];
  wire vmax = vpos[9] & ~vpos[8] & ~vpos[7] & ~vpos[6] & ~vpos[5] & ~vpos[4] & vpos[3] & vpos[2] & ~vpos[1] & ~vpos[0];
  wire hmaxxed = hmax | reset;	// set when hpos is maximum
  wire vmaxxed = vmax | reset;	// set when vpos is maximum
  wire hsync_region = hpos[9] & ~hpos[8] & hpos[7] & (hpos[6] | hpos[5] | hpos[4]) & ~(hpos[6] & hpos[5] & hpos[4]);
  wire vsync_region = ~vpos[9] & vpos[8] & vpos[7] & vpos[6] & vpos[5] & ~vpos[4] & vpos[3] & ~vpos[2] & vpos[1];
  wire hdisplay = ~hpos[9] | (~hpos[8] & ~hpos[7]);
  wire vdisplay = ~vpos[9] & (~vpos[8] | ~(vpos[7] & vpos[6] & vpos[5]));
  
  // horizontal position counter
  always @(posedge clk)
  begin
    hsync <= ~hsync_region;
    if(hmaxxed)
      hpos <= 0;
    else
      hpos <= hpos + 1;
  end

  // vertical position counter
  always @(posedge clk)
  begin
    vsync <= ~vsync_region;
    if(hmaxxed)
      if (vmaxxed)
        vpos <= 0;
      else
        vpos <= vpos + 1;
  end
  
  // display_on is set when beam is in "safe" visible frame
  assign display_on = hdisplay & vdisplay;

endmodule

`endif
