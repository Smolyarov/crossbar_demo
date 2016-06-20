`include "interfaces.sv"

module crossbar
  #(MASTERS=4, SLAVES=4)
  (
   master_if.crossbar mif,
   slave_if.crossbar sif,
   input logic clk, rst
   );
  
  typedef struct {
    logic 	 tx_valid;
    logic [31-$clog2(SLAVES):0] addr;
    logic [`DW-1:0] 		data;
    logic 			cmd; // 0-read, 1-write
  } tx_type;

  // transaction cells
  tx_type tx_queue[SLAVES][MASTERS]; // [dst][src]

  enum logic[1:0] {READY, WAIT_ACK, WAIT_RESP} sif_state[SLAVES];

  // current transaction pointer for each slave
  logic [$clog2(MASTERS)-1:0] 	rr_cnt[SLAVES], rr_copy[SLAVES];

  // tx validity for +1, +2, +3 steps for each slave
  // is used to optimize (ex-)combinatorial-heavy update_rr()
  logic 			next_tx_valid[SLAVES][1:3];
  
  // set round-robin to next non-empty transaction
  function logic [$clog2(MASTERS)-1:0] update_rr (input int i); 
    priority case (1'b1)
      next_tx_valid[i][1]: return rr_copy[i]+2'(1);
      next_tx_valid[i][2]: return rr_copy[i]+2'(2);
      next_tx_valid[i][3]: return rr_copy[i]+2'(3);
      default: return rr_cnt[i];
    endcase // priority case (1'b1)
  endfunction
  
  // table of slave responses for priority mux
  struct 			{
    logic 			ack, resp;
    logic [`DW-1:0] 		rdata;
    } try[MASTERS][SLAVES];
  

  
  always_ff @(posedge clk) begin


    
    if (rst) begin
      for (int i=0; i<SLAVES; i++) rr_cnt[i] <= 0;

      for (int i=0; i<SLAVES; i++)
	for (int j=0; j<MASTERS; j++) tx_queue[i][j].tx_valid <= 0;

      for (int i=0; i<MASTERS; i++)
	for (int j=0; j<SLAVES; j++) begin
	  try[i][j].ack <= 0;
	  try[i][j].resp <= 0;
	end
      
      for (int i=0; i<MASTERS; i++) begin
	mif.ack[i] <= 0;
	mif.resp[i] <= 0;
	mif.rdata[i] <= 0;
      end
      
      for (int i=0; i<SLAVES; i++) begin
	sif_state[i] <= READY;
	sif.req[i] <= 0;
	sif.cmd[i] <= 0;
	sif.addr[i] <= 0;
	sif.wdata[i] <= 0;
      end
    end // if (rst)

    
    
    else begin
      

      
      // store master requests:
      // if no txs in queue for current slave,
      // rr_cnt is set to a master with a lower number
      for (int i=MASTERS-1; i>=0; i--) begin
	
	logic [$clog2(SLAVES)-1:0] slave_addr;
	automatic logic 			   slave_q_has_txs = 0;
	slave_addr = mif.addr[i][31:31-$clog2(SLAVES)+1];
	
	// if master requests, we check that corresponding master-to-slave
	// transaction cell is empty and push the transaction, else ignore it
	if (mif.req[i] && !(tx_queue[slave_addr][i].tx_valid)) begin
	  tx_queue[slave_addr][i] <= '{tx_valid : 1'b1,
				       data : mif.wdata[i],
				       cmd : mif.cmd[i],
				       addr : mif.addr[i][31-$clog2(SLAVES):0]};

	  // set rr_cnt if no transactions in queue for current slave
	  for (int j=0; j<MASTERS; j++) // ### optimize time here ###
	    slave_q_has_txs |= tx_queue[slave_addr][j].tx_valid;
	  if (!slave_q_has_txs) begin
	    rr_cnt[slave_addr] <= 2'(i);
	    $display("@%t:tx_q slave %1d empty, write rr_cnt with %1d",$time,slave_addr,i);
	  end
	  
	end // if (mif.req[i] && !(tx_queue[slave_addr][i].tx_valid))
      end // for (int i=MASTERS-1; i>=0; i--)

      

      for (int i=0; i<SLAVES; i++) begin // slave operations
	// defaults
	sif.req[i] <= 0;
	for (int j=0; j<MASTERS; j++) begin
	  try[j][i].ack <= 0;
	  try[j][i].resp <= 0;
	  try[j][i].rdata <= 0;
	end
	
	unique case (sif_state[i]) // slave FSMs
	  READY: begin
	    tx_type tx;
	    tx = tx_queue[i][rr_cnt[i]];
	    
	    if (tx.tx_valid) begin // transaction pull
 	      sif.req[i] <= 1'b1;
	      sif.cmd[i] <= tx.cmd;
	      sif.addr[i] <= tx.addr;
	      if (tx.cmd) sif.wdata[i] <= tx.data; // write
	      sif_state[i] <= WAIT_ACK;
	      
	      tx_queue[i][rr_cnt[i]].tx_valid <= 0; // erase transaction
	      
	      // save copy of transaction pointer in case rr_cnt gets
	      // overwritten in transaction push phase
	      rr_copy[i] <= rr_cnt[i];  

	      for (int j=1; j<=3; j++) // see next_tx_valid declaration
		next_tx_valid[i][j] <= tx_queue[i][rr_cnt[i]+2'(j)].tx_valid;
	      
	    end // if (tx.tx_valid)
	  end // case: READY
	  
	  WAIT_ACK: begin
	    if (sif.ack[i]) begin
	      try[rr_copy[i]][i].ack <= 1'b1;
	      
	      // if write, then we are done, if read, wait for response
	      if (tx_queue[i][rr_copy[i]].cmd) begin
		sif_state[i] <= READY;
		rr_cnt[i] <= update_rr(i);
	      end
	      else sif_state[i] <= WAIT_RESP;
	    end // if (sif.ack[i])

	  end // case: WAIT_ACK
	  
	  WAIT_RESP: begin
	    if (sif.resp[i]) begin
	      try[rr_copy[i]][i].resp <= 1'b1;
	      try[rr_copy[i]][i].rdata <= sif.rdata[i];
	      sif_state[i] <= READY;
	      rr_cnt[i] <= update_rr(i);
	    end // if (sif.resp[i])
	    
	  end // case: WAIT_RESP
	  
	endcase // unique case (sif_state[i])	
      end // for (int i=0; i<SLAVES; i++)


      
      for (int i=0; i<MASTERS; i++) begin // drive slave responses to masters
	// defaults
	mif.ack[i] <= 0;
	mif.resp[i] <= 0;

	for (int j=0; j<SLAVES; j++)
	  if (try[i][j].ack) mif.ack[i] <= 1'b1;

	for (int j=0; j<SLAVES; j++)
	  if (try[i][j].resp) begin
	    mif.resp[i] <= 1'b1;
	    mif.rdata[i] <= try[i][j].rdata;
	    break; // if more than 1 simultaneous resp, first one is passed
	  end
	
      end // foreach (mif.ack[i])

      
      
    end // else: !if(rst)
    
  end // always_ff @ (posedge clk)
  
endmodule
