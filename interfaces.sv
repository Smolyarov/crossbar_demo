`ifndef INTERFACES
  `define INTERFACES
  `define DW 32

interface master_if #(N=4);
  logic req[N], ack[N], cmd[N], resp[N];
  logic [31:0] addr[N];
  logic [`DW-1:0] wdata[N];
  logic [`DW-1:0] rdata[N];

  modport crossbar(input req, cmd, addr, wdata,
		   output ack, resp, rdata);

  modport tb (input ack, resp, rdata,
	      output req, cmd, addr, wdata);
endinterface // master_if

interface slave_if #(N=4);
  logic 	     req[N], ack[N], cmd[N], resp[N];
  logic [31-$clog2(N):0] addr[N];
  logic [`DW-1:0] 	 wdata[N];
  logic [`DW-1:0] 	 rdata[N];

  modport crossbar (input ack, resp, rdata,
		    output req, cmd, addr, wdata);

  modport tb(input req, cmd, addr, wdata,
	     output ack, resp, rdata);

endinterface // slave_if

`endif
