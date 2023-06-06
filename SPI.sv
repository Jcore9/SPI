`timescale 1ns / 1ps

module spi_intf #(
  parameter SCLK_DUTY_CYCLE = 5
) (
  // Clocks, Resets
  input  clkIn,
  input  rstNIn,
  output spiClkOut,
  input  spiRstNIn,

  // Data Input
  AXI4_STREAM_BASIC.SLAVE sAxiS,

  // SPI Interface
  input  MISO,
  output MOSI,
  output SS
);

  localparam COUNTER_MID = SCLK_DUTY_CYCLE-1;
  localparam COUNTER_MAX = (SCLK_DUTY_CYCLE*2)-1;

  typedef enum {
    IDLE,
    SEND
  } spi_sm_enum;

  (* mark_debug = "true" *) spi_sm_enum spiState;
  logic [4:0] counter = 0;
  logic mosiR;
  logic ssR;
  logic tReadyR;
  logic [7:0] shiftData;
  logic [3:0] shiftCounter;

  /*
  SPI Clock Generator
  Generates the SPI clock at the requested duty cycle when the counter reaches the mid-point
  and it's not the end of the data sequence.
  */
  always_ff @ (posedge clkIn or negedge rstNIn)
  begin
    if (!rstNIn)
    begin
      counter <= 'b0;
    end else if (spiState == SEND && ~(counter == COUNTER_MID && shiftCounter == 8))
    begin
      if (counter == COUNTER_MAX)
        counter <= 'b0;
      else
        counter <= counter + 'b1;
    end else
      counter <= 'b0;
  end

  /*
  SPI Generation
  spiClkOut generated from counter being less than the duty cycle and the slave is selected
  MOSI is high when mosiQ is high and slave is selected else it's 0
  SS is high when not in the SEND state
  tReadyOut is high when in the IDLE state and tValidIn is low
  TODO : The tValidIn condition is because of the OLED control state machine. This will change in the future.
  */
  assign SS           = (spiState != SEND) ? 'b1 : 'b0;
  assign MOSI         = mosiR | SS ? 'b1 : 'b0;
  assign spiClkOut    = (counter < SCLK_DUTY_CYCLE) | SS;
  assign sAxiS.tready = (spiState == IDLE && sAxiS.tvalid == 'b0) ? 'b1 : 'b0;

  always_ff @ (posedge clkIn or negedge rstNIn)
  begin
    if (!rstNIn)
    begin
      mosiR        <= 'b1;
//      sAxiS.tready <= 'b0;
      shiftCounter <= 'b0;
      spiState     <= IDLE;
    end else
    begin
      case (spiState)
        IDLE: begin
          mosiR        <= 'b1;
//          sAxiS.tready <= 'b1;

          if (sAxiS.tvalid == 'b1)
          begin
//            sAxiS.tready <= 'b1;
            shiftData    <= sAxiS.tdata;
            spiState     <= SEND;
          end
        end

        SEND: begin
          if (counter == COUNTER_MID)
          begin
            mosiR <= shiftData[7];
            shiftData <= {shiftData[6:0], 1'b0};
            if (shiftCounter == 8)
            begin
              shiftCounter <= 0;
              spiState     <= IDLE;
            end else
            begin
              shiftCounter <= shiftCounter + 1;
            end
          end
        end
      endcase
    end
  end

endmodule