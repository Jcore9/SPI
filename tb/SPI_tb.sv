`timescale 1ns/1ps

// The interface allows verification components to access DUT signals using
// a virtual interface handle
interface spi_if (input bit sysClk);
	logic       sysRst;
	logic [7:0] tData;
	logic       tValid;
	logic       tReady;
	logic       SCLK;
	logic       SS;
	logic       MOSI;
	logic       MISO;
endinterface

class spi_item;
	// This is the base transaction object that will be used in the environment
	// to initiate new transactions and capture transactions at DUT interface

	rand bit [7:0] tData;
	rand bit       tValid;
	     bit       tReady;
			 bit       SCLK;
			 bit       SS;
			 bit       MOSI;
			 bit       MISO;

	// This function allows us to print contents of the data packet so that
	// it is easier to track in a logfile
	function void print(string tag="");
		$display ("T=%0t [%s] tData=0x%0h tValid=%0d tReady=%0d SCLK=%0d SS=%0d MOSI=%0d MISO=%0d",
			$time, tag, tData, tValid, tReady, SCLK, SS, MOSI, MISO);
	endfunction
endclass

class driver;
	// The driver is responsible for driving transactions to the DUT.
	// All it does is to get a transaction from the mailbox if it is
	// available and drive it out into the DUT interface.
	virtual spi_if vif;
	event drv_done;
	mailbox drv_mbx;

	task run();
		$display("T=%0t [Driver] Starting...", $time);

		// Try to get a new transaction every time and then assign packet
		// contents to the interface. But do this only if the design is
		// ready to accept new transactions.
		forever begin
			spi_item item;
			
			$display("T=%0t [Driver] Waiting for item...", $time);
			drv_mbx.get(item);
			item.print("Driver");
			vif.tData  <= item.tData;
			vif.tValid <= item.tValid;
			
			@ (posedge vif.sysClk);
			while(!vif.tReady) begin
				$display ("T=%0t [Driver] Wait until ready is high", $time);
				@ (posedge vif.sysClk);
			end
			
			// When transfer is over, raise the done event
			->drv_done;
		end
	endtask
endclass

class monitor;
	// The monitor has a virtual interface handle with which it can monitor
	// the events happening on the interface. It sees new transactions and then
	// captures information into a packet and sends it to the scoreboard using 
	// another mailbox.
	virtual spi_if vif;
	mailbox scb_mbx;    // Mailbox connected to scoreboard

	task run();
		$display ("T=%0t [Monitor] Starting...", $time);

		// Check forever at every clock edge to see if there is a valid transaction
		// and if yes, capture into a class object and send it to the scoreboard when
		// the transaction is over.
		forever begin
			@ (posedge vif.sysClk);
			if (vif.tValid) begin
				spi_item item = new;
				item.tData = vif.tData;
				item.tValid = vif.tValid;
				item.tReady = vif.tReady;

				item.print("Monitor");
				scb_mbx.put(item);
			end
		end
	endtask
endclass

class scoreboard;
	// The scoreboard is responsible to cehck data integrity. Since the design stores data
	// it receives for each address, scoreboard helps to check if the same data is received
	// when the same address is read at any later point in time. So the scoreboard has a
	// "memory" element which updates it internally for every write operation.
	mailbox scb_mbx;

	task run();
		forever begin
			spi_item item;
			scb_mbx.get(item);
			item.print("Scoreboard");

			// In the future this will check whether the output is as expected on the MOSI
			// line on the posedge of the SCLK. For now, just outputting what is on the line.
			$display ("T=%0t [Scoreboard] PASS! tData=0x%0h tValid=%0d tReady=%0d",
				$time, item.tData, item.tValid, item.tReady);
		end
	endtask
endclass

class env;
	// The environment is a container object simply to hold all verification components
	// together. This environment can then be reused later and all components in it would
	// be automatically connected and available for use. This is an environment without
	// a generator.
	virtual spi_if vif;     // Virtual Interface Handle
	mailbox        scb_mbx; // Top level mailbox for SCB <-> MON
	scoreboard     s0;      // Scoreboard connected to monitor
	monitor        m0;      // Monitor from design
	driver         d0;      // Driver to design

	// Instantiate all testbench components
	function new();
		d0 = new;
		m0 = new;
		s0 = new;
		scb_mbx = new;
	endfunction

	// Assign handles and start all components so that they all become active and wait
	// for transactions to be available
	virtual task run();
		d0.vif = vif;
		m0.vif = vif;
		m0.scb_mbx = scb_mbx;
		s0.scb_mbx = scb_mbx;

		fork
			s0.run();
			d0.run();
			m0.run();
		join_any
	endtask
endclass

class test;
	// An environment without the generator and hence the stimulus should be written in
	// the test

	env e0;
	mailbox drv_mbx;

	function new();
		drv_mbx = new();
		e0 = new();
	endfunction

	virtual task run();
		e0.d0.drv_mbx = drv_mbx;

		fork
			e0.run();
		join_none

		apply_stim();
	endtask

	virtual task apply_stim();
		spi_item item;

		$display("T=%0t [Test] Starting Stimulus...", $time);
		for (int i = 0; i < 10; ++i) begin
		  item = new;
		  item.randomize();
		  drv_mbx.put(item);
	    end

		item = new;
		item.randomize() with {tData == 8'haa; tValid == 1; };
		drv_mbx.put(item);
	endtask
endclass

module SPI_tb ();

	reg sysClk;
	
	// System clock generation (100 mhz)
	always #5 sysClk = ~sysClk;

	spi_if _if (sysClk);

	spi_controller #(
		.SCLK_DUTY_CYCLE(5)
	) DUT (
		.sysClkIn(_if.sysClk),
		.sysRstIn(_if.sysRst),
		.tValidIn(_if.tValid),
		.tReadyOut(_if.tReady),
		.tDataIn(_if.tData),
		.SCLK(_if.SCLK),
		.SS(_if.SS),
		.MOSI(_if.MOSI),
		.MISO(_if.MISO)
	);

	initial begin
		test t0 = new();

		sysClk <= 0;
		_if.sysRst <= 'b1;
		#20 _if.sysRst <= 'b0;

		t0 = new;
		t0.e0.vif = _if;
		t0.run();

		#10000ns;
		$finish;
	end

	initial begin
		$dumpfile("spi.vcd");
		$dumpvars(0, SPI_tb);
	end
endmodule