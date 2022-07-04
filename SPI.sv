`timescale 1ns / 1ps

module spi_controller #(
	parameter SCLK_DUTY_CYCLE = 5
	) (
	input        sysClkIn,
	input        sysRstIn,
	input        tValidIn,
	output       tReadyOut,
	input  [7:0] tDataIn,
	output       SCLK,
	output       SS,
	output       MOSI,
	input        MISO
);

	localparam COUNTER_MID = SCLK_DUTY_CYCLE - 1;
	localparam COUNTER_MAX = (SCLK_DUTY_CYCLE*2)-1;

	typedef enum {IDLE, SEND, HOLD_SS, HOLD} spi_enum;

	spi_enum    state;
	logic [7:0] shiftReg;
	logic [3:0] shiftCounter;
	logic [4:0] counter;
	logic       clkDiv;
	logic       mosiTemp;

	// State Machine for sending out 8-bit SPI transactions.
	always@(posedge sysRstIn or posedge sysClkIn)
	begin
		if (sysRstIn) begin
			shiftReg     <= 0;
			shiftCounter <= 0;
			mosiTemp     <= 1'b1;
			state        <= IDLE;
		end else begin
			case (state)
				IDLE: begin
					shiftCounter <= 0;
					shiftReg     <= tDataIn;
					mosiTemp     <= 1'b1;

					if (tValidIn == 1'b1)
						state <= SEND;
				end

				SEND: begin
					if (counter == COUNTER_MID) begin
						mosiTemp <= shiftReg[7];
						shiftReg <= {shiftReg[6:0], 1'b0};
						if (shiftCounter == 4'd8)
							shiftCounter <= 1'b0;
						else
							shiftCounter <= shiftCounter + 1;
					end

					if (shiftCounter == 4'd8 && counter == COUNTER_MID)
						state <= HOLD_SS;
				end

				HOLD_SS: begin
					shiftCounter <= shiftCounter + 1;

					if (shiftCounter == 4'd3)
						state <= HOLD;
				end

				// Don't know if this state is still needed. Should just go back to idle anyway.
				HOLD: begin
					if (tValidIn == 1'b0)
						state <= IDLE;
				end
			endcase
		end
	end

	// Counter used to create SCLK
	always@(posedge sysRstIn or posedge sysClkIn)
	begin
		if (sysRstIn) begin
			counter <= 0;
		end else begin
			if (state == SEND && ~(counter == COUNTER_MID && shiftCounter == 8)) begin
				if (counter == COUNTER_MAX)
					counter <= 0;
				else
					counter <= counter + 1;
			end else begin
				counter <= 0;
			end
		end
	end

	// Outputs
	assign SCLK = (counter < SCLK_DUTY_CYCLE) | SS;
	assign MOSI = mosiTemp | SS | (state == HOLD_SS ? 1'b1 : 1'b0);
	assign SS   = (state != SEND && state != HOLD_SS) ? 1'b1 : 1'b0;
	assign tReadyOut = (state == IDLE && tValidIn == 1'b0) ? 1'b1 : 1'b0;

endmodule
