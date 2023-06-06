class spi_driver;
	virtual spi_if vif;
	event drDone;
	mailbox drMbx;

	task run();
		$display ("T=%0t [Driver] Starting...");

		