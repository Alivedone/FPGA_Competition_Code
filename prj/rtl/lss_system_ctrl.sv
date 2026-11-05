// Non-video system control at legacy GP0 user window 0x40080000.
// Keep reset control alive while its own soft reset resets the GP datapath.
module lss_system_ctrl(
 input wire clk, input wire bus_reset, input wire global_reset_n,
 mna_gp_ww_itf.slave ctrl,
 output reg soft_reset
);
 localparam [31:0] UNUSED=32'hB0DDDDDD;
 reg [6:0] count;
 reg reset_finished;
 reg read_valid;
 reg [31:0] read_data;
 wire write_reset=ctrl.awwvalid && ctrl.awwready && ctrl.awwaddr[17:0]==18'h70;
 assign ctrl.awwready=!bus_reset;
 assign ctrl.arready=!bus_reset && !read_valid;
 assign ctrl.rvalid=read_valid;
 assign ctrl.rdata=read_data;
 always @(posedge clk) begin
  if (!global_reset_n) begin
   soft_reset<=0;count<=0;reset_finished<=0;
  end else if(write_reset) begin
   soft_reset<=ctrl.awwdata[0];count<=0;reset_finished<=0;
  end else if(soft_reset) begin
   if(count==100) begin soft_reset<=0;count<=0;reset_finished<=1;end
   else count<=count+1'b1;
  end
 end
 always @(posedge clk) begin
  if(bus_reset || !global_reset_n) begin read_valid<=0;read_data<=0;end
  else begin
   if(ctrl.rvalid && ctrl.rready)read_valid<=0;
   if(ctrl.arvalid && ctrl.arready) begin
    read_valid<=1;
    case(ctrl.araddr[17:0])
     18'h0:read_data<=0; // obsolete video test IRQ remains inactive
     18'h70:read_data<={31'b0,soft_reset};
     18'h74:read_data<={31'b0,reset_finished};
     18'h7c:read_data<=32'h4c534332; // LSC2, dedicated control identity
     default:read_data<=UNUSED;
    endcase
   end
  end
 end
endmodule
