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
  rand bit[31:0] wdata[M];

  task drive();
    foreach (enable[i]) begin
      fork
	if (enable[i]) begin
	  mif.req[i] = 1;
	  mif.cmd[i] = cmd;
	  mif.addr[i] = {slave_num[i], addr[i]};
	  mif.wdata[i] = cmd ? wdata[i] : 'x;
	  @(posedge clk);
	  mif.req[i] = 0;
	end
      join_none
    end
  endtask
  
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

    repeat(10) begin
      assert(mtx.randomize());
      mtx.drive();
      repeat(10) @(posedge clk);
    end
  end
  
endprogram
