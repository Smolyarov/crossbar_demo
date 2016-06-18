`timescale 1ns/1ns
`include "interfaces.sv"

program automatic test #(M=4, S=4) //masters, slaves
  (master_if.tb mif,
   slave_if.tb sif,
   input logic clk,
   output logic rst);
  
class Master_tx;
  
  rand bit 		enable[M];
  rand bit 		cmd[M]; // 0-read, 1-write
  rand bit[$clog2(S)-1:0] slave_num[M];
  rand bit[31-$clog2(S):0] addr[M];
  rand bit[`DW-1:0] wdata[M];

  constraint c0 {foreach (cmd[i]) !cmd[i] -> wdata[i] == '0;}

  task drive(input int i);
    fork
    if (enable[i]) begin
      mif.req[i] = 1;
      mif.cmd[i] = cmd[i];
      mif.addr[i] = {slave_num[i], addr[i]};
      mif.wdata[i] = cmd[i] ? wdata[i] : 'x;
      @(posedge clk);
      mif.req[i] = 0;
      repeat(5) @(posedge clk);
      sif.ack[slave_num[i]] = 1;
      @(posedge clk) sif.ack[slave_num[i]] = 0;
    end
    join_none
  endtask

  function void display();
    foreach (enable[i]) if (enable[i])
      $display("%t: M%1d: cmd=%1b slaveN=%d wdata=%h", $time, i ,cmd[i], slave_num[i], wdata[i]);
  endfunction
  
endclass // Master_tx

  task reset();
    rst = 1;
    @(posedge clk);
    rst = 0; 
  endtask // reset

  

  initial begin

    Master_tx mtx;
    mtx = new();

    repeat(10) @(posedge clk);
    reset();

    repeat(20) begin
      
      assert(mtx.randomize());
      mtx.display();
      foreach (mif.req[i]) mtx.drive(i);
      repeat(10) @(posedge clk);
     
    end
  end // initial begin

  final $display("final @%t", $time);
  
  
endprogram
