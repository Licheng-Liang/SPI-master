///////////////////////////////////////////////////////////////////////////////

// Description: SPI (Serial Peripheral Interface) Master

//              Creates master based on input configuration.

//              Sends a byte one bit at a time on MOSI

//              Will also receive byte data one bit at a time on MISO.

//              Any data on input byte will be shipped out on MOSI.

//              To kick-off transaction, user must pulse i_TX_DV.

//              This module supports multi-byte transmissions by pulsing

//              i_TX_DV and loading up i_TX_Byte when o_TX_Ready is high.

//

//              This module is only responsible for controlling Clk, MOSI, 

//              and MISO.  If the SPI peripheral requires a chip-select, 

//              this must be done at a higher level.

//

// Note:        i_Clk must be at least 2x faster than i_SPI_Clk

//

// Parameters:  SPI_MODE, can be 0, 1, 2, or 3.  See above.

//              Can be configured in one of 4 modes:

//              Mode | Clock Polarity (CPOL/CKP) | Clock Phase (CPHA)

//               0   |             0             |        0

//               1   |             0             |        1

//               2   |             1             |        0

//               3   |             1             |        1

//              More: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface_Bus#Mode_numbers

//              CLKS_PER_HALF_BIT - Sets frequency of o_SPI_Clk.  o_SPI_Clk is

//              derived from i_Clk.  Set to integer number of clocks for each

//              half-bit of SPI data.  E.g. 100 MHz i_Clk, CLKS_PER_HALF_BIT = 2

//              would create o_SPI_CLK of 25 MHz.  Must be >= 2

//

///////////////////////////////////////////////////////////////////////////////



module SPI_Master

  #(parameter SPI_MODE = 0,  //这里用的是模式0,在例化时可通过传入参数来改变模式

    parameter CLKS_PER_HALF_BIT = 2)

  (
   // Control/Data Signals,
   input        i_Rst_L,     // FPGA Reset
   input        i_Clk,       // FPGA Clock

   // TX (MOSI) Signals
    input [7:0]  i_TX_Byte,        // Byte to transmit on MOSI//存储输入控制序列（8个比特）
    input        i_TX_DV,          // Data Valid Pulse with i_TX_Byte//输入控制位

   output reg   o_TX_Ready,       // Transmit Ready for next byte//等待下一输入
    
   // RX (MISO) Signals
   output reg       o_RX_DV,     // Data Valid pulse (1 clock cycle)//输出控制位
   output reg [7:0] o_RX_Byte,  // Byte received on MISO//输出数据(8个比特）

   // SPI Interface
   output reg o_SPI_Clk,//SPI时钟
   input      i_SPI_MISO,//SPI输入数据（1个比特）
   output reg o_SPI_MOSI//SPI输出数据（1个比特）
   );

  // SPI Interface (All Runs at SPI Clock Domain) //SPI工作模式
  wire w_CPOL;     // Clock polarity
  wire w_CPHA;     // Clock phase

  reg [$clog2(CLKS_PER_HALF_BIT*2)-1:0] r_SPI_Clk_Count;  //SPI时钟计数器

  reg r_SPI_Clk;

  reg [4:0] r_SPI_Clk_Edges;  

  reg r_Leading_Edge;  //上升沿

  reg r_Trailing_Edge;  //下降沿

  reg       r_TX_DV;   //发射允许脉冲

  reg [7:0] r_TX_Byte;  //发射数据



  reg [2:0] r_RX_Bit_Count;  //接收数据计数

  reg [2:0] r_TX_Bit_Count;  //发射数据计数



  // CPOL: Clock Polarity

  // CPOL=0 means clock idles at 0, leading edge is rising edge.

  // CPOL=1 means clock idles at 1, leading edge is falling edge.

  assign w_CPOL  = (SPI_MODE == 2) | (SPI_MODE == 3); 



  // CPHA: Clock Phase

  // CPHA=0 means the "out" side changes the data on trailing edge of clock

  //              the "in" side captures data on leading edge of clock

  // CPHA=1 means the "out" side changes the data on leading edge of clock

  //              the "in" side captures data on the trailing edge of clock

  assign w_CPHA  = (SPI_MODE == 1) | (SPI_MODE == 3);







  // Purpose: Generate SPI Clock correct number of times when DV pulse comes
  //产生SPI时钟信号，并记录时钟的边沿
  always @(posedge i_Clk or negedge i_Rst_L)

  begin

    if (~i_Rst_L)
    begin
      o_TX_Ready      <= 1'b0;
      r_SPI_Clk_Edges <= 0;
      r_Leading_Edge  <= 1'b0;
      r_Trailing_Edge <= 1'b0;
      r_SPI_Clk       <= w_CPOL; // assign default state to idle state
      r_SPI_Clk_Count <= 0;
    end

    else
    begin
      // Default assignments

      r_Leading_Edge  <= 1'b0;

      r_Trailing_Edge <= 1'b0;
    
      if (i_TX_DV)//发送控制位来到
      begin

        o_TX_Ready      <= 1'b0;

        r_SPI_Clk_Edges <= 16;  // Total # edges in one byte ALWAYS 16  //8个时钟周期一共有16个边沿

      end

      else if (r_SPI_Clk_Edges > 0)
      begin

        o_TX_Ready <= 1'b0;

        if (r_SPI_Clk_Count == CLKS_PER_HALF_BIT*2-1)  //一个SPI时钟周期
        begin

          r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 1;    //时钟沿减一

          r_Trailing_Edge <= 1'b1;   //此时为下降沿

          r_SPI_Clk_Count <= 0;    //一个周期结束，计数器置0

          r_SPI_Clk       <= ~r_SPI_Clk;  //时钟翻转

        end

        else if (r_SPI_Clk_Count == CLKS_PER_HALF_BIT-1)  //半个SPI时钟周期

        begin

          r_SPI_Clk_Edges <= r_SPI_Clk_Edges - 1;  //时钟沿减一

          r_Leading_Edge  <= 1'b1;  //此时为上升沿

          r_SPI_Clk_Count <= r_SPI_Clk_Count + 1;  //还未到一个周期，计数器继续加1

          r_SPI_Clk       <= ~r_SPI_Clk;

        end

        else

        begin

          r_SPI_Clk_Count <= r_SPI_Clk_Count + 1;  //计数器加1（在 r_SPI_Clk_Count = 0 或 2时也能执行加1）

        end

      end  

      else
      begin

        o_TX_Ready <= 1'b1;              

      end

    end // else: !if(~i_Rst_L)

  end // always @ (posedge i_Clk or negedge i_Rst_L)



  // Purpose: Register i_TX_Byte when Data Valid is pulsed.
  // Keeps local storage of byte in case higher level module changes the data

  always @(posedge i_Clk or negedge i_Rst_L)
  begin

    if (~i_Rst_L)
    begin
      r_TX_Byte <= 8'h00;
      r_TX_DV   <= 1'b0;
    end

    else
      begin

        r_TX_DV <= i_TX_DV; // 1 clock cycle delay

        if (i_TX_DV)//发送控制位到来
        begin

          r_TX_Byte <= i_TX_Byte;

        end

      end // else: !if(~i_Rst_L)

  end // always @ (posedge i_Clk or negedge i_Rst_L)





  // Purpose: Generate MOSI data//生成发送控制序列
  // Works with both CPHA=0 and CPHA=1

  always @(posedge i_Clk or negedge i_Rst_L)
  begin

    if (~i_Rst_L)

    begin

      o_SPI_MOSI     <= 1'b0;

      r_TX_Bit_Count <= 3'b111; // send MSb first

    end

    else

    begin

      // If ready is high, reset bit counts to default

      if (o_TX_Ready)

      begin

        r_TX_Bit_Count <= 3'b111;

      end

      // Catch the case where we start transaction and CPHA = 0

      else if (r_TX_DV & ~w_CPHA)

      begin

        o_SPI_MOSI     <= r_TX_Byte[3'b111];

        r_TX_Bit_Count <= 3'b110;

      end

      else if ((r_Leading_Edge & w_CPHA) | (r_Trailing_Edge & ~w_CPHA)) //在边缘到来时发送

      begin

        r_TX_Bit_Count <= r_TX_Bit_Count - 1;

        o_SPI_MOSI     <= r_TX_Byte[r_TX_Bit_Count];//将发送控制序列中一位位发送

      end

    end

  end

  // Purpose: Read in MISO data.//读取输出数据

  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    
    if (~i_Rst_L)
      begin
        o_RX_Byte      <= 8'h00;
        o_RX_DV        <= 1'b0;
        r_RX_Bit_Count <= 3'b111;
      end

    else
    begin

      // Default Assignments

      o_RX_DV   <= 1'b0;

      if (o_TX_Ready) // Check if ready is high, if so reset bit count to default
      begin

        r_RX_Bit_Count <= 3'b111;

      end

      else if ((r_Leading_Edge & ~w_CPHA) | (r_Trailing_Edge & w_CPHA))

      begin

        o_RX_Byte[r_RX_Bit_Count] <= i_SPI_MISO;  // Sample data

        r_RX_Bit_Count            <= r_RX_Bit_Count - 1;

        if (r_RX_Bit_Count == 3'b000)

        begin

          o_RX_DV   <= 1'b1;   // Byte done, pulse Data Valid

        end

      end

    end

  end

  

  

  // Purpose: Add clock delay to signals for alignment.

  always @(posedge i_Clk or negedge i_Rst_L)

  begin

    if (~i_Rst_L)

    begin

      o_SPI_Clk  <= w_CPOL;

    end

    else

      begin

        o_SPI_Clk <= r_SPI_Clk;

      end // else: !if(~i_Rst_L)

  end // always @ (posedge i_Clk or negedge i_Rst_L)
  

endmodule // SPI_Master
