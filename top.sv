`timescale 1ns/1ns
`include "interfaces.sv"

module top;
  
  logic clk=0, rst;
  master_if mif();
  slave_if sif();

  crossbar cb0 (mif, sif, clk, rst);
  test tb0 (mif, sif, clk, rst);

  always #5 clk = ~clk;
  
endmodule
