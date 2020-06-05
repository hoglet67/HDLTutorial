`timescale 1ns / 1ps

module frame_buffer_tb();

   reg         clock;
   reg [10:0]  address;
   reg [7:0]   data_in;
   reg         cs_n;
   reg         we_n;
   reg         oe_n;
   wire        r;
   wire        g;
   wire        b;
   wire        hsync;
   wire        vsync;
   wire [7:0]  data;

frame_buffer
   DUT
     (
      .clock(clock),
      .address(address),
      .data(data),
      .cs_n(cs_n),
      .oe_n(oe_n),
      .we_n(we_n),
      .r(r),
      .g(g),
      .b(b),
      .hsync(hsync),
      .vsync(vsync)
      );

   assign data = we_n ? 8'hZZ : data_in;

   initial begin
      clock = 1'b0;

      address = 11'h000;
      data_in = 8'h00;
      cs_n    = 1'b1;
      oe_n    = 1'b1;
      we_n    = 1'b1;

      $dumpvars;

      #(2000 * 1000);

      $finish;

   end

   always
     #10 clock = !clock;

endmodule
