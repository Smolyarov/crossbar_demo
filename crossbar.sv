`include "interfaces.sv"

module crossbar #(MASTERS=4, SLAVES=4) (master_if.crossbar mif, slave_if.crossbar sif);
  
  typedef struct {
    logic 	 tx_valid;
    logic [31-$clog2(SLAVES):0] addr;
    logic [31:0] 		data;
    logic 			cmd; // 0-read, 1-write
  } tx_type;

  // transaction cells
  tx_type tx_queue[SLAVES][MASTERS]; // [dst][src]

  enum 				{READY, WAIT_ACK, WAIT_RESP} sif_state[SLAVES];

  // current transaction pointer for each slave
  logic [$clog2(MASTERS)-1:0] 	rr_cnt[SLAVES];
  
  // table of slave responses for priority mux
  struct 			{
    logic 			ack, resp;
    logic [31:0] 		rdata;
  } try[MASTERS][SLAVES];
  

  
  always_ff @(posedge mif.clk) begin


    
    if (mif.rst) begin
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
    end // if (mif.rst)

    
    
    else begin
      

      
      for (int i=0; i<MASTERS; i++) begin // store master requests
	
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
      end // for (int i=0; i<MASTERS; i++)

      

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
	    
	    if (tx.tx_valid) begin
 	      sif.req[i] <= 1'b1;
	      sif.cmd[i] <= tx.cmd;
	      sif.addr[i] <= tx.addr;
	      if (tx.cmd) sif.wdata[i] <= tx.data; // write
	      sif_state[i] <= WAIT_ACK;
	      
	      tx_queue[i][rr_cnt[i]].tx_valid <= 0; // erase transaction 
	    end
	  end // case: READY
	  
	  WAIT_ACK: begin
	    if (sif.ack[i]) begin
	      try[rr_cnt[i]][i].ack <= 1'b1;
	      sif_state[i] <= WAIT_RESP;
	    end
	  end
	  
	  WAIT_RESP: begin
	    if (sif.resp[i]) begin
	      try[rr_cnt[i]][i].resp <= 1'b1;
	      try[rr_cnt[i]][i].rdata <= sif.rdata[i];
	      sif_state[i] <= READY;
	      
	      // update rr_cnt (set to next non-empty transaction) round-robin
	      priority case (1'b1)
		tx_queue[i][rr_cnt[i]+1].tx_valid: rr_cnt[i] <= rr_cnt[i]+2'(1);
		tx_queue[i][rr_cnt[i]+2].tx_valid: rr_cnt[i] <= rr_cnt[i]+2'(2);
		tx_queue[i][rr_cnt[i]+3].tx_valid: rr_cnt[i] <= rr_cnt[i]+2'(3);
		default: rr_cnt[i] <= rr_cnt[i];
	      endcase // priority case (1'b1)
	      
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

      
      
    end // else: !if(mif.rst)
    
  end // always_ff @ (posedge mif.clk)
  
endmodule
