interface master_if #(N=4) (input logic clk, rst);
  logic req[N], ack[N], cmd[N], resp[N];
  logic [31:0] addr[N];
  logic [31:0] wdata[N];
  logic [31:0] rdata[N];

  modport crossbar(input clk, rst, req, cmd, addr, wdata,
		   output ack, resp, rdata);

  modport tb (input clk, rst, ack, resp, rdata,
	      output req, cmd, addr, wdata);
endinterface

interface slave_if #(N=4);
  logic 	     req[N], ack[N], cmd[N], resp[N];
  logic [31-$clog2(N):0] addr[N];
  logic [31:0] 		 wdata[N];
  logic [31:0] 		 rdata[N];

  modport crossbar (input ack, resp, rdata,
		    output req, cmd, addr, wdata);

  modport tb(input req, cmd, addr, wdata,
	     output ack, resp, rdata);

endinterface  
