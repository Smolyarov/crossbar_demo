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
	mif.req[i] = 1;
	mif.cmd[i] = cmd[i];
	mif.addr[i] = {slave_num[i], addr[i]};
	mif.wdata[i] = cmd[i] ? wdata[i] : 'x;
	@(posedge clk);
	mif.req[i] = 0;
      end
    join_none
  endtask

  
  task drive_sif(input int i);
    bit cmd_int;
    bit [31-$clog2(S):0] addr_int;
    fork
      forever begin
        if (sif.req[i]) begin
          
          cmd_int = sif.cmd[i];
          addr_int = sif.addr[i]; 
          
          repeat(`SLAVE_ACK_LAT) @(posedge clk);
          sif.ack[i] = 1;
          $display("ACK @%t", $time);
          @(posedge clk) sif.ack[i] = 0;
          
          if (!cmd_int) begin // read operation
            repeat(`SLAVE_RESP_LAT) @(posedge clk);
            $display("RESP @%t", $time);
            sif.resp[i] = 1;
            sif.rdata[i] = addr_int;
            @(posedge clk) sif.resp[i] = 0;
            break;
          end
          else break;
          
        end // if (sif.req[i])
        else @(posedge clk);
      end // forever begin
    join_none
  endtask

  
  function void print();
    $display("@%t ns: transaction", $time);
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
  
  // Tests
  
  initial begin
    Master_tx mtx;
    mtx = new(); // !! each time create new tx
    mtx.constraint_mode(0);
    
    reset();
    mtx.one_to_one.constraint_mode(1);
    mtx.randomize();
    mtx.print();
    foreach (mtx.enable[i])
      if (mtx.enable[i]) begin
        mtx.drive_mif(i);
        mtx.drive_sif(mtx.slave_num[i]);
      end
    #100;
  end
  
  

  final $display("EXIT @%t", $time);  
endprogram
