module frame_buffer
  (
      clock,
      address,
      data,
      cs_ram_n,
      cs_rom_n,
      we_n,
      r,
      g,
      b,
      hsync,
      vsync
   );

   // ================================================================
   // Functions
   // ================================================================

   // Log2 Function to help work out counter widths
   function integer clog2;
      input integer value;
      begin
         value = value - 1;
         for (clog2 = 0; value > 0; clog2 = clog2 + 1)
           value = value >> 1;
      end
   endfunction

   // ================================================================
   // Parameters
   // ================================================================

   // Bus Interface
   parameter BUS_DSIZE       =      8;
   parameter BUS_ASIZE       =     12;
   parameter REG_BASE        =  'hFF0;

   // Character Parameters
   parameter CHAR_W          =      8; // Width of character in pixels
   parameter CHAR_H          =     16; // Height of character in pixels
   parameter CHAR_SET_SIZE   =    256; // Number of characters in the character set

   // Display Parameters
   parameter DISP_W          =     80; // Width of display in characters
   parameter DISP_H          =     25; // Height of display in characters
   parameter DISP_FG_COL     = 3'b111; // RGB of Forground Color (white)
   parameter DISP_BG_COL     = 3'b001; // RGB of Background Color (Blue)
   parameter DISP_BDR_COL    = 3'b010; // RGB of Border Color (Green)

   // Horizontal Video Timing Parameters
   parameter H_ACTIVE        =    640; // Must be >= DISP_W * CHAR_W
   parameter H_FRONT_PORCH   =     16;
   parameter H_SYNC_WIDTH    =     96;
   parameter H_BACK_PORCH    =     48;
   parameter H_SYNC_POLARITY =   1'b1; // 0=positive, 1=negative

   // Vertical Video Timing Parameters
   parameter V_ACTIVE        =    480; // Must be >= DISP_H * CHAR_H
   parameter V_FRONT_PORCH   =     10;
   parameter V_SYNC_WIDTH    =      2;
   parameter V_BACK_PORCH    =     33;
   parameter V_SYNC_POLARITY =   1'b1; // 0=positive, 1=negative

   // ================================================================
   // Internal Parameters
   // ================================================================

   // Video Timing Parameters (derived)
   localparam H_SYNC_START   = H_ACTIVE     + H_FRONT_PORCH;
   localparam H_SYNC_END     = H_SYNC_START + H_SYNC_WIDTH;
   localparam H_TOTAL        = H_SYNC_END   + H_BACK_PORCH;
   localparam V_SYNC_START   = V_ACTIVE     + V_FRONT_PORCH;
   localparam V_SYNC_END     = V_SYNC_START + V_SYNC_WIDTH;
   localparam V_TOTAL        = V_SYNC_END   + V_BACK_PORCH;

   // Display Parameters
   localparam H_START        = (H_ACTIVE - CHAR_W * DISP_W) / 2;
   localparam H_END          = H_START + CHAR_W * DISP_W;
   localparam V_START        = (V_ACTIVE - CHAR_H * DISP_H) / 2;
   localparam V_END          = V_START + CHAR_H * DISP_H;

   // Display RAM Size
   localparam DISP_RAM_DSIZE  = clog2(CHAR_SET_SIZE);
   localparam DISP_RAM_ASIZE  = clog2(DISP_H*DISP_W);

   // Display ROM Size
   localparam DISP_ROM_DSIZE  = BUS_DSIZE;
   localparam DISP_ROM_ASIZE  = BUS_ASIZE - 1;

   // Charater ROM Size
   localparam CHAR_ROM_DSIZE = CHAR_W;
   localparam CHAR_ROM_ASIZE = clog2(CHAR_SET_SIZE) + clog2(CHAR_H);

   // Bus ROM Size
   localparam BUS_ROM_DSIZE  = BUS_DSIZE;
   localparam BUS_ROM_ASIZE  = BUS_ASIZE;

   // Implementation parameters
   localparam VPD            = 5; // Video Pipeline Delay

   // ================================================================
   // Inputs and Outputs
   // ================================================================

   // FPGA board clock (==2x pixel clock)
   input                      clock;

   // Asynchronous bus interface
   input [BUS_ASIZE-1:0]      address;
   inout [BUS_DSIZE-1:0]      data;
   input                      cs_ram_n;
   input                      cs_rom_n;
   input                      we_n;

   // VGA interface
   output reg                 r;
   output reg                 g;
   output reg                 b;
   output reg                 hsync;
   output reg                 vsync;

   // ================================================================
   // Internal Registers
   // ================================================================

   reg                            pix_clken     = 0;
   reg [clog2(      H_TOTAL)-1:0] h_counter     = 0;
   reg [clog2(      V_TOTAL)-1:0] v_counter     = 0;
   reg [clog2(       CHAR_W)-1:0] char_col      = 0;
   reg [clog2(       CHAR_H)-1:0] char_row      = 0;
   reg [clog2(       DISP_W)-1:0] disp_addr_col = 0;
   reg [clog2(       DISP_H)-1:0] disp_addr_row = 0;
   reg [clog2(DISP_H*DISP_W)-1:0] disp_addr     = 0;
   reg [DISP_RAM_DSIZE-1:0]       char          = 0;
   reg [CHAR_W-1:0]               char_data     = 0;
   reg [CHAR_W-1:0]               shift_reg     = 0;
   reg                            blank         = 0;
   reg [VPD-2:0]                  blank_delay   = 0;
   reg                            active        = 0;
   reg [VPD-2:0]                  active_delay  = 0;
   reg [VPD-1:0]                  hsync_delay   = 0;
   reg [VPD-1:0]                  vsync_delay   = 0;
   reg                            wr0           = 0;
   reg                            wr1           = 0;
   reg                            wr2           = 0;
   reg [BUS_ASIZE-1:0]            address0      = 0;
   reg [BUS_ASIZE-1:0]            address1      = 0;
   reg [BUS_ASIZE-1:0]            address2      = 0;
   reg [BUS_DSIZE-1:0]            din0          = 0;
   reg [BUS_DSIZE-1:0]            din1          = 0;
   reg [BUS_DSIZE-1:0]            din2          = 0;
   reg [BUS_DSIZE-1:0]            dout_ram      = 0;
   reg [BUS_DSIZE-1:0]            dout_rom      = 0;
   reg [clog2(       DISP_W)-1:0] cursor_col    = 0;
   reg [clog2(       DISP_H)-1:0] cursor_row    = 0;
   reg                            cursor_en     = 0;

   // ================================================================
   // Internal Block RAM
   // ================================================================

   reg [DISP_RAM_DSIZE-1:0]       disp_ram[0:2**DISP_RAM_ASIZE-1];
   reg [DISP_ROM_DSIZE-1:0]       disp_rom[0:2**DISP_ROM_ASIZE-1];
   reg [CHAR_ROM_DSIZE-1:0]       char_rom[0:2**CHAR_ROM_ASIZE-1];
   reg [ BUS_ROM_DSIZE-1:0]        bus_rom[0:2** BUS_ROM_ASIZE-1];

   initial begin
      // Initialize character ROM
      $readmemh("../src/char_rom.hex", char_rom);

      // Initialize display RAM
      $readmemh("../src/disp_ram.hex", disp_ram);

      // Initialize display ROM
      $readmemh("../src/disp_rom.hex", disp_rom);

      // Initialize bus ROM
      $readmemh("../src/atommc3e_rom.hex", bus_rom);
   end

   // ================================================================
   // Asynchronous Bus Interface for RAM
   // ================================================================

   // This logic assumes the FPGA clock is >> the target system clock
   always @(posedge clock) begin

      // Synchronise the write strobe to the FPGA clock
      wr0 <= (!cs_ram_n && !we_n);
      wr1 <= wr0;
      wr2 <= wr1;

      // Delay the address
      address0 <= address;
      address1 <= address0;
      address2 <= address1;

      // Delay the data
      din0 <= data;
      din1 <= din0;
      din2 <= din1;

      if (address2 == REG_BASE + 0) begin
         if (wr2 && !wr1)
           cursor_en <= din2[6];
         dout_ram <= {1'b0, cursor_en, 6'b0};
      end else if (address2 == REG_BASE + 1) begin
         if (wr2 && !wr1)
           cursor_col <= din2;
         dout_ram <= cursor_col;
      end else if (address2 == REG_BASE + 2) begin
         if (wr2 && !wr1)
           cursor_row <= din2;
         dout_ram <= cursor_row;
      end else if (address2[BUS_ASIZE-1]) begin
         // Display RAM Write (at the end of the write strobe)
         if (wr2 && !wr1)
           disp_ram[address2[DISP_RAM_ASIZE-1:0]] <= din2;
         // Display RAM Read
         dout_ram <= disp_ram[address2[DISP_RAM_ASIZE-1:0]];
      end else begin
         // Display ROM Read
         dout_ram <= disp_rom[address2[DISP_ROM_ASIZE-1:0]];
      end

      dout_rom <= bus_rom[address2];

   end

   // Tristate buffer
   assign data = (!cs_ram_n && we_n) ? dout_ram :
                 (!cs_rom_n && we_n) ? dout_rom :
                 {BUS_DSIZE{1'bz}};

   // ================================================================
   // Main Pixel Pipeline
   // ================================================================

   // A half-speed clock enable for the below pixel pipeline
   always @(posedge clock) begin
      pix_clken <= !pix_clken;
   end

   // The logic clocks at the pixel clock rate
   always @(posedge clock) begin
      if (pix_clken) begin

         // ==================== Pipeline Stage 0 ====================

         // Horizontal Video Counter
         if (h_counter == H_TOTAL - 1)
           h_counter <= 0;
         else
           h_counter <= h_counter + 1'b1;

         // Vertical Video Counter
         if (h_counter == H_TOTAL - 1)
           if (v_counter == V_TOTAL - 1)
             v_counter <= 0;
           else
             v_counter <= v_counter + 1'b1;

         // Video Sync Generation
         {blank,   blank_delay} <= { blank_delay, (h_counter >= H_ACTIVE || v_counter >= V_ACTIVE)};
         {active, active_delay} <= {active_delay, (h_counter >= H_START && h_counter < H_END && v_counter >= V_START && v_counter < V_END)};
         {hsync,   hsync_delay} <= { hsync_delay, (h_counter >= H_SYNC_START && h_counter < H_SYNC_END) ^ H_SYNC_POLARITY};
         {vsync,   vsync_delay} <= { vsync_delay, (v_counter >= V_SYNC_START && v_counter < V_SYNC_END) ^ V_SYNC_POLARITY};

         // ==================== Pipeline Stage 1 ====================

         // Character Col Counter
         if (h_counter == H_START)
           char_col <= 0;
         else if (char_col == CHAR_W - 1)
           char_col <= 0;
         else
           char_col <= char_col + 1'b1;

         // Character Row Counter
         if (h_counter == H_START)
           if (v_counter == V_START)
             char_row <= 0;
           else if (char_row == CHAR_H - 1)
             char_row <= 0;
           else
             char_row <= char_row + 1'b1;

         // Display Column Address Generation
         if (h_counter == H_START)
           disp_addr_col <= 0;
         else if (char_col == CHAR_W - 1)
           disp_addr_col <= disp_addr_col + 1'b1;

         // Display Row Address Generation
         if (h_counter == H_START)
           if (v_counter == V_START)
             disp_addr_row <= 0;
           else if (char_row == CHAR_H - 1)
             disp_addr_row <= disp_addr_row + 1'b1;

         // ==================== Pipeline Stage 2 ====================

         // Display Address Generation
         disp_addr <= disp_addr_row * DISP_W + disp_addr_col;

         // ==================== Pipeline Stage 3 ====================

         // Display Memory Read
         char <= disp_ram[disp_addr] ;

         // ==================== Pipeline Stage 4 ====================

         // Character ROM Read
         char_data <= char_rom[{char, char_row}];

         // ==================== Pipeline Stage 5 ====================

         // Video Shifter
         if (char_col == 3) // delay loading to compensate pipelining
           if (cursor_en && disp_addr_col == cursor_col && disp_addr_row == cursor_row && char_row >= CHAR_H - 2)
             shift_reg <= {CHAR_W{1'b1}};
           else
             shift_reg <= char_data;
         else
           shift_reg <= { shift_reg[CHAR_W-2:0], 1'b0 };

         // ==================== Pipeline Stage 6 ====================

         // RGB Pixel Generation
         if (blank)
           {r, g, b} <= 3'b000; // Blanked
         else if (active)
           if (shift_reg[7])
             {r, g, b} <= DISP_FG_COL; // Active foreground
           else
             {r, g, b} <= DISP_BG_COL; // Active background
         else
           {r, g, b} <= DISP_BDR_COL; // Border

      end
   end

endmodule
