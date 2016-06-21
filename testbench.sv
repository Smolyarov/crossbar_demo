`timescale 1ns/1ns
`include "interfaces.sv"

`define SLAVE_ACK_LAT 2
`define SLAVE_RESP_LAT 2

program automatic test #(M=4, S=4) //masters, slaves
  (master_if.tb mif,
   slave_if.tb sif,
   input logic clk,
   output logic rst);

  typedef class Errors;
  
// Classes
class Master_tx;
  rand bit 		enable[M];
  rand bit 		cmd[M]; // 0-read, 1-write
  rand bit[$clog2(S)-1:0] slave_num[M];
  rand bit[31-$clog2(S):0] addr[M];
  rand bit[`DW-1:0] wdata[M];
  
  constraint one_to_one {
    enable.sum() with (8'(item)) == 1;
  }
  
  constraint many_to_one {
    enable.sum() with (8'(item)) inside {[M:M]};
    foreach (slave_num[i])
    if (i>0) slave_num[i]==slave_num[i-1];
  }
  
  constraint all_to_all {
    enable.sum() with (8'(item)) == M;
    foreach (slave_num[i])
    foreach (slave_num[j])
    if (i!=j) slave_num[i] != slave_num[j]; // unique slave
  }

  constraint reads_only {
    foreach (cmd[i]) cmd[i] == 0;
  }

  constraint writes_only {
    foreach (cmd[i]) cmd[i] == 1;
  }


  function void print();
    $display("@%4tns: transaction", $time);
    foreach (enable[i])
      if (enable[i])
        $display("M%1d->S%1d cmd:%1b addr:%h wdata:%h",
                 i, slave_num[i], cmd[i], addr[i], wdata[i]);
  endfunction
  
endclass // Master_tx

class Errors;
  int 		data_err;
  int 		tx_score; // 0-ok, <0-not all txs have completed

  function new();
    data_err = 0;
    tx_score = 0;
  endfunction // new

  function void print();
    $display("TOTAL ERRORS: %0d", data_err);
    $display("TX SCORE: %0d", tx_score);
  endfunction // print
endclass
  
  // Test data
  
  // Properties
  
  // Assertions
  
  // Tasks and functions
  
  task reset();
    rst = 1;
    @(posedge clk);
    rst = 0;
    // test reset behavior
    assert(!(sif.req.or() || mif.ack.or() || mif.resp.or()))
      $display("Reset OK");
  endtask // reset
  
  
  task spawn_slave(input int i);  
    bit cmd_int;
    bit [31-$clog2(S):0] addr_int;
    
    fork
      forever begin
        if (sif.req[i]) begin
          $display("S%1d req\t@%4t", i, $time);
          
          cmd_int = sif.cmd[i];
          addr_int = sif.addr[i]; 
          
          repeat(`SLAVE_ACK_LAT) @(posedge clk);
          sif.ack[i] = 1;
          $display("S%1d ack\t@%4t", i, $time);
          @(posedge clk) sif.ack[i] = 0;
          
          if (!cmd_int) begin // read operation
            repeat(`SLAVE_RESP_LAT) @(posedge clk);
            $display("S%1d resp\t@%4t", i, $time);
            sif.resp[i] = 1;
            sif.rdata[i] = addr_int; // for convenient checking
            @(posedge clk) sif.resp[i] = 0;
            continue;
          end
          else continue;
          
        end // if (sif.req[i])
        else @(posedge clk);
	
      end // forever begin
    join_none
  endtask // spawn_slave


  task spawn_master(input int i, input mailbox #(Master_tx) mbx, input Errors err);
    fork
      Master_tx tx;

      forever begin
	mbx.peek(tx);
	if (tx.enable[i]) begin
	  err.tx_score--;
	  $display("M%1d -----start\t@%4t", i, $time);
          $display("M%1d req\t@%4t", i, $time);
          mif.req[i] = 1;
          mif.cmd[i] = tx.cmd[i];
          mif.addr[i] = {tx.slave_num[i], tx.addr[i]};
          mif.wdata[i] = tx.cmd[i] ? tx.wdata[i] : 'x;
          @(posedge clk);
          mif.req[i] = 0;
          forever begin
            if (mif.ack[i]) begin
              $display("M%1d ack\t@%4t", i, $time);
              if (tx.cmd[i]) begin
		err.tx_score++;
		$display("M%1d -----end\t@%4t", i, $time);
		@(posedge clk);
		break; // if write, no need to wait for resp
	      end
              else begin
		forever begin
                  if (mif.resp[i]) begin
                    $display("M%1d resp\t@%4t", i, $time);
                    $display("M%1d got %h expected %h", i, mif.rdata[i], tx.addr[i]);
		    assert(mif.rdata[i]==tx.addr[i]) else begin
		      $error("rdata mismatch");
		      err.data_err++;
		    end

		    err.tx_score++;
		    $display("M%1d -----end\t@%4t", i, $time);
		    @(posedge clk);
                    break;
                  end
		  else @(posedge clk);
		end // forever begin
		break;
	      end // else: !if(cmd[i])
	    end // if (mif.ack[i])
            else @(posedge clk);
	    
          end // forever begin
	  
	end // if (tx.enable[i])
	mbx.get(tx); // let put next transaction
      end // forever begin
    join_none
  endtask // spawn_master
  
  
  // Tests
  
  initial begin
    Master_tx mtx;
    Errors total_err;

    mailbox #(Master_tx) master_mbx[M];

    total_err = new();
    foreach (master_mbx[i]) master_mbx[i] = new(1);
    
    reset();

    foreach (sif.req[i]) spawn_slave(i);
    foreach (mif.req[i]) spawn_master(i, master_mbx[i], total_err);

    repeat(50) begin
      mtx = new();
      mtx.constraint_mode(0);
      mtx.one_to_one.constraint_mode(1);
      assert(mtx.randomize());
      mtx.print();

      fork
	foreach (mif.req[i]) master_mbx[i].put(mtx);
      join
    end
    
    #20us;
    $display("-----------------------------------------");
    total_err.print();
    $stop();
    
  end // initial begin
  
  

  final $display("EXIT\t@%4t", $time);  
endprogram
