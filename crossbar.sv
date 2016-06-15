`include "interfaces.sv"

module crossbar #(MASTERS=4, SLAVES=4) (master_if.crossbar mif, slave_if.crossbar sif);
  
  typedef struct {
    logic 	 tx_valid;
    logic [31-$clog2(SLAVES):0] addr;
    logic [31:0] 		data;
    logic 			cmd; // 0-read, 1-write
  } tx_type;
  
  tx_type tx_queue[SLAVES][MASTERS]; // [dst][src]

  enum 				{READY, WAIT_ACK, WAIT_RESP} sif_state[SLAVES];
  
  logic [$clog2(MASTERS)-1:0] 	rr_cnt[SLAVES], rr_next[SLAVES];

  /*
  always_comb begin // determine next non-empty transaction for each slave
    foreach (rr_cnt[i])
      priority case (1'b1)
	tx_queue[i][rr_cnt[i]+1]: rr_next[i] <= rr_cnt[i]+1;
	tx_queue[i][rr_cnt[i]+2]: rr_next[i] <= rr_cnt[i]+2;
	tx_queue[i][rr_cnt[i]+3]: rr_next[i] <= rr_cnt[i]+3;
	tx_queue[i][rr_cnt[i]+1]: rr_next[i] <= rr_cnt[i]+1;
      endcase // priority case (1'b1)
  end
  */
  
  always_ff @(posedge mif.clk) begin
    if (mif.rst) begin
      rr_cnt <= 0;
      foreach (tx_queue[i,j]) tx_queue[i][j].tx_valid <= 0;
      
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
    end // if (mif.rst)
    
    else begin
      
      foreach (mif.req[i]) begin // store master requests
	
	logic [$clog2(SLAVES)-1:0] slave_addr;
	slave_addr = mif.addr[i][31:31-$clog2(SLAVES)+1];
	
	// if master requests, we check that corresponding master-to-slave
	// transaction cell is empty and push the transaction, else ignore it
	if (mif.req[i] && !(tx_queue[slave_addr][i].tx_valid)) begin
	  tx_queue[slave_addr][i] <= '{tx_valid : 1'b1,
				       data : mif.wdata[i],
				       cmd : mif.cmd[i],
				       addr : mif.addr[i][31-$clog2(SLAVES):0]};  
	end 
      end // foreach (mif.req[i])

      foreach (sif.req[i]) begin // slave operations
	sif.req[i] <= 0; // default
	
	unique case (sif_state[i])
	  READY: begin
	    tx_type tx;
	    tx = tx_queue[i][rr_cnt[i]];
	    
	    if (tx.tx_valid) begin
	      sif.req[i] <= 1'b1;
	      sif.cmd[i] <= tx.cmd;
	      sif.addr[i] <= tx.addr;
	      if (tx.cmd) sif.wdata[i] <= tx.data; // write
	      
	      tx_queue[i][rr_cnt[i]].tx_valid <= 0; // erase transaction
	    end
	  end
	  WAIT_ACK:;
	  WAIT_RESP:;
	endcase
      end
      
    end
    
    
  end // always_ff @ (posedge mif.clk)
  
endmodule
