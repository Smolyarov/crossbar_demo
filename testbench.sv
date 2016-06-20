`timescale 1ns/1ns
`include "interfaces.sv"

`define SLAVE_ACK_LAT 2
`define SLAVE_RESP_LAT 2

program automatic test #(M=4, S=4) //masters, slaves
  (master_if.tb mif,
   slave_if.tb sif,
   input logic clk,
   output logic rst);

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
    enable.sum() with (8'(item)) inside {[2:M]};
    foreach (slave_num[i])
      if (i>0) slave_num[i]==slave_num[i-1];
  }
  
  constraint all_to_all {
    enable.sum() with (8'(item)) == M;
    foreach (slave_num[i])
      foreach (slave_num[j])
        if (i!=j) slave_num[i] != slave_num[j]; // unique slave
  }

  
  task drive_mif(input int i);
    fork
      if (enable[i]) begin
        $display("M%1d req\t@%4t", i, $time);
        mif.req[i] = 1;
        mif.cmd[i] = cmd[i];
        mif.addr[i] = {slave_num[i], addr[i]};
        mif.wdata[i] = cmd[i] ? wdata[i] : 'x;
        @(posedge clk);
        mif.req[i] = 0;
        forever begin
          if (mif.ack[i]) begin
            $display("M%1d ack\t@%4t", i, $time);
            if (cmd[i]) break; // if write, no need to wait for resp
            else
              forever begin
                if (mif.resp[i]) begin
                  $display("M%1d resp\t@%4t", i, $time);
                  $display("M%1d got %h expected %h", i, mif.rdata[i], addr[i]);
                  break;
                end
		else @(posedge clk);
              end
	    
	  end // if (mif.ack[i])
          else @(posedge clk);
	  
        end // forever begin
	
      end // if (enable[i])
    join_none
  endtask // drive_mif

  
  function void print();
    $display("@%4tns: transaction", $time);
    foreach (enable[i])
      if (enable[i])
        $display("M%1d->S%1d cmd:%1b addr:%h wdata:%h",
                 i, slave_num[i], cmd[i], addr[i], wdata[i]);
  endfunction
  
endclass // Master_tx
  
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
  endtask
  
  
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
  endtask
  
  // Tests
  
  initial begin
    Master_tx mtx;
    mtx = new(); // !! each time create new tx
    mtx.constraint_mode(0);
    
    reset();
    mtx.many_to_one.constraint_mode(1);
    mtx.randomize();
    mtx.print();
    foreach (mtx.enable[i])
      if (mtx.enable[i]) mtx.drive_mif(i);
    foreach (sif.req[i]) spawn_slave(i);
    #1000;
  end
  
  

  final $display("EXIT\t@%4t", $time);  
endprogram
