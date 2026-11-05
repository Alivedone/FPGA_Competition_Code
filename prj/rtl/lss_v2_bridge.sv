// LS V2: PS DDR read DMA -> complete window BRAM -> AI_Mate shared DDR.
// UserCustomOp has no B response. Each 64-byte write is fenced by a matching
// readback on the same interface; DONE requires every returned beat to match.
module lss_v2_bridge (
 input wire gp_clk, gp_rst_n, hp_clk, hp_rst_n, ddr_ready,
 input wire [31:0] ra_awaddr, ra_awdata,
 input wire ra_awvalid, output wire ra_awready,
 input wire [31:0] ra_araddr, input wire ra_arvalid,
 output wire ra_arready, output reg [31:0] ra_rdata,
 output reg ra_rvalid, input wire ra_rready,
 output wire [31:0] ps_araddr, output wire [3:0] ps_arlen,
 output wire ps_arvalid, input wire ps_arready,
 input wire [63:0] ps_rdata, input wire [1:0] ps_rresp,
 input wire ps_rlast, ps_rvalid, output wire ps_rready,
 output wire [31:0] ddr_awaddr, output wire [511:0] ddr_awdata,
 output wire [71:0] ddr_awinfo, output wire ddr_awvalid,
 input wire ddr_awready,
 output wire [31:0] ddr_araddr, output wire [31:0] ddr_arinfo,
 output wire ddr_arvalid, input wire ddr_arready,
 input wire [511:0] ddr_rdata, input wire ddr_rvalid,
 input wire [31:0] ddr_rinfo, output wire ddr_rready
);
 localparam IDLE=0, CHECK=1, PS_ADDR=2, PS_DATA=3, PACK_REQ=4,
   PACK_WAIT=5, PACK=6, DDR_WRITE=7, DDR_ADDR=8, DDR_DATA=9,
   FINISH=10, FAILED=11;
 reg [3:0] state;
 reg [31:0] cfg_src,cfg_dst,cfg_w;
 reg command, busy_gp, done_gp, error_gp;
 reg [31:0] read_gp,write_gp,verify_gp,code_gp,seq_gp,rejected;
 (* ASYNC_REG="TRUE" *) reg ack_g1,ack_g2,ready_g1,ready_g2;
 reg ack_seen;
 (* ASYNC_REG="TRUE" *) reg cmd_h1,cmd_h2;
 reg cmd_seen,ack;
 reg [31:0] src,dst,total,read_bytes,write_bytes,verify_bytes,code;
 reg [12:0] recv_index,read_index,pack_base;
 reg [2:0] lane,burst_beat;
 reg [10:0] fence_retries;
 reg [511:0] packed_data;
 (* ram_style="block" *) reg [63:0] memory [0:5119];
 reg [63:0] mem_q;
 wire failed=(code!=0);
 wire aw_event=ra_awvalid && ra_awready;
 assign ra_awready=1'b1;
 assign ra_arready=!ra_rvalid;
 always @(posedge gp_clk or negedge gp_rst_n) begin
  if(!gp_rst_n) begin
   cfg_src<=0;cfg_dst<=0;cfg_w<=10;command<=0;busy_gp<=0;done_gp<=0;
   error_gp<=0;ack_g1<=0;ack_g2<=0;ack_seen<=0;ready_g1<=0;ready_g2<=0;
   read_gp<=0;write_gp<=0;verify_gp<=0;code_gp<=0;seq_gp<=0;rejected<=0;
   ra_rvalid<=0;ra_rdata<=0;
  end else begin
   ack_g1<=ack;ack_g2<=ack_g1;ready_g1<=ddr_ready;ready_g2<=ready_g1;
   if(ack_g2!=ack_seen) begin
    // Bundled result data is stable before ack traverses two synchronizers.
    ack_seen<=ack_g2;busy_gp<=0;done_gp<=1;error_gp<=failed;
    read_gp<=read_bytes;write_gp<=write_bytes;verify_gp<=verify_bytes;
    code_gp<=code;seq_gp<=seq_gp+1;
   end
   if(aw_event) begin
    if(busy_gp) rejected<=rejected+1;
    else case(ra_awaddr[7:0])
     8'h10:cfg_src<=ra_awdata;
     8'h14:cfg_dst<=ra_awdata;
     8'h18:cfg_w<=ra_awdata;
     8'h04:if(ra_awdata==1) begin
      if(ready_g2) begin
       command<=!command;busy_gp<=1;done_gp<=0;error_gp<=0;
       read_gp<=0;write_gp<=0;verify_gp<=0;code_gp<=0;
      end else rejected<=rejected+1;
     end
     default:rejected<=rejected+1;
    endcase
   end
   if(ra_rvalid && ra_rready) ra_rvalid<=0;
   if(ra_arvalid && ra_arready) begin
    ra_rvalid<=1;
    case(ra_araddr[7:0])
     8'h00:ra_rdata<=32'h4c535632;
     8'h08:ra_rdata<={28'b0,ready_g2,error_gp,done_gp,busy_gp};
     8'h0c:ra_rdata<=seq_gp;
     8'h10:ra_rdata<=cfg_src;
     8'h14:ra_rdata<=cfg_dst;
     8'h18:ra_rdata<=cfg_w;
     8'h1c:ra_rdata<=read_gp;
     8'h20:ra_rdata<=write_gp;
     8'h24:ra_rdata<=verify_gp;
     8'h28:ra_rdata<=code_gp;
     8'h2c:ra_rdata<=rejected;
     8'h30:ra_rdata<=32'h00010000;
     default:ra_rdata<=32'hbad00000;
    endcase
   end
  end
 end

 assign ps_araddr=src+read_bytes;
 assign ps_arlen=4'd7; // 8 x 64-bit = 64 bytes, never crosses 4KiB.
 assign ps_arvalid=(state==PS_ADDR);
 assign ps_rready=(state==PS_DATA);
 assign ddr_awaddr=dst+write_bytes;
 assign ddr_awdata=packed_data;
 assign ddr_awinfo={1'b0,64'hffffffffffffffff,6'b0,1'b1};
 assign ddr_awvalid=(state==DDR_WRITE);
 assign ddr_araddr=dst+verify_bytes;
 assign ddr_arinfo=32'd1;
 assign ddr_arvalid=(state==DDR_ADDR);
 assign ddr_rready=(state==DDR_DATA);
 always @(posedge hp_clk) mem_q<=memory[read_index];
 // The RAM itself has no reset. Task state prevents reading an unwritten slot.
 // Keep its write process separate from asynchronous control reset for BRAM inference.
 always @(posedge hp_clk) begin
  if(hp_rst_n && state==PS_DATA && ps_rvalid) memory[recv_index]<=ps_rdata;
 end
 always @(posedge hp_clk or negedge hp_rst_n) begin
  if(!hp_rst_n) begin
   state<=IDLE;cmd_h1<=0;cmd_h2<=0;cmd_seen<=0;ack<=0;
   src<=0;dst<=0;total<=0;read_bytes<=0;write_bytes<=0;
   verify_bytes<=0;code<=0;recv_index<=0;read_index<=0;
   pack_base<=0;lane<=0;burst_beat<=0;packed_data<=0;fence_retries<=0;
  end else begin
   cmd_h1<=command;cmd_h2<=cmd_h1;
   case(state)
    IDLE:if(cmd_h2!=cmd_seen) begin
     cmd_seen<=cmd_h2;
     // Source config is held while busy_gp; sampled after command CDC.
     src<=cfg_src;dst<=cfg_dst;total<=cfg_w<<11;
     read_bytes<=0;write_bytes<=0;verify_bytes<=0;code<=0;
     recv_index<=0;pack_base<=0;lane<=0;burst_beat<=0;fence_retries<=0;state<=CHECK;
    end
    CHECK:begin
     if(cfg_w<1 || cfg_w>20) begin code<=1;state<=FAILED;end
     else if(src[5:0]!=0 || {1'b0,src}+total>33'h040000000) begin code<=2;state<=FAILED;end
     else if(dst[5:0]!=0 || {1'b0,dst}+total>33'h100000000) begin code<=3;state<=FAILED;end
     else if(!ddr_ready) begin code<=4;state<=FAILED;end
     else state<=PS_ADDR;
    end
    PS_ADDR:if(ps_arready) state<=PS_DATA;
    PS_DATA:if(ps_rvalid) begin
     recv_index<=recv_index+1;
     // Any PS bus error is terminal; stop after draining this legal burst.
     if(ps_rresp!=0) code<=5;
     if(ps_rlast!=(burst_beat==7)) code<=6;
     if(burst_beat==7 || ps_rlast) begin
      burst_beat<=0;
      if(code!=0 || ps_rresp!=0 || !ps_rlast || burst_beat!=7) state<=FAILED;
      else begin
       read_bytes<=read_bytes+64;
       if(read_bytes+64==total) state<=PACK_REQ;
       else state<=PS_ADDR;
      end
     end else burst_beat<=burst_beat+1;
    end
    PACK_REQ:begin read_index<=pack_base+lane;state<=PACK_WAIT;end
    PACK_WAIT:state<=PACK;
    PACK:begin
     packed_data[lane*64+:64]<=mem_q;
     if(lane==7) begin lane<=0;state<=DDR_WRITE;end
     else begin lane<=lane+1;state<=PACK_REQ;end
    end
    DDR_WRITE:if(ddr_awready) begin write_bytes<=write_bytes+64;state<=DDR_ADDR;end
    DDR_ADDR:if(ddr_arready) state<=DDR_DATA;
    DDR_DATA:if(ddr_rvalid) begin
     if(!ddr_rinfo[0]) begin code<=7;state<=FAILED;end
     else if(ddr_rdata!==packed_data) begin
      // Read/write queues may be independently buffered in the vendor core.
      // A read may see the poisoned old value before a posted write commits.
      // Poll for visibility with a finite bound, never start NPU on stale data.
      if(fence_retries==1023) begin code<=7;state<=FAILED;end
      else begin fence_retries<=fence_retries+1;state<=DDR_ADDR;end
     end
     else begin
      fence_retries<=0;
      verify_bytes<=verify_bytes+64;
      if(verify_bytes+64==total) state<=FINISH;
      else begin pack_base<=pack_base+8;state<=PACK_REQ;end
     end
    end
    FINISH:begin ack<=cmd_seen;state<=IDLE;end
    FAILED:begin ack<=cmd_seen;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
