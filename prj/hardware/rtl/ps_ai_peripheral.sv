//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : ps_ai_peripheral.sv
// Author        : 
// Project       : 
// Create Date   : 2026.03.20
// Description   :
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================

module ps_ai_peripheral (
  // PS DDR
  inout     [53 : 0]     FIXED_IO_0_mio             ,
  inout     [14 : 0]     DDR_0_addr                 , 
  inout     [2  : 0]     DDR_0_ba                   , 
  inout                  DDR_0_cas_n                , 
  inout                  DDR_0_ck_n                 , 
  inout                  DDR_0_ck_p                 , 
  inout                  DDR_0_cke                  , 
  inout                  DDR_0_cs_n                 , 
  inout     [3  : 0]     DDR_0_dm                   , 
  inout     [31 : 0]     DDR_0_dq                   , 
  inout     [3  : 0]     DDR_0_dqs_n                , 
  inout     [3  : 0]     DDR_0_dqs_p                , 
  inout                  DDR_0_odt                  , 
  inout                  DDR_0_ras_n                , 
  inout                  DDR_0_reset_n              , 
  inout                  DDR_0_we_n                 , 
  inout                  FIXED_IO_0_ddr_vrn         , 
  inout                  FIXED_IO_0_ddr_vrp         , 
  inout                  FIXED_IO_0_ps_clk          ,
  inout                  FIXED_IO_0_ps_porb         ,
  inout                  FIXED_IO_0_ps_srstb        ,

  // PL DDR  
  inout     [ 63 : 0]    ddr3_dq                    ,
  inout     [  7 : 0]    ddr3_dqs_n                 ,
  inout     [  7 : 0]    ddr3_dqs_p                 ,
  output    [  7 : 0]    ddr3_dm                    ,
  output    [ 14 : 0]    ddr3_addr                  ,
  output    [  2 : 0]    ddr3_ba                    ,
  output                 ddr3_ras_n                 ,
  output                 ddr3_cas_n                 ,
  output                 ddr3_we_n                  ,
  output                 ddr3_reset_n               ,
  output    [  0 : 0]    ddr3_ck_p                  ,
  output    [  0 : 0]    ddr3_ck_n                  ,
  output    [  0 : 0]    ddr3_cke                   ,
  output    [  0 : 0]    ddr3_cs_n                  ,
  output    [  0 : 0]    ddr3_odt                   ,
       
  input                  sys_rst                    ,
  input                  sys_clk_p                  ,
  input                  sys_clk_n                  ,

  output    [  1 : 0]    led                       ,

  input                  PJTAG_TCK                 ,
  input                  PJTAG_TMS                 ,
  input                  PJTAG_TDI                 ,
  output                 PJTAG_TDO
);
  wire gp_clk,hp_clk,gp_clk_rst,hp_clk_rst;
  //User CustomOp REG BUS -> master ports
  wire    [ 31 : 0]    User_Reg_awwaddr          ;
  wire    [ 31 : 0]    User_Reg_awwdata          ;
  wire                 User_Reg_awwvalid         ;
  wire                  User_Reg_awwready         ;
  wire    [ 31 : 0]    User_Reg_araddr           ;
  wire                 User_Reg_arvalid          ;
  wire                  User_Reg_arready          ;
  wire     [ 31 : 0]    User_Reg_rdata            ;
  wire                  User_Reg_rvalid           ;
  wire                 User_Reg_rready           ; //User CustomOp DATA BUS -> slave ports
  wire     [ 31 : 0]    User_Ddr_awwaddr          ;
  wire     [511 : 0]    User_Ddr_awwdata          ;
  wire     [ 71 : 0]    User_Ddr_awwinfo          ; //{1'b0,pl_awen[63:0],pl_awinfo[5:0],pl_awlast[0]}
  wire                  User_Ddr_awwvalid         ;
  wire                 User_Ddr_awwready         ;
  wire     [ 31 : 0]    User_Ddr_araddr           ;
  wire                  User_Ddr_arvalid          ;
  wire     [ 31:  0]    User_Ddr_arinfo           ; //{25'h0,pl_arinfo,pl_arlast}
  wire                 User_Ddr_arready          ;
  wire    [511 : 0]    User_Ddr_rdata            ;
  wire                 User_Ddr_rvalid           ;
  wire    [ 31:  0]    User_Ddr_rinfo            ; //{25'h0,pl_rinfo,pl_rlast}
  wire                  User_Ddr_rready;



    // ************************************************************************************
    //   BUYI AI
    // ************************************************************************************
    wire          [      26 : 0]   pl_awaddr        ;
    wire          [     511 : 0]   pl_awdata        ;
    wire          [      63 : 0]   pl_awen          ;
    wire          [       5 : 0]   pl_awinfo        ; // {awdbg_4, awsts_1, awstv_1}
    wire                           pl_awlast        ;
    wire                           pl_awvalid       ;
    wire                           pl_awready       ;
    wire          [      26 : 0]   pl_araddr        ;
    wire          [       5 : 0]   pl_arinfo        ; // {ardbg_4, arstc_1, arstv_1}
    wire                           pl_arlast        ;
    wire                           pl_arvalid       ;
    wire                           pl_arready       ;
    wire          [     511 : 0]   pl_rdata         ;
    wire                           pl_rvalid        ;
    wire                           pl_rlast         ;
    wire                           pl_rready        ;
    wire          [      15 : 0]   pl_ra_awaddr     ;  //{broadcast_1, col_id_4, row_id_4, offset_7}  
    wire          [      31 : 0]   pl_ra_awdata     ;
    wire                           pl_ra_awvalid    ;
    wire                           pl_ra_awready    ;
    wire          [      15 : 0]   pl_ra_araddr     ;  //{NA_1, col_id_4, row_id_4, offset_7}  
    wire                           pl_ra_arvalid    ;
    wire                           pl_ra_arready    ;
    wire          [      31 : 0]   pl_ra_rdata      ;
    wire                           pl_ra_rvalid     ;
    wire                           pl_ra_rready     ;
    wire          [      17 : 0]   pl_int_info      ;
    wire                           pl_int_valid     ;
    wire                           pl_int_ready     ;
    wire                           pl_ra_clk        ;
    wire                           pl_itf_clk       ;
    wire                           pl_rst_n         ;
    wire                           pl_clk_en_b      ;
    wire                           pl_bist_clk      ;
    wire                           pl_bist_rstn     ;
    wire                           pl_bist_en       ;
    wire                           pl_bist_err      ;
    wire                           pl_bist_done     ;
    wire                           pl_repair_done   ;  
    wire                           pl_repair_fail   ; 
    wire                           pl_clk_div_out   ;   // for clk check, you can set false path for this signal
    wire                           pl_scan_mode_b   ;
    wire                           pl_scan_en       ;
    wire                           pl_scan_clk      ;
    wire                           pl_scan_rst_n    ;
    wire          [    83 : 0  ]   pl_scan_i        ;    
    wire          [    63 : 0  ]   pl_scan_o        ;

  // ************************************************************************************
  //   PS-PL
  // ************************************************************************************
    wire              BYolo_GP0_ARVALID;
    wire              BYolo_GP0_AWVALID;
    wire              BYolo_GP0_BREADY ;
    wire              BYolo_GP0_RREADY ;
    wire              BYolo_GP0_WLAST  ;
    wire              BYolo_GP0_WVALID ;
    wire     [11 : 0] BYolo_GP0_ARID   ;
    wire     [11 : 0] BYolo_GP0_AWID   ;
    wire     [11 : 0] BYolo_GP0_WID    ;
    wire     [1 : 0]  BYolo_GP0_ARBURST;
    wire     [1 : 0]  BYolo_GP0_ARLOCK ;
    wire     [2 : 0]  BYolo_GP0_ARSIZE ;
    wire     [1 : 0]  BYolo_GP0_AWBURST;
    wire     [1 : 0]  BYolo_GP0_AWLOCK ;
    wire     [2 : 0]  BYolo_GP0_AWSIZE ;
    wire     [2 : 0]  BYolo_GP0_ARPROT ;
    wire     [2 : 0]  BYolo_GP0_AWPROT ;
    wire     [31 : 0] BYolo_GP0_ARADDR ;
    wire     [31 : 0] BYolo_GP0_AWADDR ;
    wire     [31 : 0] BYolo_GP0_WDATA  ;
    wire     [3 : 0]  BYolo_GP0_ARCACHE;
    wire     [3 : 0]  BYolo_GP0_ARLEN  ;
    wire     [3 : 0]  BYolo_GP0_ARQOS  ;
    wire     [3 : 0]  BYolo_GP0_AWCACHE;
    wire     [3 : 0]  BYolo_GP0_AWLEN  ;
    wire     [3 : 0]  BYolo_GP0_AWQOS  ;
    wire     [3 : 0]  BYolo_GP0_WSTRB  ;
    wire              BYolo_GP0_ARREADY;
    wire              BYolo_GP0_AWREADY;
    wire              BYolo_GP0_BVALID ;
    wire              BYolo_GP0_RLAST  ;
    wire              BYolo_GP0_RVALID ;
    wire              BYolo_GP0_WREADY ;
    wire     [11 : 0] BYolo_GP0_BID    ;
    wire     [11 : 0] BYolo_GP0_RID    ;
    wire     [1 : 0]  BYolo_GP0_BRESP  ;
    wire     [1 : 0]  BYolo_GP0_RRESP  ;
    wire     [31 : 0] BYolo_GP0_RDATA  ;
    
    wire              BYolo_GP1_ARVALID;
    wire              BYolo_GP1_AWVALID;
    wire              BYolo_GP1_BREADY ;
    wire              BYolo_GP1_RREADY ;
    wire              BYolo_GP1_WLAST  ;
    wire              BYolo_GP1_WVALID ;
    wire     [11 : 0] BYolo_GP1_ARID   ;
    wire     [11 : 0] BYolo_GP1_AWID   ;
    wire     [11 : 0] BYolo_GP1_WID    ;
    wire     [1 : 0]  BYolo_GP1_ARBURST;
    wire     [1 : 0]  BYolo_GP1_ARLOCK ;
    wire     [2 : 0]  BYolo_GP1_ARSIZE ;
    wire     [1 : 0]  BYolo_GP1_AWBURST;
    wire     [1 : 0]  BYolo_GP1_AWLOCK ;
    wire     [2 : 0]  BYolo_GP1_AWSIZE ;
    wire     [2 : 0]  BYolo_GP1_ARPROT ;
    wire     [2 : 0]  BYolo_GP1_AWPROT ;
    wire     [31 : 0] BYolo_GP1_ARADDR ;
    wire     [31 : 0] BYolo_GP1_AWADDR ;
    wire     [31 : 0] BYolo_GP1_WDATA  ;
    wire     [3 : 0]  BYolo_GP1_ARCACHE;
    wire     [3 : 0]  BYolo_GP1_ARLEN  ;
    wire     [3 : 0]  BYolo_GP1_ARQOS  ;
    wire     [3 : 0]  BYolo_GP1_AWCACHE;
    wire     [3 : 0]  BYolo_GP1_AWLEN  ;
    wire     [3 : 0]  BYolo_GP1_AWQOS  ;
    wire     [3 : 0]  BYolo_GP1_WSTRB  ;
    wire              BYolo_GP1_ARREADY;
    wire              BYolo_GP1_AWREADY;
    wire              BYolo_GP1_BVALID ;
    wire              BYolo_GP1_RLAST  ;
    wire              BYolo_GP1_RVALID ;
    wire              BYolo_GP1_WREADY ;
    wire     [11 : 0] BYolo_GP1_BID    ;
    wire     [11 : 0] BYolo_GP1_RID    ;
    wire     [1 : 0]  BYolo_GP1_BRESP  ;
    wire     [1 : 0]  BYolo_GP1_RRESP  ;
    wire     [31 : 0] BYolo_GP1_RDATA  ;

    wire              User_GP0_ARVALID;
    wire              User_GP0_AWVALID;
    wire              User_GP0_BREADY ;
    wire              User_GP0_RREADY ;
    wire              User_GP0_WLAST  ;
    wire              User_GP0_WVALID ;
    wire     [11 : 0] User_GP0_ARID   ;
    wire     [11 : 0] User_GP0_AWID   ;
    wire     [11 : 0] User_GP0_WID    ;
    wire     [1 : 0]  User_GP0_ARBURST;
    wire     [1 : 0]  User_GP0_ARLOCK ;
    wire     [2 : 0]  User_GP0_ARSIZE ;
    wire     [1 : 0]  User_GP0_AWBURST;
    wire     [1 : 0]  User_GP0_AWLOCK ;
    wire     [2 : 0]  User_GP0_AWSIZE ;
    wire     [2 : 0]  User_GP0_ARPROT ;
    wire     [2 : 0]  User_GP0_AWPROT ;
    wire     [31 : 0] User_GP0_ARADDR ;
    wire     [31 : 0] User_GP0_AWADDR ;
    wire     [31 : 0] User_GP0_WDATA  ;
    wire     [3 : 0]  User_GP0_ARCACHE;
    wire     [3 : 0]  User_GP0_ARLEN  ;
    wire     [3 : 0]  User_GP0_ARQOS  ;
    wire     [3 : 0]  User_GP0_AWCACHE;
    wire     [3 : 0]  User_GP0_AWLEN  ;
    wire     [3 : 0]  User_GP0_AWQOS  ;
    wire     [3 : 0]  User_GP0_WSTRB  ;
    wire              User_GP0_ACLK   ;
    wire              User_GP0_ARREADY;
    wire              User_GP0_AWREADY;
    wire              User_GP0_BVALID ;
    wire              User_GP0_RLAST  ;
    wire              User_GP0_RVALID ;
    wire              User_GP0_WREADY ;
    wire     [11 : 0] User_GP0_BID    ;
    wire     [11 : 0] User_GP0_RID    ;
    wire     [1 : 0]  User_GP0_BRESP  ;
    wire     [1 : 0]  User_GP0_RRESP  ;
    wire     [31 : 0] User_GP0_RDATA  ;
    
    wire              User_GP1_ARVALID;
    wire              User_GP1_AWVALID;
    wire              User_GP1_BREADY ;
    wire              User_GP1_RREADY ;
    wire              User_GP1_WLAST  ;
    wire              User_GP1_WVALID ;
    wire     [11 : 0] User_GP1_ARID   ;
    wire     [11 : 0] User_GP1_AWID   ;
    wire     [11 : 0] User_GP1_WID    ;
    wire     [1 : 0]  User_GP1_ARBURST;
    wire     [1 : 0]  User_GP1_ARLOCK ;
    wire     [2 : 0]  User_GP1_ARSIZE ;
    wire     [1 : 0]  User_GP1_AWBURST;
    wire     [1 : 0]  User_GP1_AWLOCK ;
    wire     [2 : 0]  User_GP1_AWSIZE ;
    wire     [2 : 0]  User_GP1_ARPROT ;
    wire     [2 : 0]  User_GP1_AWPROT ;
    wire     [31 : 0] User_GP1_ARADDR ;
    wire     [31 : 0] User_GP1_AWADDR ;
    wire     [31 : 0] User_GP1_WDATA  ;
    wire     [3 : 0]  User_GP1_ARCACHE;
    wire     [3 : 0]  User_GP1_ARLEN  ;
    wire     [3 : 0]  User_GP1_ARQOS  ;
    wire     [3 : 0]  User_GP1_AWCACHE;
    wire     [3 : 0]  User_GP1_AWLEN  ;
    wire     [3 : 0]  User_GP1_AWQOS  ;
    wire     [3 : 0]  User_GP1_WSTRB  ;
    wire              User_GP1_ACLK   ;
    wire              User_GP1_ARREADY;
    wire              User_GP1_AWREADY;
    wire              User_GP1_BVALID ;
    wire              User_GP1_RLAST  ;
    wire              User_GP1_RVALID ;
    wire              User_GP1_WREADY ;
    wire     [11 : 0] User_GP1_BID    ;
    wire     [11 : 0] User_GP1_RID    ;
    wire     [1 : 0]  User_GP1_BRESP  ;
    wire     [1 : 0]  User_GP1_RRESP  ;
    wire     [31 : 0] User_GP1_RDATA  ;



    wire              S_AXI_HP2_ARREADY       ;
    wire              S_AXI_HP2_AWREADY       ;
    wire              S_AXI_HP2_BVALID        ;
    wire              S_AXI_HP2_RLAST         ;
    wire              S_AXI_HP2_RVALID        ;
    wire              S_AXI_HP2_WREADY        ;
    wire     [1 : 0]  S_AXI_HP2_BRESP         ;
    wire     [1 : 0]  S_AXI_HP2_RRESP         ;
    wire     [4 : 0]  S_AXI_HP2_BID           ;
    wire     [4 : 0]  S_AXI_HP2_RID           ;
    wire     [63 : 0] S_AXI_HP2_RDATA         ;
    wire              S_AXI_HP2_ARVALID       ;
    wire              S_AXI_HP2_AWVALID       ;
    wire              S_AXI_HP2_BREADY        ;
    wire              S_AXI_HP2_RREADY        ;
    wire              S_AXI_HP2_WLAST         ;
    wire              S_AXI_HP2_WVALID        ;
    wire    [1 : 0]   S_AXI_HP2_ARBURST       ;
    wire    [1 : 0]   S_AXI_HP2_ARLOCK        ;
    wire    [2 : 0]   S_AXI_HP2_ARSIZE        ;
    wire    [1 : 0]   S_AXI_HP2_AWBURST       ;
    wire    [1 : 0]   S_AXI_HP2_AWLOCK        ;
    wire    [2 : 0]   S_AXI_HP2_AWSIZE        ;
    wire    [2 : 0]   S_AXI_HP2_ARPROT        ;
    wire    [2 : 0]   S_AXI_HP2_AWPROT        ;
    wire    [31 : 0]  S_AXI_HP2_ARADDR        ;
    wire    [31 : 0]  S_AXI_HP2_AWADDR        ;
    wire    [3 : 0]   S_AXI_HP2_ARCACHE       ;
    wire    [3 : 0]   S_AXI_HP2_ARLEN         ;
    wire    [3 : 0]   S_AXI_HP2_ARQOS         ;
    wire    [3 : 0]   S_AXI_HP2_AWCACHE       ;
    wire    [3 : 0]   S_AXI_HP2_AWLEN         ;
    wire    [3 : 0]   S_AXI_HP2_AWQOS         ;
    wire    [4 : 0]   S_AXI_HP2_ARID          ;
    wire    [4 : 0]   S_AXI_HP2_AWID          ;
    wire    [4 : 0]   S_AXI_HP2_WID           ;
    wire    [63 : 0]  S_AXI_HP2_WDATA         ;
    wire    [7 : 0]   S_AXI_HP2_WSTRB         ;


    // HP_HC
    wire             S0_AXI_HP_HC_ARREADY     ;
    wire             S0_AXI_HP_HC_AWREADY     ;
    wire             S0_AXI_HP_HC_BVALID      ;
    wire             S0_AXI_HP_HC_RLAST       ;
    wire             S0_AXI_HP_HC_RVALID      ;
    wire             S0_AXI_HP_HC_WREADY      ;
    wire   [1 : 0  ] S0_AXI_HP_HC_BRESP       ;
    wire   [1 : 0  ] S0_AXI_HP_HC_RRESP       ;
    wire   [4 : 0  ] S0_AXI_HP_HC_BID         ;
    wire   [4 : 0  ] S0_AXI_HP_HC_RID         ;
    wire   [63: 0  ] S0_AXI_HP_HC_RDATA       ;
    wire             S0_AXI_HP_HC_ARVALID     ;
    wire             S0_AXI_HP_HC_AWVALID     ;
    wire             S0_AXI_HP_HC_BREADY      ;
    wire             S0_AXI_HP_HC_RREADY      ;
    wire             S0_AXI_HP_HC_WLAST       ;
    wire             S0_AXI_HP_HC_WVALID      ;
    wire   [1 : 0  ] S0_AXI_HP_HC_ARBURST     ;
    wire   [1 : 0  ] S0_AXI_HP_HC_ARLOCK      ;
    wire   [2 : 0  ] S0_AXI_HP_HC_ARSIZE      ;
    wire   [1 : 0  ] S0_AXI_HP_HC_AWBURST     ;
    wire   [1 : 0  ] S0_AXI_HP_HC_AWLOCK      ;
    wire   [2 : 0  ] S0_AXI_HP_HC_AWSIZE      ;
    wire   [2 : 0  ] S0_AXI_HP_HC_ARPROT      ;
    wire   [2 : 0  ] S0_AXI_HP_HC_AWPROT      ;
    wire   [31: 0  ] S0_AXI_HP_HC_ARADDR      ;
    wire   [31: 0  ] S0_AXI_HP_HC_AWADDR      ;
    wire   [3 : 0  ] S0_AXI_HP_HC_ARCACHE     ;
    wire   [3 : 0  ] S0_AXI_HP_HC_ARLEN       ;
    wire   [3 : 0  ] S0_AXI_HP_HC_ARQOS       ;
    wire   [3 : 0  ] S0_AXI_HP_HC_AWCACHE     ;
    wire   [3 : 0  ] S0_AXI_HP_HC_AWLEN       ;
    wire   [3 : 0  ] S0_AXI_HP_HC_AWQOS       ;
    wire   [4 : 0  ] S0_AXI_HP_HC_ARID        ;
    wire   [4 : 0  ] S0_AXI_HP_HC_AWID        ;
    wire   [4 : 0  ] S0_AXI_HP_HC_WID         ;
    wire   [63: 0  ] S0_AXI_HP_HC_WDATA       ;
    wire   [7 : 0  ] S0_AXI_HP_HC_WSTRB       ;    

    wire             S1_AXI_HP_HC_ARREADY     ;
    wire             S1_AXI_HP_HC_AWREADY     ;
    wire             S1_AXI_HP_HC_BVALID      ;
    wire             S1_AXI_HP_HC_RLAST       ;
    wire             S1_AXI_HP_HC_RVALID      ;
    wire             S1_AXI_HP_HC_WREADY      ;
    wire   [1 : 0  ] S1_AXI_HP_HC_BRESP       ;
    wire   [1 : 0  ] S1_AXI_HP_HC_RRESP       ;
    wire   [4 : 0  ] S1_AXI_HP_HC_BID         ;
    wire   [4 : 0  ] S1_AXI_HP_HC_RID         ;
    wire   [63: 0  ] S1_AXI_HP_HC_RDATA       ;
    wire             S1_AXI_HP_HC_ARVALID     ;
    wire             S1_AXI_HP_HC_AWVALID     ;
    wire             S1_AXI_HP_HC_BREADY      ;
    wire             S1_AXI_HP_HC_RREADY      ;
    wire             S1_AXI_HP_HC_WLAST       ;
    wire             S1_AXI_HP_HC_WVALID      ;
    wire   [1 : 0  ] S1_AXI_HP_HC_ARBURST     ;
    wire   [1 : 0  ] S1_AXI_HP_HC_ARLOCK      ;
    wire   [2 : 0  ] S1_AXI_HP_HC_ARSIZE      ;
    wire   [1 : 0  ] S1_AXI_HP_HC_AWBURST     ;
    wire   [1 : 0  ] S1_AXI_HP_HC_AWLOCK      ;
    wire   [2 : 0  ] S1_AXI_HP_HC_AWSIZE      ;
    wire   [2 : 0  ] S1_AXI_HP_HC_ARPROT      ;
    wire   [2 : 0  ] S1_AXI_HP_HC_AWPROT      ;
    wire   [31: 0  ] S1_AXI_HP_HC_ARADDR      ;
    wire   [31: 0  ] S1_AXI_HP_HC_AWADDR      ;
    wire   [3 : 0  ] S1_AXI_HP_HC_ARCACHE     ;
    wire   [3 : 0  ] S1_AXI_HP_HC_ARLEN       ;
    wire   [3 : 0  ] S1_AXI_HP_HC_ARQOS       ;
    wire   [3 : 0  ] S1_AXI_HP_HC_AWCACHE     ;
    wire   [3 : 0  ] S1_AXI_HP_HC_AWLEN       ;
    wire   [3 : 0  ] S1_AXI_HP_HC_AWQOS       ;
    wire   [4 : 0  ] S1_AXI_HP_HC_ARID        ;
    wire   [4 : 0  ] S1_AXI_HP_HC_AWID        ;
    wire   [4 : 0  ] S1_AXI_HP_HC_WID         ;
    wire   [63: 0  ] S1_AXI_HP_HC_WDATA       ;
    wire   [7 : 0  ] S1_AXI_HP_HC_WSTRB       ; 

    wire             S2_AXI_HP_HC_ARREADY     ;
    wire             S2_AXI_HP_HC_AWREADY     ;
    wire             S2_AXI_HP_HC_BVALID      ;
    wire             S2_AXI_HP_HC_RLAST       ;
    wire             S2_AXI_HP_HC_RVALID      ;
    wire             S2_AXI_HP_HC_WREADY      ;
    wire   [1 : 0  ] S2_AXI_HP_HC_BRESP       ;
    wire   [1 : 0  ] S2_AXI_HP_HC_RRESP       ;
    wire   [4 : 0  ] S2_AXI_HP_HC_BID         ;
    wire   [4 : 0  ] S2_AXI_HP_HC_RID         ;
    wire   [63: 0  ] S2_AXI_HP_HC_RDATA       ;
    wire             S2_AXI_HP_HC_ARVALID     ;
    wire             S2_AXI_HP_HC_AWVALID     ;
    wire             S2_AXI_HP_HC_BREADY      ;
    wire             S2_AXI_HP_HC_RREADY      ;
    wire             S2_AXI_HP_HC_WLAST       ;
    wire             S2_AXI_HP_HC_WVALID      ;
    wire   [1 : 0  ] S2_AXI_HP_HC_ARBURST     ;
    wire   [1 : 0  ] S2_AXI_HP_HC_ARLOCK      ;
    wire   [2 : 0  ] S2_AXI_HP_HC_ARSIZE      ;
    wire   [1 : 0  ] S2_AXI_HP_HC_AWBURST     ;
    wire   [1 : 0  ] S2_AXI_HP_HC_AWLOCK      ;
    wire   [2 : 0  ] S2_AXI_HP_HC_AWSIZE      ;
    wire   [2 : 0  ] S2_AXI_HP_HC_ARPROT      ;
    wire   [2 : 0  ] S2_AXI_HP_HC_AWPROT      ;
    wire   [31: 0  ] S2_AXI_HP_HC_ARADDR      ;
    wire   [31: 0  ] S2_AXI_HP_HC_AWADDR      ;
    wire   [3 : 0  ] S2_AXI_HP_HC_ARCACHE     ;
    wire   [3 : 0  ] S2_AXI_HP_HC_ARLEN       ;
    wire   [3 : 0  ] S2_AXI_HP_HC_ARQOS       ;
    wire   [3 : 0  ] S2_AXI_HP_HC_AWCACHE     ;
    wire   [3 : 0  ] S2_AXI_HP_HC_AWLEN       ;
    wire   [3 : 0  ] S2_AXI_HP_HC_AWQOS       ;
    wire   [4 : 0  ] S2_AXI_HP_HC_ARID        ;
    wire   [4 : 0  ] S2_AXI_HP_HC_AWID        ;
    wire   [4 : 0  ] S2_AXI_HP_HC_WID         ;
    wire   [63: 0  ] S2_AXI_HP_HC_WDATA       ;
    wire   [7 : 0  ] S2_AXI_HP_HC_WSTRB       ; 

    wire             S3_AXI_HP_HC_ARREADY     ;
    wire             S3_AXI_HP_HC_AWREADY     ;
    wire             S3_AXI_HP_HC_BVALID      ;
    wire             S3_AXI_HP_HC_RLAST       ;
    wire             S3_AXI_HP_HC_RVALID      ;
    wire             S3_AXI_HP_HC_WREADY      ;
    wire   [1 : 0  ] S3_AXI_HP_HC_BRESP       ;
    wire   [1 : 0  ] S3_AXI_HP_HC_RRESP       ;
    wire   [4 : 0  ] S3_AXI_HP_HC_BID         ;
    wire   [4 : 0  ] S3_AXI_HP_HC_RID         ;
    wire   [63: 0  ] S3_AXI_HP_HC_RDATA       ;
    wire             S3_AXI_HP_HC_ARVALID     ;
    wire             S3_AXI_HP_HC_AWVALID     ;
    wire             S3_AXI_HP_HC_BREADY      ;
    wire             S3_AXI_HP_HC_RREADY      ;
    wire             S3_AXI_HP_HC_WLAST       ;
    wire             S3_AXI_HP_HC_WVALID      ;
    wire   [1 : 0  ] S3_AXI_HP_HC_ARBURST     ;
    wire   [1 : 0  ] S3_AXI_HP_HC_ARLOCK      ;
    wire   [2 : 0  ] S3_AXI_HP_HC_ARSIZE      ;
    wire   [1 : 0  ] S3_AXI_HP_HC_AWBURST     ;
    wire   [1 : 0  ] S3_AXI_HP_HC_AWLOCK      ;
    wire   [2 : 0  ] S3_AXI_HP_HC_AWSIZE      ;
    wire   [2 : 0  ] S3_AXI_HP_HC_ARPROT      ;
    wire   [2 : 0  ] S3_AXI_HP_HC_AWPROT      ;
    wire   [31: 0  ] S3_AXI_HP_HC_ARADDR      ;
    wire   [31: 0  ] S3_AXI_HP_HC_AWADDR      ;
    wire   [3 : 0  ] S3_AXI_HP_HC_ARCACHE     ;
    wire   [3 : 0  ] S3_AXI_HP_HC_ARLEN       ;
    wire   [3 : 0  ] S3_AXI_HP_HC_ARQOS       ;
    wire   [3 : 0  ] S3_AXI_HP_HC_AWCACHE     ;
    wire   [3 : 0  ] S3_AXI_HP_HC_AWLEN       ;
    wire   [3 : 0  ] S3_AXI_HP_HC_AWQOS       ;
    wire   [4 : 0  ] S3_AXI_HP_HC_ARID        ;
    wire   [4 : 0  ] S3_AXI_HP_HC_AWID        ;
    wire   [4 : 0  ] S3_AXI_HP_HC_WID         ;
    wire   [63: 0  ] S3_AXI_HP_HC_WDATA       ;
    wire   [7 : 0  ] S3_AXI_HP_HC_WSTRB       ;    

    wire              FCLK_RESET0_N           ;

    wire    [28 : 0 ] app_addr                ;
    wire    [2 : 0  ] app_cmd                 ;
    wire              app_en                  ;
    wire [64*8-1 : 0] app_wdf_data            ;
    wire [64-1   : 0] app_wdf_mask            ;
    wire [64*8-1 : 0] app_rd_data             ;
    wire              app_wdf_end             ;
    wire              app_wdf_wren            ;
    wire              app_rd_data_end         ; 
    wire              app_rd_data_valid       ; 
    wire              app_rdy                 ; 
    wire              app_wdf_rdy             ; 

  // ************************************************************************************
  //   reset and clocks
  // ************************************************************************************
  wire              soft_rst            ;
  wire              sys_rst_n           ;
  wire              clk_200mhz          ;
  wire              ddr_clk_rst         ;
  wire              ps_clk_out          ;  
  wire              ddr_clk             ;
  wire              ddr_ui_rst          ; // not use
  wire              ddr3_init_done      ;
  wire              ddr_clk_led         ;
  wire              ps_clk_led          ;

  wire              customop_irq        ;
  wire              ai_irq              ; 
  wire              pl_bist_err_inv     ; 
  wire              pl_bvalid           ;
  wire              pl_bready           ;
  wire              pll_lock            ; 
  //************************************

  mna_gp_ww_itf  gp0();
  mna_gp_ww_itf  gp1();
  mna_gp_ww_itf  host_ctrl()  ;
  mna_gp_ww_itf  ai_ra()      ;
  mna_gp_ww_itf  system_ctrl()        ;
  mna_gp_ww_itf  user_op()    ;

  assign sys_rst_n    = ~sys_rst                   ;
  assign led[0]     = ddr3_init_done & ddr_clk_led ;
  assign led[1] = ps_clk_led;


demo_clkrst_wrapper u_demo_clkrst_wrapper(
  .ddr_clk_led (ddr_clk_led ),
  .ps_clk_led  (ps_clk_led  ),

  .sys_rst     (sys_rst | (~FCLK_RESET0_N)),
  .soft_rst    (soft_rst    ),

  .ddr_clk     (ddr_clk     ),
  .ps_clk_out  (ps_clk_out  ),

  .gp_clk      (gp_clk      ),
  .hp_clk      (hp_clk      ),
  .gp_clk_rst  (gp_clk_rst  ),
  .hp_clk_rst  (hp_clk_rst  ),
  .ddr_clk_rst (ddr_clk_rst )
);

gp_io u_gp0_io(
  .M_AXI_GP_ARVALID (User_GP0_ARVALID ),
  .M_AXI_GP_AWVALID (User_GP0_AWVALID ),
  .M_AXI_GP_BREADY  (User_GP0_BREADY  ),
  .M_AXI_GP_RREADY  (User_GP0_RREADY  ),
  .M_AXI_GP_WLAST   (User_GP0_WLAST   ),
  .M_AXI_GP_WVALID  (User_GP0_WVALID  ),
  .M_AXI_GP_ARID    (User_GP0_ARID    ),
  .M_AXI_GP_AWID    (User_GP0_AWID    ),
  .M_AXI_GP_WID     (User_GP0_WID     ),
  .M_AXI_GP_ARBURST (User_GP0_ARBURST ),
  .M_AXI_GP_ARLOCK  (User_GP0_ARLOCK  ),
  .M_AXI_GP_ARSIZE  (User_GP0_ARSIZE  ),
  .M_AXI_GP_AWBURST (User_GP0_AWBURST ),
  .M_AXI_GP_AWLOCK  (User_GP0_AWLOCK  ),
  .M_AXI_GP_AWSIZE  (User_GP0_AWSIZE  ),
  .M_AXI_GP_ARPROT  (User_GP0_ARPROT  ),
  .M_AXI_GP_AWPROT  (User_GP0_AWPROT  ),
  .M_AXI_GP_ARADDR  (User_GP0_ARADDR  ),
  .M_AXI_GP_AWADDR  (User_GP0_AWADDR  ),
  .M_AXI_GP_WDATA   (User_GP0_WDATA   ),
  .M_AXI_GP_ARCACHE (User_GP0_ARCACHE ),
  .M_AXI_GP_ARLEN   (User_GP0_ARLEN   ),
  .M_AXI_GP_ARQOS   (User_GP0_ARQOS   ),
  .M_AXI_GP_AWCACHE (User_GP0_AWCACHE ),
  .M_AXI_GP_AWLEN   (User_GP0_AWLEN   ),
  .M_AXI_GP_AWQOS   (User_GP0_AWQOS   ),
  .M_AXI_GP_WSTRB   (User_GP0_WSTRB   ),
  .M_AXI_GP_ACLK    (User_GP0_ACLK    ),
  .M_AXI_GP_ARREADY (User_GP0_ARREADY ),
  .M_AXI_GP_AWREADY (User_GP0_AWREADY ),
  .M_AXI_GP_BVALID  (User_GP0_BVALID  ),
  .M_AXI_GP_RLAST   (User_GP0_RLAST   ),
  .M_AXI_GP_RVALID  (User_GP0_RVALID  ),
  .M_AXI_GP_WREADY  (User_GP0_WREADY  ),
  .M_AXI_GP_BID     (User_GP0_BID     ),
  .M_AXI_GP_RID     (User_GP0_RID     ),
  .M_AXI_GP_BRESP   (User_GP0_BRESP   ),
  .M_AXI_GP_RRESP   (User_GP0_RRESP   ),
  .M_AXI_GP_RDATA   (User_GP0_RDATA   ),
  .gp               (gp0.master       ),
  .gp_clk_rst       (gp_clk_rst       ),
  .gp_clk           (gp_clk           )
);

gp0_manager 
#(
  .GP0_BASE       (32'h40000000       )
)
u_gp0_manager(
  .gpx       (gp0.slave            ),
  .host_ctrl (host_ctrl.master     ), // not used
  .ai_ra     (ai_ra.master         ), // not used
  .m2_gpx    (system_ctrl.master           ),
  .m3_gpx    (user_op.master       ),
  .gpx_rst   (gp_clk_rst           ),
  .gpx_clk   (gp_clk               )
);

gpx_RFU  #(.ERR(32'hA0AAAAAA)) u_host_ctrl_RFU(
  .gpx             (host_ctrl.slave            ),    
  .gpx_rst         (gp_clk_rst                 ),
  .gpx_clk         (gp_clk                     )
);

gpx_RFU  #(.ERR(32'hA0AAAAAA)) u_ai_ra_RFU(
  .gpx             (ai_ra.slave                ),    
  .gpx_rst         (gp_clk_rst                 ),
  .gpx_clk         (gp_clk                     )
);

assign User_Reg_araddr   = user_op.araddr   ;   
assign User_Reg_arvalid  = user_op.arvalid  ; 
assign User_Reg_rready   = user_op.rready   ;   
assign User_Reg_awwaddr  = user_op.awwaddr  ;   
assign User_Reg_awwdata  = user_op.awwdata  ;   
assign User_Reg_awwvalid = user_op.awwvalid ;   
assign user_op.arready   = User_Reg_arready  ;
assign user_op.rdata     = User_Reg_rdata    ;
assign user_op.rvalid    = User_Reg_rvalid   ;
assign user_op.awwready  = User_Reg_awwready ;

gp_io u_gp1_io(
  .M_AXI_GP_ARVALID (User_GP1_ARVALID  ),
  .M_AXI_GP_AWVALID (User_GP1_AWVALID  ),
  .M_AXI_GP_BREADY  (User_GP1_BREADY   ),
  .M_AXI_GP_RREADY  (User_GP1_RREADY   ),
  .M_AXI_GP_WLAST   (User_GP1_WLAST    ),
  .M_AXI_GP_WVALID  (User_GP1_WVALID   ),
  .M_AXI_GP_ARID    (User_GP1_ARID     ),
  .M_AXI_GP_AWID    (User_GP1_AWID     ),
  .M_AXI_GP_WID     (User_GP1_WID      ),
  .M_AXI_GP_ARBURST (User_GP1_ARBURST  ),
  .M_AXI_GP_ARLOCK  (User_GP1_ARLOCK   ),
  .M_AXI_GP_ARSIZE  (User_GP1_ARSIZE   ),
  .M_AXI_GP_AWBURST (User_GP1_AWBURST  ),
  .M_AXI_GP_AWLOCK  (User_GP1_AWLOCK   ),
  .M_AXI_GP_AWSIZE  (User_GP1_AWSIZE   ),
  .M_AXI_GP_ARPROT  (User_GP1_ARPROT   ),
  .M_AXI_GP_AWPROT  (User_GP1_AWPROT   ),
  .M_AXI_GP_ARADDR  (User_GP1_ARADDR   ),
  .M_AXI_GP_AWADDR  (User_GP1_AWADDR   ),
  .M_AXI_GP_WDATA   (User_GP1_WDATA    ),
  .M_AXI_GP_ARCACHE (User_GP1_ARCACHE  ),
  .M_AXI_GP_ARLEN   (User_GP1_ARLEN    ),
  .M_AXI_GP_ARQOS   (User_GP1_ARQOS    ),
  .M_AXI_GP_AWCACHE (User_GP1_AWCACHE  ),
  .M_AXI_GP_AWLEN   (User_GP1_AWLEN    ),
  .M_AXI_GP_AWQOS   (User_GP1_AWQOS    ),
  .M_AXI_GP_WSTRB   (User_GP1_WSTRB    ),
  .M_AXI_GP_ACLK    (User_GP1_ACLK     ),
  .M_AXI_GP_ARREADY (User_GP1_ARREADY  ),
  .M_AXI_GP_AWREADY (User_GP1_AWREADY  ),
  .M_AXI_GP_BVALID  (User_GP1_BVALID   ),
  .M_AXI_GP_RLAST   (User_GP1_RLAST    ),
  .M_AXI_GP_RVALID  (User_GP1_RVALID   ),
  .M_AXI_GP_WREADY  (User_GP1_WREADY   ),
  .M_AXI_GP_BID     (User_GP1_BID      ),
  .M_AXI_GP_RID     (User_GP1_RID      ),
  .M_AXI_GP_BRESP   (User_GP1_BRESP    ),
  .M_AXI_GP_RRESP   (User_GP1_RRESP    ),
  .M_AXI_GP_RDATA   (User_GP1_RDATA    ),
  .gp               (gp1.master        ),
  .gp_clk_rst       (gp_clk_rst        ),
  .gp_clk           (gp_clk            )
);

gpx_RFU  #(.ERR(32'hB0AAAAAA)) u_cdma_ctrl_RFU(
  .gpx             (gp1.slave                 ),    
  .gpx_rst         (gp_clk_rst                ),
  .gpx_clk         (gp_clk                    )
);

lss_system_ctrl u_system_ctrl (
 .clk(gp_clk),.bus_reset(gp_clk_rst),
 .global_reset_n(sys_rst_n & FCLK_RESET0_N),
 .ctrl(system_ctrl.slave),.soft_reset(soft_rst)
);

assign S_AXI_HP2_AWID = 0;
assign S_AXI_HP2_AWADDR = 0;
assign S_AXI_HP2_AWLEN = 0;
assign S_AXI_HP2_AWSIZE = 3;
assign S_AXI_HP2_AWBURST = 1;
assign S_AXI_HP2_AWLOCK = 0;
assign S_AXI_HP2_AWCACHE = 0;
assign S_AXI_HP2_AWPROT = 0;
assign S_AXI_HP2_AWQOS = 0;
assign S_AXI_HP2_AWVALID = 0;
assign S_AXI_HP2_WDATA = 0;
assign S_AXI_HP2_WSTRB = 0;
assign S_AXI_HP2_WLAST = 0;
assign S_AXI_HP2_WVALID = 0;
assign S_AXI_HP2_BREADY = 1;
assign S_AXI_HP2_ARID = 0;
assign S_AXI_HP2_ARSIZE = 3;
assign S_AXI_HP2_ARBURST = 1;
assign S_AXI_HP2_ARLOCK = 0;
assign S_AXI_HP2_ARCACHE = 0;
assign S_AXI_HP2_ARPROT = 0;
assign S_AXI_HP2_ARQOS = 0;

lss_v2_bridge u_lss_v2_bridge (
 .gp_clk(gp_clk),.gp_rst_n(~gp_clk_rst),.hp_clk(hp_clk),.hp_rst_n(~hp_clk_rst),
 .ddr_ready(ddr3_init_done & ~ddr_ui_rst),
 .ra_awaddr(User_Reg_awwaddr),.ra_awdata(User_Reg_awwdata),
 .ra_awvalid(User_Reg_awwvalid),.ra_awready(User_Reg_awwready),
 .ra_araddr(User_Reg_araddr),.ra_arvalid(User_Reg_arvalid),.ra_arready(User_Reg_arready),
 .ra_rdata(User_Reg_rdata),.ra_rvalid(User_Reg_rvalid),.ra_rready(User_Reg_rready),
 .ps_araddr(S_AXI_HP2_ARADDR),.ps_arlen(S_AXI_HP2_ARLEN),
 .ps_arvalid(S_AXI_HP2_ARVALID),.ps_arready(S_AXI_HP2_ARREADY),
 .ps_rdata(S_AXI_HP2_RDATA),.ps_rresp(S_AXI_HP2_RRESP),.ps_rlast(S_AXI_HP2_RLAST),
 .ps_rvalid(S_AXI_HP2_RVALID),.ps_rready(S_AXI_HP2_RREADY),
 .ddr_awaddr(User_Ddr_awwaddr),.ddr_awdata(User_Ddr_awwdata),.ddr_awinfo(User_Ddr_awwinfo),
 .ddr_awvalid(User_Ddr_awwvalid),.ddr_awready(User_Ddr_awwready),
 .ddr_araddr(User_Ddr_araddr),.ddr_arinfo(User_Ddr_arinfo),
 .ddr_arvalid(User_Ddr_arvalid),.ddr_arready(User_Ddr_arready),
 .ddr_rdata(User_Ddr_rdata),.ddr_rvalid(User_Ddr_rvalid),
 .ddr_rinfo(User_Ddr_rinfo),.ddr_rready(User_Ddr_rready)
);

wire fclk_50;
clk_wiz_0 clk_wiz_0_inst(
 .clk_out1(ps_clk_out),.clk_out2(clk_200mhz),
 .reset(1'b0),.locked(pll_lock),.clk_in1(fclk_50)
);

ps_ai_wrapper ps_ai_wrapper_u0 (
    .AI_BIST_0_pl_bist_done(pl_bist_done),
    .AI_BIST_0_pl_bist_en(pl_bist_en),
    .AI_BIST_0_pl_bist_err(pl_bist_err),
    .AI_BIST_0_pl_bist_err_inv(pl_bist_err_inv),
    .AI_BIST_0_pl_repair_done(pl_repair_done),
    .AI_BIST_0_pl_repair_fail(pl_repair_fail),
    .AI_IRQ_0_pl_int_info(pl_int_info),
    .AI_IRQ_0_pl_int_ready(pl_int_ready),
    .AI_IRQ_0_pl_int_valid(pl_int_valid),
    .AI_SCAN_0_pl_scan_compression_mode(1'b0),
    .AI_SCAN_0_pl_scan_cs('b0),
    .AI_SCAN_0_pl_scan_en(pl_scan_en),
    .AI_SCAN_0_pl_scan_in(pl_scan_i[63:0]),
    .AI_SCAN_0_pl_scan_mode_b(pl_scan_mode_b),
    .AI_SCAN_0_pl_scan_occ_bypass(1'b0),
    .AI_SCAN_0_pl_scan_occ_mode(1'b0),
    .AI_SCAN_0_pl_scan_occ_reset(1'b0),
    .AI_SCAN_0_pl_scan_out(pl_scan_o),
    .AI_SCAN_0_pl_scan_wrp_mode(1'b0),
    .AI_SCAN_0_pl_scan_wrp_shift(1'b0),
    .BYolo_GP0_araddr(BYolo_GP0_ARADDR),
    .BYolo_GP0_arburst(BYolo_GP0_ARBURST),
    .BYolo_GP0_arcache(BYolo_GP0_ARCACHE),
    .BYolo_GP0_arid(BYolo_GP0_ARID),
    .BYolo_GP0_arlen(BYolo_GP0_ARLEN),
    .BYolo_GP0_arlock(BYolo_GP0_ARLOCK),
    .BYolo_GP0_arprot(BYolo_GP0_ARPROT),
    .BYolo_GP0_arqos(BYolo_GP0_ARQOS),
    .BYolo_GP0_arready(BYolo_GP0_ARREADY),
    .BYolo_GP0_arsize(BYolo_GP0_ARSIZE),
    .BYolo_GP0_arvalid(BYolo_GP0_ARVALID),
    .BYolo_GP0_awaddr(BYolo_GP0_AWADDR),
    .BYolo_GP0_awburst(BYolo_GP0_AWBURST),
    .BYolo_GP0_awcache(BYolo_GP0_AWCACHE),
    .BYolo_GP0_awid(BYolo_GP0_AWID),
    .BYolo_GP0_awlen(BYolo_GP0_AWLEN),
    .BYolo_GP0_awlock(BYolo_GP0_AWLOCK),
    .BYolo_GP0_awprot(BYolo_GP0_AWPROT),
    .BYolo_GP0_awqos(BYolo_GP0_AWQOS),
    .BYolo_GP0_awready(BYolo_GP0_AWREADY),
    .BYolo_GP0_awsize(BYolo_GP0_AWSIZE),
    .BYolo_GP0_awvalid(BYolo_GP0_AWVALID),
    .BYolo_GP0_bid(BYolo_GP0_BID),
    .BYolo_GP0_bready(BYolo_GP0_BREADY),
    .BYolo_GP0_bresp(BYolo_GP0_BRESP),
    .BYolo_GP0_bvalid(BYolo_GP0_BVALID),
    .BYolo_GP0_rdata(BYolo_GP0_RDATA),
    .BYolo_GP0_rid(BYolo_GP0_RID),
    .BYolo_GP0_rlast(BYolo_GP0_RLAST),
    .BYolo_GP0_rready(BYolo_GP0_RREADY),
    .BYolo_GP0_rresp(BYolo_GP0_RRESP),
    .BYolo_GP0_rvalid(BYolo_GP0_RVALID),
    .BYolo_GP0_wdata(BYolo_GP0_WDATA),
    .BYolo_GP0_wid(BYolo_GP0_WID),
    .BYolo_GP0_wlast(BYolo_GP0_WLAST),
    .BYolo_GP0_wready(BYolo_GP0_WREADY),
    .BYolo_GP0_wstrb(BYolo_GP0_WSTRB),
    .BYolo_GP0_wvalid(BYolo_GP0_WVALID),
    .BYolo_GP1_araddr(BYolo_GP1_ARADDR),
    .BYolo_GP1_arburst(BYolo_GP1_ARBURST),
    .BYolo_GP1_arcache(BYolo_GP1_ARCACHE),
    .BYolo_GP1_arid(BYolo_GP1_ARID),
    .BYolo_GP1_arlen(BYolo_GP1_ARLEN),
    .BYolo_GP1_arlock(BYolo_GP1_ARLOCK),
    .BYolo_GP1_arprot(BYolo_GP1_ARPROT),
    .BYolo_GP1_arqos(BYolo_GP1_ARQOS),
    .BYolo_GP1_arready(BYolo_GP1_ARREADY),
    .BYolo_GP1_arsize(BYolo_GP1_ARSIZE),
    .BYolo_GP1_arvalid(BYolo_GP1_ARVALID),
    .BYolo_GP1_awaddr(BYolo_GP1_AWADDR),
    .BYolo_GP1_awburst(BYolo_GP1_AWBURST),
    .BYolo_GP1_awcache(BYolo_GP1_AWCACHE),
    .BYolo_GP1_awid(BYolo_GP1_AWID),
    .BYolo_GP1_awlen(BYolo_GP1_AWLEN),
    .BYolo_GP1_awlock(BYolo_GP1_AWLOCK),
    .BYolo_GP1_awprot(BYolo_GP1_AWPROT),
    .BYolo_GP1_awqos(BYolo_GP1_AWQOS),
    .BYolo_GP1_awready(BYolo_GP1_AWREADY),
    .BYolo_GP1_awsize(BYolo_GP1_AWSIZE),
    .BYolo_GP1_awvalid(BYolo_GP1_AWVALID),
    .BYolo_GP1_bid(BYolo_GP1_BID),
    .BYolo_GP1_bready(BYolo_GP1_BREADY),
    .BYolo_GP1_bresp(BYolo_GP1_BRESP),
    .BYolo_GP1_bvalid(BYolo_GP1_BVALID),
    .BYolo_GP1_rdata(BYolo_GP1_RDATA),
    .BYolo_GP1_rid(BYolo_GP1_RID),
    .BYolo_GP1_rlast(BYolo_GP1_RLAST),
    .BYolo_GP1_rready(BYolo_GP1_RREADY),
    .BYolo_GP1_rresp(BYolo_GP1_RRESP),
    .BYolo_GP1_rvalid(BYolo_GP1_RVALID),
    .BYolo_GP1_wdata(BYolo_GP1_WDATA),
    .BYolo_GP1_wid(BYolo_GP1_WID),
    .BYolo_GP1_wlast(BYolo_GP1_WLAST),
    .BYolo_GP1_wready(BYolo_GP1_WREADY),
    .BYolo_GP1_wstrb(BYolo_GP1_WSTRB),
    .BYolo_GP1_wvalid(BYolo_GP1_WVALID),
    .DDR_0_addr(DDR_0_addr),
    .DDR_0_ba(DDR_0_ba),
    .DDR_0_cas_n(DDR_0_cas_n),
    .DDR_0_ck_n(DDR_0_ck_n),
    .DDR_0_ck_p(DDR_0_ck_p),
    .DDR_0_cke(DDR_0_cke),
    .DDR_0_cs_n(DDR_0_cs_n),
    .DDR_0_dm(DDR_0_dm),
    .DDR_0_dq(DDR_0_dq),
    .DDR_0_dqs_n(DDR_0_dqs_n),
    .DDR_0_dqs_p(DDR_0_dqs_p),
    .DDR_0_odt(DDR_0_odt),
    .DDR_0_ras_n(DDR_0_ras_n),
    .DDR_0_reset_n(DDR_0_reset_n),
    .DDR_0_we_n(DDR_0_we_n),
    .FCLK_CLK0_0(fclk_50),
    .FCLK_RESET0_N_0(FCLK_RESET0_N),
    .FIXED_IO_0_ddr_vrn(FIXED_IO_0_ddr_vrn),
    .FIXED_IO_0_ddr_vrp(FIXED_IO_0_ddr_vrp),
    .FIXED_IO_0_mio(FIXED_IO_0_mio),
    .FIXED_IO_0_ps_clk(FIXED_IO_0_ps_clk),
    .FIXED_IO_0_ps_porb(FIXED_IO_0_ps_porb),
    .FIXED_IO_0_ps_srstb(FIXED_IO_0_ps_srstb),
    .M_AI_HP_0_pl_araddr(pl_araddr),
    .M_AI_HP_0_pl_arinfo(pl_arinfo),
    .M_AI_HP_0_pl_arlast(pl_arlast),
    .M_AI_HP_0_pl_arready(pl_arready),
    .M_AI_HP_0_pl_arvalid(pl_arvalid),
    .M_AI_HP_0_pl_awaddr(pl_awaddr),
    .M_AI_HP_0_pl_awdata(pl_awdata),
    .M_AI_HP_0_pl_awen(pl_awen),
    .M_AI_HP_0_pl_awinfo(pl_awinfo),
    .M_AI_HP_0_pl_awlast(pl_awlast),
    .M_AI_HP_0_pl_awready(pl_awready),
    .M_AI_HP_0_pl_awvalid(pl_awvalid),
    .M_AI_HP_0_pl_bready(pl_bready),
    .M_AI_HP_0_pl_bvalid(pl_bvalid),
    .M_AI_HP_0_pl_rdata(pl_rdata),
    .M_AI_HP_0_pl_rlast(pl_rlast),
    .M_AI_HP_0_pl_rready(pl_rready),
    .M_AI_HP_0_pl_rvalid(pl_rvalid),
    .PJTAG_0_tck(PJTAG_TCK),
    .PJTAG_0_tdi(PJTAG_TDI),
    .PJTAG_0_tdo(PJTAG_TDO),
    .PJTAG_0_tms(PJTAG_TMS),
    .S_AI_GP_0_pl_ra_araddr(pl_ra_araddr),
    .S_AI_GP_0_pl_ra_arready(pl_ra_arready),
    .S_AI_GP_0_pl_ra_arvalid(pl_ra_arvalid),
    .S_AI_GP_0_pl_ra_awaddr(pl_ra_awaddr),
    .S_AI_GP_0_pl_ra_awdata(pl_ra_awdata),
    .S_AI_GP_0_pl_ra_awready(pl_ra_awready),
    .S_AI_GP_0_pl_ra_awvalid(pl_ra_awvalid),
    .S_AI_GP_0_pl_ra_rdata(pl_ra_rdata),
    .S_AI_GP_0_pl_ra_rready(pl_ra_rready),
    .S_AI_GP_0_pl_ra_rvalid(pl_ra_rvalid),
    .S_AXI_HP0_0_araddr(S0_AXI_HP_HC_ARADDR),
    .S_AXI_HP0_0_arburst(S0_AXI_HP_HC_ARBURST),
    .S_AXI_HP0_0_arcache(S0_AXI_HP_HC_ARCACHE),
    .S_AXI_HP0_0_arid({1'b0, (S0_AXI_HP_HC_ARID)}),
    .S_AXI_HP0_0_arlen(S0_AXI_HP_HC_ARLEN),
    .S_AXI_HP0_0_arlock(S0_AXI_HP_HC_ARLOCK),
    .S_AXI_HP0_0_arprot(S0_AXI_HP_HC_ARPROT),
    .S_AXI_HP0_0_arqos(S0_AXI_HP_HC_ARQOS),
    .S_AXI_HP0_0_arready(S0_AXI_HP_HC_ARREADY),
    .S_AXI_HP0_0_arsize(S0_AXI_HP_HC_ARSIZE),
    .S_AXI_HP0_0_arvalid(S0_AXI_HP_HC_ARVALID),
    .S_AXI_HP0_0_awaddr(S0_AXI_HP_HC_AWADDR),
    .S_AXI_HP0_0_awburst(S0_AXI_HP_HC_AWBURST),
    .S_AXI_HP0_0_awcache(S0_AXI_HP_HC_AWCACHE),
    .S_AXI_HP0_0_awid({1'b0, (S0_AXI_HP_HC_AWID)}),
    .S_AXI_HP0_0_awlen(S0_AXI_HP_HC_AWLEN),
    .S_AXI_HP0_0_awlock(S0_AXI_HP_HC_AWLOCK),
    .S_AXI_HP0_0_awprot(S0_AXI_HP_HC_AWPROT),
    .S_AXI_HP0_0_awqos(S0_AXI_HP_HC_AWQOS),
    .S_AXI_HP0_0_awready(S0_AXI_HP_HC_AWREADY),
    .S_AXI_HP0_0_awsize(S0_AXI_HP_HC_AWSIZE),
    .S_AXI_HP0_0_awvalid(S0_AXI_HP_HC_AWVALID),
    .S_AXI_HP0_0_bid(S0_AXI_HP_HC_BID),
    .S_AXI_HP0_0_bready(S0_AXI_HP_HC_BREADY),
    .S_AXI_HP0_0_bresp(S0_AXI_HP_HC_BRESP),
    .S_AXI_HP0_0_bvalid(S0_AXI_HP_HC_BVALID),
    .S_AXI_HP0_0_rdata(S0_AXI_HP_HC_RDATA),
    .S_AXI_HP0_0_rid(S0_AXI_HP_HC_RID),
    .S_AXI_HP0_0_rlast(S0_AXI_HP_HC_RLAST),
    .S_AXI_HP0_0_rready(S0_AXI_HP_HC_RREADY),
    .S_AXI_HP0_0_rresp(S0_AXI_HP_HC_RRESP),
    .S_AXI_HP0_0_rvalid(S0_AXI_HP_HC_RVALID),
    .S_AXI_HP0_0_wdata(S0_AXI_HP_HC_WDATA),
    .S_AXI_HP0_0_wid({1'b0, (S0_AXI_HP_HC_WID)}),
    .S_AXI_HP0_0_wlast(S0_AXI_HP_HC_WLAST),
    .S_AXI_HP0_0_wready(S0_AXI_HP_HC_WREADY),
    .S_AXI_HP0_0_wstrb(S0_AXI_HP_HC_WSTRB),
    .S_AXI_HP0_0_wvalid(S0_AXI_HP_HC_WVALID),
    .S_AXI_HP1_0_araddr(S1_AXI_HP_HC_ARADDR),
    .S_AXI_HP1_0_arburst(S1_AXI_HP_HC_ARBURST),
    .S_AXI_HP1_0_arcache(S1_AXI_HP_HC_ARCACHE),
    .S_AXI_HP1_0_arid(S1_AXI_HP_HC_ARID),
    .S_AXI_HP1_0_arlen(S1_AXI_HP_HC_ARLEN),
    .S_AXI_HP1_0_arlock(S1_AXI_HP_HC_ARLOCK),
    .S_AXI_HP1_0_arprot(S1_AXI_HP_HC_ARPROT),
    .S_AXI_HP1_0_arqos(S1_AXI_HP_HC_ARQOS),
    .S_AXI_HP1_0_arready(S1_AXI_HP_HC_ARREADY),
    .S_AXI_HP1_0_arsize(S1_AXI_HP_HC_ARSIZE),
    .S_AXI_HP1_0_arvalid(S1_AXI_HP_HC_ARVALID),
    .S_AXI_HP1_0_awaddr(S1_AXI_HP_HC_AWADDR),
    .S_AXI_HP1_0_awburst(S1_AXI_HP_HC_AWBURST),
    .S_AXI_HP1_0_awcache(S1_AXI_HP_HC_AWCACHE),
    .S_AXI_HP1_0_awid(S1_AXI_HP_HC_AWID),
    .S_AXI_HP1_0_awlen(S1_AXI_HP_HC_AWLEN),
    .S_AXI_HP1_0_awlock(S1_AXI_HP_HC_AWLOCK),
    .S_AXI_HP1_0_awprot(S1_AXI_HP_HC_AWPROT),
    .S_AXI_HP1_0_awqos(S1_AXI_HP_HC_AWQOS),
    .S_AXI_HP1_0_awready(S1_AXI_HP_HC_AWREADY),
    .S_AXI_HP1_0_awsize(S1_AXI_HP_HC_AWSIZE),
    .S_AXI_HP1_0_awvalid(S1_AXI_HP_HC_AWVALID),
    .S_AXI_HP1_0_bid(S1_AXI_HP_HC_BID),
    .S_AXI_HP1_0_bready(S1_AXI_HP_HC_BREADY),
    .S_AXI_HP1_0_bresp(S1_AXI_HP_HC_BRESP),
    .S_AXI_HP1_0_bvalid(S1_AXI_HP_HC_BVALID),
    .S_AXI_HP1_0_rdata(S1_AXI_HP_HC_RDATA),
    .S_AXI_HP1_0_rid(S1_AXI_HP_HC_RID),
    .S_AXI_HP1_0_rlast(S1_AXI_HP_HC_RLAST),
    .S_AXI_HP1_0_rready(S1_AXI_HP_HC_RREADY),
    .S_AXI_HP1_0_rresp(S1_AXI_HP_HC_RRESP),
    .S_AXI_HP1_0_rvalid(S1_AXI_HP_HC_RVALID),
    .S_AXI_HP1_0_wdata(S1_AXI_HP_HC_WDATA),
    .S_AXI_HP1_0_wid(S1_AXI_HP_HC_WID),
    .S_AXI_HP1_0_wlast(S1_AXI_HP_HC_WLAST),
    .S_AXI_HP1_0_wready(S1_AXI_HP_HC_WREADY),
    .S_AXI_HP1_0_wstrb(S1_AXI_HP_HC_WSTRB),
    .S_AXI_HP1_0_wvalid(S1_AXI_HP_HC_WVALID),
    .S_AXI_HP2_0_araddr(S2_AXI_HP_HC_ARADDR),
    .S_AXI_HP2_0_arburst(S2_AXI_HP_HC_ARBURST),
    .S_AXI_HP2_0_arcache(S2_AXI_HP_HC_ARCACHE),
    .S_AXI_HP2_0_arid(S2_AXI_HP_HC_ARID),
    .S_AXI_HP2_0_arlen(S2_AXI_HP_HC_ARLEN),
    .S_AXI_HP2_0_arlock(S2_AXI_HP_HC_ARLOCK),
    .S_AXI_HP2_0_arprot(S2_AXI_HP_HC_ARPROT),
    .S_AXI_HP2_0_arqos(S2_AXI_HP_HC_ARQOS),
    .S_AXI_HP2_0_arready(S2_AXI_HP_HC_ARREADY),
    .S_AXI_HP2_0_arsize(S2_AXI_HP_HC_ARSIZE),
    .S_AXI_HP2_0_arvalid(S2_AXI_HP_HC_ARVALID),
    .S_AXI_HP2_0_awaddr(S2_AXI_HP_HC_AWADDR),
    .S_AXI_HP2_0_awburst(S2_AXI_HP_HC_AWBURST),
    .S_AXI_HP2_0_awcache(S2_AXI_HP_HC_AWCACHE),
    .S_AXI_HP2_0_awid(S2_AXI_HP_HC_AWID),
    .S_AXI_HP2_0_awlen(S2_AXI_HP_HC_AWLEN),
    .S_AXI_HP2_0_awlock(S2_AXI_HP_HC_AWLOCK),
    .S_AXI_HP2_0_awprot(S2_AXI_HP_HC_AWPROT),
    .S_AXI_HP2_0_awqos(S2_AXI_HP_HC_AWQOS),
    .S_AXI_HP2_0_awready(S2_AXI_HP_HC_AWREADY),
    .S_AXI_HP2_0_awsize(S2_AXI_HP_HC_AWSIZE),
    .S_AXI_HP2_0_awvalid(S2_AXI_HP_HC_AWVALID),
    .S_AXI_HP2_0_bid(S2_AXI_HP_HC_BID),
    .S_AXI_HP2_0_bready(S2_AXI_HP_HC_BREADY),
    .S_AXI_HP2_0_bresp(S2_AXI_HP_HC_BRESP),
    .S_AXI_HP2_0_bvalid(S2_AXI_HP_HC_BVALID),
    .S_AXI_HP2_0_rdata(S2_AXI_HP_HC_RDATA),
    .S_AXI_HP2_0_rid(S2_AXI_HP_HC_RID),
    .S_AXI_HP2_0_rlast(S2_AXI_HP_HC_RLAST),
    .S_AXI_HP2_0_rready(S2_AXI_HP_HC_RREADY),
    .S_AXI_HP2_0_rresp(S2_AXI_HP_HC_RRESP),
    .S_AXI_HP2_0_rvalid(S2_AXI_HP_HC_RVALID),
    .S_AXI_HP2_0_wdata(S2_AXI_HP_HC_WDATA),
    .S_AXI_HP2_0_wid(S2_AXI_HP_HC_WID),
    .S_AXI_HP2_0_wlast(S2_AXI_HP_HC_WLAST),
    .S_AXI_HP2_0_wready(S2_AXI_HP_HC_WREADY),
    .S_AXI_HP2_0_wstrb(S2_AXI_HP_HC_WSTRB),
    .S_AXI_HP2_0_wvalid(S2_AXI_HP_HC_WVALID),
    .S_AXI_HP2_1_araddr(S_AXI_HP2_ARADDR),
    .S_AXI_HP2_1_arburst(S_AXI_HP2_ARBURST),
    .S_AXI_HP2_1_arcache(S_AXI_HP2_ARCACHE),
    .S_AXI_HP2_1_arid(S_AXI_HP2_ARID),
    .S_AXI_HP2_1_arlen(S_AXI_HP2_ARLEN),
    .S_AXI_HP2_1_arlock(S_AXI_HP2_ARLOCK),
    .S_AXI_HP2_1_arprot(S_AXI_HP2_ARPROT),
    .S_AXI_HP2_1_arqos(S_AXI_HP2_ARQOS),
    .S_AXI_HP2_1_arready(S_AXI_HP2_ARREADY),
    .S_AXI_HP2_1_arsize(S_AXI_HP2_ARSIZE),
    .S_AXI_HP2_1_arvalid(S_AXI_HP2_ARVALID),
    .S_AXI_HP2_1_awaddr(S_AXI_HP2_AWADDR),
    .S_AXI_HP2_1_awburst(S_AXI_HP2_AWBURST),
    .S_AXI_HP2_1_awcache(S_AXI_HP2_AWCACHE),
    .S_AXI_HP2_1_awid(S_AXI_HP2_AWID),
    .S_AXI_HP2_1_awlen(S_AXI_HP2_AWLEN),
    .S_AXI_HP2_1_awlock(S_AXI_HP2_AWLOCK),
    .S_AXI_HP2_1_awprot(S_AXI_HP2_AWPROT),
    .S_AXI_HP2_1_awqos(S_AXI_HP2_AWQOS),
    .S_AXI_HP2_1_awready(S_AXI_HP2_AWREADY),
    .S_AXI_HP2_1_awsize(S_AXI_HP2_AWSIZE),
    .S_AXI_HP2_1_awvalid(S_AXI_HP2_AWVALID),
    .S_AXI_HP2_1_bid(S_AXI_HP2_BID),
    .S_AXI_HP2_1_bready(S_AXI_HP2_BREADY),
    .S_AXI_HP2_1_bresp(S_AXI_HP2_BRESP),
    .S_AXI_HP2_1_bvalid(S_AXI_HP2_BVALID),
    .S_AXI_HP2_1_rdata(S_AXI_HP2_RDATA),
    .S_AXI_HP2_1_rid(S_AXI_HP2_RID),
    .S_AXI_HP2_1_rlast(S_AXI_HP2_RLAST),
    .S_AXI_HP2_1_rready(S_AXI_HP2_RREADY),
    .S_AXI_HP2_1_rresp(S_AXI_HP2_RRESP),
    .S_AXI_HP2_1_rvalid(S_AXI_HP2_RVALID),
    .S_AXI_HP2_1_wdata(S_AXI_HP2_WDATA),
    .S_AXI_HP2_1_wid(S_AXI_HP2_WID),
    .S_AXI_HP2_1_wlast(S_AXI_HP2_WLAST),
    .S_AXI_HP2_1_wready(S_AXI_HP2_WREADY),
    .S_AXI_HP2_1_wstrb(S_AXI_HP2_WSTRB),
    .S_AXI_HP2_1_wvalid(S_AXI_HP2_WVALID),
    .S_AXI_HP3_0_araddr(S3_AXI_HP_HC_ARADDR),
    .S_AXI_HP3_0_arburst(S3_AXI_HP_HC_ARBURST),
    .S_AXI_HP3_0_arcache(S3_AXI_HP_HC_ARCACHE),
    .S_AXI_HP3_0_arid(S3_AXI_HP_HC_ARID),
    .S_AXI_HP3_0_arlen(S3_AXI_HP_HC_ARLEN),
    .S_AXI_HP3_0_arlock(S3_AXI_HP_HC_ARLOCK),
    .S_AXI_HP3_0_arprot(S3_AXI_HP_HC_ARPROT),
    .S_AXI_HP3_0_arqos(S3_AXI_HP_HC_ARQOS),
    .S_AXI_HP3_0_arready(S3_AXI_HP_HC_ARREADY),
    .S_AXI_HP3_0_arsize(S3_AXI_HP_HC_ARSIZE),
    .S_AXI_HP3_0_arvalid(S3_AXI_HP_HC_ARVALID),
    .S_AXI_HP3_0_awaddr(S3_AXI_HP_HC_AWADDR),
    .S_AXI_HP3_0_awburst(S3_AXI_HP_HC_AWBURST),
    .S_AXI_HP3_0_awcache(S3_AXI_HP_HC_AWCACHE),
    .S_AXI_HP3_0_awid(S3_AXI_HP_HC_AWID),
    .S_AXI_HP3_0_awlen(S3_AXI_HP_HC_AWLEN),
    .S_AXI_HP3_0_awlock(S3_AXI_HP_HC_AWLOCK),
    .S_AXI_HP3_0_awprot(S3_AXI_HP_HC_AWPROT),
    .S_AXI_HP3_0_awqos(S3_AXI_HP_HC_AWQOS),
    .S_AXI_HP3_0_awready(S3_AXI_HP_HC_AWREADY),
    .S_AXI_HP3_0_awsize(S3_AXI_HP_HC_AWSIZE),
    .S_AXI_HP3_0_awvalid(S3_AXI_HP_HC_AWVALID),
    .S_AXI_HP3_0_bid(S3_AXI_HP_HC_BID),
    .S_AXI_HP3_0_bready(S3_AXI_HP_HC_BREADY),
    .S_AXI_HP3_0_bresp(S3_AXI_HP_HC_BRESP),
    .S_AXI_HP3_0_bvalid(S3_AXI_HP_HC_BVALID),
    .S_AXI_HP3_0_rdata(S3_AXI_HP_HC_RDATA),
    .S_AXI_HP3_0_rid(S3_AXI_HP_HC_RID),
    .S_AXI_HP3_0_rlast(S3_AXI_HP_HC_RLAST),
    .S_AXI_HP3_0_rready(S3_AXI_HP_HC_RREADY),
    .S_AXI_HP3_0_rresp(S3_AXI_HP_HC_RRESP),
    .S_AXI_HP3_0_rvalid(S3_AXI_HP_HC_RVALID),
    .S_AXI_HP3_0_wdata(S3_AXI_HP_HC_WDATA),
    .S_AXI_HP3_0_wid(S3_AXI_HP_HC_WID),
    .S_AXI_HP3_0_wlast(S3_AXI_HP_HC_WLAST),
    .S_AXI_HP3_0_wready(S3_AXI_HP_HC_WREADY),
    .S_AXI_HP3_0_wstrb(S3_AXI_HP_HC_WSTRB),
    .S_AXI_HP3_0_wvalid(S3_AXI_HP_HC_WVALID),
    .USBIND_0_0_port_indctl(),
    .USBIND_0_0_vbus_pwrfault(),
    .USBIND_0_0_vbus_pwrselect(),
    .User_GP0_araddr(User_GP0_ARADDR),
    .User_GP0_arburst(User_GP0_ARBURST),
    .User_GP0_arcache(User_GP0_ARCACHE),
    .User_GP0_arid(User_GP0_ARID),
    .User_GP0_arlen(User_GP0_ARLEN),
    .User_GP0_arlock(User_GP0_ARLOCK),
    .User_GP0_arprot(User_GP0_ARPROT),
    .User_GP0_arqos(User_GP0_ARQOS),
    .User_GP0_arready(User_GP0_ARREADY),
    .User_GP0_arsize(User_GP0_ARSIZE),
    .User_GP0_arvalid(User_GP0_ARVALID),
    .User_GP0_awaddr(User_GP0_AWADDR),
    .User_GP0_awburst(User_GP0_AWBURST),
    .User_GP0_awcache(User_GP0_AWCACHE),
    .User_GP0_awid(User_GP0_AWID),
    .User_GP0_awlen(User_GP0_AWLEN),
    .User_GP0_awlock(User_GP0_AWLOCK),
    .User_GP0_awprot(User_GP0_AWPROT),
    .User_GP0_awqos(User_GP0_AWQOS),
    .User_GP0_awready(User_GP0_AWREADY),
    .User_GP0_awsize(User_GP0_AWSIZE),
    .User_GP0_awvalid(User_GP0_AWVALID),
    .User_GP0_bid(User_GP0_BID),
    .User_GP0_bready(User_GP0_BREADY),
    .User_GP0_bresp(User_GP0_BRESP),
    .User_GP0_bvalid(User_GP0_BVALID),
    .User_GP0_rdata(User_GP0_RDATA),
    .User_GP0_rid(User_GP0_RID),
    .User_GP0_rlast(User_GP0_RLAST),
    .User_GP0_rready(User_GP0_RREADY),
    .User_GP0_rresp(User_GP0_RRESP),
    .User_GP0_rvalid(User_GP0_RVALID),
    .User_GP0_wdata(User_GP0_WDATA),
    .User_GP0_wid(User_GP0_WID),
    .User_GP0_wlast(User_GP0_WLAST),
    .User_GP0_wready(User_GP0_WREADY),
    .User_GP0_wstrb(User_GP0_WSTRB),
    .User_GP0_wvalid(User_GP0_WVALID),
    .User_GP1_araddr(User_GP1_ARADDR),
    .User_GP1_arburst(User_GP1_ARBURST),
    .User_GP1_arcache(User_GP1_ARCACHE),
    .User_GP1_arid(User_GP1_ARID),
    .User_GP1_arlen(User_GP1_ARLEN),
    .User_GP1_arlock(User_GP1_ARLOCK),
    .User_GP1_arprot(User_GP1_ARPROT),
    .User_GP1_arqos(User_GP1_ARQOS),
    .User_GP1_arready(User_GP1_ARREADY),
    .User_GP1_arsize(User_GP1_ARSIZE),
    .User_GP1_arvalid(User_GP1_ARVALID),
    .User_GP1_awaddr(User_GP1_AWADDR),
    .User_GP1_awburst(User_GP1_AWBURST),
    .User_GP1_awcache(User_GP1_AWCACHE),
    .User_GP1_awid(User_GP1_AWID),
    .User_GP1_awlen(User_GP1_AWLEN),
    .User_GP1_awlock(User_GP1_AWLOCK),
    .User_GP1_awprot(User_GP1_AWPROT),
    .User_GP1_awqos(User_GP1_AWQOS),
    .User_GP1_awready(User_GP1_AWREADY),
    .User_GP1_awsize(User_GP1_AWSIZE),
    .User_GP1_awvalid(User_GP1_AWVALID),
    .User_GP1_bid(User_GP1_BID),
    .User_GP1_bready(User_GP1_BREADY),
    .User_GP1_bresp(User_GP1_BRESP),
    .User_GP1_bvalid(User_GP1_BVALID),
    .User_GP1_rdata(User_GP1_RDATA),
    .User_GP1_rid(User_GP1_RID),
    .User_GP1_rlast(User_GP1_RLAST),
    .User_GP1_rready(User_GP1_RREADY),
    .User_GP1_rresp(User_GP1_RRESP),
    .User_GP1_rvalid(User_GP1_RVALID),
    .User_GP1_wdata(User_GP1_WDATA),
    .User_GP1_wid(User_GP1_WID),
    .User_GP1_wlast(User_GP1_WLAST),
    .User_GP1_wready(User_GP1_WREADY),
    .User_GP1_wstrb(User_GP1_WSTRB),
    .User_GP1_wvalid(User_GP1_WVALID),
    .ai_irq(ai_irq),
    .customop_irq(customop_irq),
    .gp_axi_aclk(ps_clk_out),
    .hp_axi_aclk(hp_clk),
    .pl_bist_clk_0(pl_bist_clk),
    .pl_bist_rstn_0(pl_bist_rstn),
    .pl_clk_div_out_0(pl_clk_div_out),
    .pl_clk_en_b_0(pl_clk_en_b),
    .pl_itf_clk_0(pl_itf_clk),
    .pl_ra_clk_0(pl_ra_clk),
    .pl_rst_n_0(pl_rst_n),
    .pl_scan_clk_0(pl_scan_clk),
    .pl_scan_rst_n_0(pl_scan_rst_n),
    .reset_n(sys_rst_n & FCLK_RESET0_N),
    .soft_rst_n(~soft_rst)
);

AI_Mate ZGolo(
  .hp_clk                   (ddr_clk                  ),
  .ui_clk                   (ddr_clk                  ),
  .reg_clk                  (gp_clk                   ),
  .sys_rst_n                (sys_rst_n & (~soft_rst)  & FCLK_RESET0_N ),
  .img_ready_0              (               ),
  .img_data_0               (64'b0),
  .img_valid_0              (1'b0),
  .img_start_0              (1'b0),
 
  .app_addr                 (app_addr                 ),
  .app_cmd                  (app_cmd                  ),
  .app_en                   (app_en                   ),
  .app_wdf_data             (app_wdf_data             ),
  .app_wdf_end              (app_wdf_end              ),
  .app_wdf_mask             (app_wdf_mask             ),
  .app_wdf_wren             (app_wdf_wren             ),
  .app_rd_data              (app_rd_data              ),
  .app_rd_data_end          (app_rd_data_end          ),
  .app_rd_data_valid        (app_rd_data_valid        ),
  .app_rdy                  (app_rdy                  ),
  .app_wdf_rdy              (app_wdf_rdy              ),
  .ddr3_init_done           (ddr3_init_done           ),
  
  .M_AXI_GP0_ARVALID        (BYolo_GP0_ARVALID        ),
  .M_AXI_GP0_AWVALID        (BYolo_GP0_AWVALID        ),
  .M_AXI_GP0_BREADY         (BYolo_GP0_BREADY         ),
  .M_AXI_GP0_RREADY         (BYolo_GP0_RREADY         ),
  .M_AXI_GP0_WLAST          (BYolo_GP0_WLAST          ),
  .M_AXI_GP0_WVALID         (BYolo_GP0_WVALID         ),
  .M_AXI_GP0_ARID           (BYolo_GP0_ARID           ),
  .M_AXI_GP0_AWID           (BYolo_GP0_AWID           ),
  .M_AXI_GP0_WID            (BYolo_GP0_WID            ),
  .M_AXI_GP0_ARBURST        (BYolo_GP0_ARBURST        ),
  .M_AXI_GP0_ARLOCK         (BYolo_GP0_ARLOCK         ),
  .M_AXI_GP0_ARSIZE         (BYolo_GP0_ARSIZE         ),
  .M_AXI_GP0_AWBURST        (BYolo_GP0_AWBURST        ),
  .M_AXI_GP0_AWLOCK         (BYolo_GP0_AWLOCK         ),
  .M_AXI_GP0_AWSIZE         (BYolo_GP0_AWSIZE         ),
  .M_AXI_GP0_ARPROT         (BYolo_GP0_ARPROT         ),
  .M_AXI_GP0_AWPROT         (BYolo_GP0_AWPROT         ),
  .M_AXI_GP0_ARADDR         (BYolo_GP0_ARADDR         ),
  .M_AXI_GP0_AWADDR         (BYolo_GP0_AWADDR         ),
  .M_AXI_GP0_WDATA          (BYolo_GP0_WDATA          ),
  .M_AXI_GP0_ARCACHE        (BYolo_GP0_ARCACHE        ),
  .M_AXI_GP0_ARLEN          (BYolo_GP0_ARLEN          ),
  .M_AXI_GP0_ARQOS          (BYolo_GP0_ARQOS          ),
  .M_AXI_GP0_AWCACHE        (BYolo_GP0_AWCACHE        ),
  .M_AXI_GP0_AWLEN          (BYolo_GP0_AWLEN          ),
  .M_AXI_GP0_AWQOS          (BYolo_GP0_AWQOS          ),
  .M_AXI_GP0_WSTRB          (BYolo_GP0_WSTRB          ),
  .M_AXI_GP0_ARREADY        (BYolo_GP0_ARREADY        ),
  .M_AXI_GP0_AWREADY        (BYolo_GP0_AWREADY        ),
  .M_AXI_GP0_BVALID         (BYolo_GP0_BVALID         ),
  .M_AXI_GP0_RLAST          (BYolo_GP0_RLAST          ),
  .M_AXI_GP0_RVALID         (BYolo_GP0_RVALID         ),
  .M_AXI_GP0_WREADY         (BYolo_GP0_WREADY         ),
  .M_AXI_GP0_BID            (BYolo_GP0_BID            ),
  .M_AXI_GP0_RID            (BYolo_GP0_RID            ),
  .M_AXI_GP0_BRESP          (BYolo_GP0_BRESP          ),
  .M_AXI_GP0_RRESP          (BYolo_GP0_RRESP          ),
  .M_AXI_GP0_RDATA          (BYolo_GP0_RDATA          ),
  
  .M_AXI_GP1_ARVALID        (BYolo_GP1_ARVALID        ),
  .M_AXI_GP1_AWVALID        (BYolo_GP1_AWVALID        ),
  .M_AXI_GP1_BREADY         (BYolo_GP1_BREADY         ),
  .M_AXI_GP1_RREADY         (BYolo_GP1_RREADY         ),
  .M_AXI_GP1_WLAST          (BYolo_GP1_WLAST          ),
  .M_AXI_GP1_WVALID         (BYolo_GP1_WVALID         ),
  .M_AXI_GP1_ARID           (BYolo_GP1_ARID           ),
  .M_AXI_GP1_AWID           (BYolo_GP1_AWID           ),
  .M_AXI_GP1_WID            (BYolo_GP1_WID            ),
  .M_AXI_GP1_ARBURST        (BYolo_GP1_ARBURST        ),
  .M_AXI_GP1_ARLOCK         (BYolo_GP1_ARLOCK         ),
  .M_AXI_GP1_ARSIZE         (BYolo_GP1_ARSIZE         ),
  .M_AXI_GP1_AWBURST        (BYolo_GP1_AWBURST        ),
  .M_AXI_GP1_AWLOCK         (BYolo_GP1_AWLOCK         ),
  .M_AXI_GP1_AWSIZE         (BYolo_GP1_AWSIZE         ),
  .M_AXI_GP1_ARPROT         (BYolo_GP1_ARPROT         ),
  .M_AXI_GP1_AWPROT         (BYolo_GP1_AWPROT         ),
  .M_AXI_GP1_ARADDR         (BYolo_GP1_ARADDR         ),
  .M_AXI_GP1_AWADDR         (BYolo_GP1_AWADDR         ),
  .M_AXI_GP1_WDATA          (BYolo_GP1_WDATA          ),
  .M_AXI_GP1_ARCACHE        (BYolo_GP1_ARCACHE        ),
  .M_AXI_GP1_ARLEN          (BYolo_GP1_ARLEN          ),
  .M_AXI_GP1_ARQOS          (BYolo_GP1_ARQOS          ),
  .M_AXI_GP1_AWCACHE        (BYolo_GP1_AWCACHE        ),
  .M_AXI_GP1_AWLEN          (BYolo_GP1_AWLEN          ),
  .M_AXI_GP1_AWQOS          (BYolo_GP1_AWQOS          ),
  .M_AXI_GP1_WSTRB          (BYolo_GP1_WSTRB          ),
  .M_AXI_GP1_ARREADY        (BYolo_GP1_ARREADY        ),
  .M_AXI_GP1_AWREADY        (BYolo_GP1_AWREADY        ),
  .M_AXI_GP1_BVALID         (BYolo_GP1_BVALID         ),
  .M_AXI_GP1_RLAST          (BYolo_GP1_RLAST          ),
  .M_AXI_GP1_RVALID         (BYolo_GP1_RVALID         ),
  .M_AXI_GP1_WREADY         (BYolo_GP1_WREADY         ),
  .M_AXI_GP1_BID            (BYolo_GP1_BID            ),
  .M_AXI_GP1_RID            (BYolo_GP1_RID            ),
  .M_AXI_GP1_BRESP          (BYolo_GP1_BRESP          ),
  .M_AXI_GP1_RRESP          (BYolo_GP1_RRESP          ),
  .M_AXI_GP1_RDATA          (BYolo_GP1_RDATA          ),

  .S0_AXI_HP_HC_ARREADY     (S0_AXI_HP_HC_ARREADY     ),
  .S0_AXI_HP_HC_AWREADY     (S0_AXI_HP_HC_AWREADY     ),
  .S0_AXI_HP_HC_BVALID      (S0_AXI_HP_HC_BVALID      ),
  .S0_AXI_HP_HC_RLAST       (S0_AXI_HP_HC_RLAST       ),
  .S0_AXI_HP_HC_RVALID      (S0_AXI_HP_HC_RVALID      ),
  .S0_AXI_HP_HC_WREADY      (S0_AXI_HP_HC_WREADY      ),
  .S0_AXI_HP_HC_BRESP       (S0_AXI_HP_HC_BRESP       ),
  .S0_AXI_HP_HC_RRESP       (S0_AXI_HP_HC_RRESP       ),
  .S0_AXI_HP_HC_BID         (S0_AXI_HP_HC_BID         ),
  .S0_AXI_HP_HC_RID         (S0_AXI_HP_HC_RID         ),
  .S0_AXI_HP_HC_RDATA       (S0_AXI_HP_HC_RDATA       ),
  .S0_AXI_HP_HC_ARVALID     (S0_AXI_HP_HC_ARVALID     ),
  .S0_AXI_HP_HC_AWVALID     (S0_AXI_HP_HC_AWVALID     ),
  .S0_AXI_HP_HC_BREADY      (S0_AXI_HP_HC_BREADY      ),
  .S0_AXI_HP_HC_RREADY      (S0_AXI_HP_HC_RREADY      ),
  .S0_AXI_HP_HC_WLAST       (S0_AXI_HP_HC_WLAST       ),
  .S0_AXI_HP_HC_WVALID      (S0_AXI_HP_HC_WVALID      ),
  .S0_AXI_HP_HC_ARBURST     (S0_AXI_HP_HC_ARBURST     ),
  .S0_AXI_HP_HC_ARLOCK      (S0_AXI_HP_HC_ARLOCK      ),
  .S0_AXI_HP_HC_ARSIZE      (S0_AXI_HP_HC_ARSIZE      ),
  .S0_AXI_HP_HC_AWBURST     (S0_AXI_HP_HC_AWBURST     ),
  .S0_AXI_HP_HC_AWLOCK      (S0_AXI_HP_HC_AWLOCK      ),
  .S0_AXI_HP_HC_AWSIZE      (S0_AXI_HP_HC_AWSIZE      ),
  .S0_AXI_HP_HC_ARPROT      (S0_AXI_HP_HC_ARPROT      ),
  .S0_AXI_HP_HC_AWPROT      (S0_AXI_HP_HC_AWPROT      ),
  .S0_AXI_HP_HC_ARADDR      (S0_AXI_HP_HC_ARADDR      ),
  .S0_AXI_HP_HC_AWADDR      (S0_AXI_HP_HC_AWADDR      ),
  .S0_AXI_HP_HC_ARCACHE     (S0_AXI_HP_HC_ARCACHE     ),
  .S0_AXI_HP_HC_ARLEN       (S0_AXI_HP_HC_ARLEN       ),
  .S0_AXI_HP_HC_ARQOS       (S0_AXI_HP_HC_ARQOS       ),
  .S0_AXI_HP_HC_AWCACHE     (S0_AXI_HP_HC_AWCACHE     ),
  .S0_AXI_HP_HC_AWLEN       (S0_AXI_HP_HC_AWLEN       ),
  .S0_AXI_HP_HC_AWQOS       (S0_AXI_HP_HC_AWQOS       ),
  .S0_AXI_HP_HC_ARID        (S0_AXI_HP_HC_ARID        ),
  .S0_AXI_HP_HC_AWID        (S0_AXI_HP_HC_AWID        ),
  .S0_AXI_HP_HC_WID         (S0_AXI_HP_HC_WID         ),
  .S0_AXI_HP_HC_WDATA       (S0_AXI_HP_HC_WDATA       ),
  .S0_AXI_HP_HC_WSTRB       (S0_AXI_HP_HC_WSTRB       ), 

  .S1_AXI_HP_HC_ARREADY     (S1_AXI_HP_HC_ARREADY     ),
  .S1_AXI_HP_HC_AWREADY     (S1_AXI_HP_HC_AWREADY     ),
  .S1_AXI_HP_HC_BVALID      (S1_AXI_HP_HC_BVALID      ),
  .S1_AXI_HP_HC_RLAST       (S1_AXI_HP_HC_RLAST       ),
  .S1_AXI_HP_HC_RVALID      (S1_AXI_HP_HC_RVALID      ),
  .S1_AXI_HP_HC_WREADY      (S1_AXI_HP_HC_WREADY      ),
  .S1_AXI_HP_HC_BRESP       (S1_AXI_HP_HC_BRESP       ),
  .S1_AXI_HP_HC_RRESP       (S1_AXI_HP_HC_RRESP       ),
  .S1_AXI_HP_HC_BID         (S1_AXI_HP_HC_BID         ),
  .S1_AXI_HP_HC_RID         (S1_AXI_HP_HC_RID         ),
  .S1_AXI_HP_HC_RDATA       (S1_AXI_HP_HC_RDATA       ),
  .S1_AXI_HP_HC_ARVALID     (S1_AXI_HP_HC_ARVALID     ),
  .S1_AXI_HP_HC_AWVALID     (S1_AXI_HP_HC_AWVALID     ),
  .S1_AXI_HP_HC_BREADY      (S1_AXI_HP_HC_BREADY      ),
  .S1_AXI_HP_HC_RREADY      (S1_AXI_HP_HC_RREADY      ),
  .S1_AXI_HP_HC_WLAST       (S1_AXI_HP_HC_WLAST       ),
  .S1_AXI_HP_HC_WVALID      (S1_AXI_HP_HC_WVALID      ),
  .S1_AXI_HP_HC_ARBURST     (S1_AXI_HP_HC_ARBURST     ),
  .S1_AXI_HP_HC_ARLOCK      (S1_AXI_HP_HC_ARLOCK      ),
  .S1_AXI_HP_HC_ARSIZE      (S1_AXI_HP_HC_ARSIZE      ),
  .S1_AXI_HP_HC_AWBURST     (S1_AXI_HP_HC_AWBURST     ),
  .S1_AXI_HP_HC_AWLOCK      (S1_AXI_HP_HC_AWLOCK      ),
  .S1_AXI_HP_HC_AWSIZE      (S1_AXI_HP_HC_AWSIZE      ),
  .S1_AXI_HP_HC_ARPROT      (S1_AXI_HP_HC_ARPROT      ),
  .S1_AXI_HP_HC_AWPROT      (S1_AXI_HP_HC_AWPROT      ),
  .S1_AXI_HP_HC_ARADDR      (S1_AXI_HP_HC_ARADDR      ),
  .S1_AXI_HP_HC_AWADDR      (S1_AXI_HP_HC_AWADDR      ),
  .S1_AXI_HP_HC_ARCACHE     (S1_AXI_HP_HC_ARCACHE     ),
  .S1_AXI_HP_HC_ARLEN       (S1_AXI_HP_HC_ARLEN       ),
  .S1_AXI_HP_HC_ARQOS       (S1_AXI_HP_HC_ARQOS       ),
  .S1_AXI_HP_HC_AWCACHE     (S1_AXI_HP_HC_AWCACHE     ),
  .S1_AXI_HP_HC_AWLEN       (S1_AXI_HP_HC_AWLEN       ),
  .S1_AXI_HP_HC_AWQOS       (S1_AXI_HP_HC_AWQOS       ),
  .S1_AXI_HP_HC_ARID        (S1_AXI_HP_HC_ARID        ),
  .S1_AXI_HP_HC_AWID        (S1_AXI_HP_HC_AWID        ),
  .S1_AXI_HP_HC_WID         (S1_AXI_HP_HC_WID         ),
  .S1_AXI_HP_HC_WDATA       (S1_AXI_HP_HC_WDATA       ),
  .S1_AXI_HP_HC_WSTRB       (S1_AXI_HP_HC_WSTRB       ), 

  .S2_AXI_HP_HC_ARREADY     (S2_AXI_HP_HC_ARREADY     ),
  .S2_AXI_HP_HC_AWREADY     (S2_AXI_HP_HC_AWREADY     ),
  .S2_AXI_HP_HC_BVALID      (S2_AXI_HP_HC_BVALID      ),
  .S2_AXI_HP_HC_RLAST       (S2_AXI_HP_HC_RLAST       ),
  .S2_AXI_HP_HC_RVALID      (S2_AXI_HP_HC_RVALID      ),
  .S2_AXI_HP_HC_WREADY      (S2_AXI_HP_HC_WREADY      ),
  .S2_AXI_HP_HC_BRESP       (S2_AXI_HP_HC_BRESP       ),
  .S2_AXI_HP_HC_RRESP       (S2_AXI_HP_HC_RRESP       ),
  .S2_AXI_HP_HC_BID         (S2_AXI_HP_HC_BID         ),
  .S2_AXI_HP_HC_RID         (S2_AXI_HP_HC_RID         ),
  .S2_AXI_HP_HC_RDATA       (S2_AXI_HP_HC_RDATA       ),
  .S2_AXI_HP_HC_ARVALID     (S2_AXI_HP_HC_ARVALID     ),
  .S2_AXI_HP_HC_AWVALID     (S2_AXI_HP_HC_AWVALID     ),
  .S2_AXI_HP_HC_BREADY      (S2_AXI_HP_HC_BREADY      ),
  .S2_AXI_HP_HC_RREADY      (S2_AXI_HP_HC_RREADY      ),
  .S2_AXI_HP_HC_WLAST       (S2_AXI_HP_HC_WLAST       ),
  .S2_AXI_HP_HC_WVALID      (S2_AXI_HP_HC_WVALID      ),
  .S2_AXI_HP_HC_ARBURST     (S2_AXI_HP_HC_ARBURST     ),
  .S2_AXI_HP_HC_ARLOCK      (S2_AXI_HP_HC_ARLOCK      ),
  .S2_AXI_HP_HC_ARSIZE      (S2_AXI_HP_HC_ARSIZE      ),
  .S2_AXI_HP_HC_AWBURST     (S2_AXI_HP_HC_AWBURST     ),
  .S2_AXI_HP_HC_AWLOCK      (S2_AXI_HP_HC_AWLOCK      ),
  .S2_AXI_HP_HC_AWSIZE      (S2_AXI_HP_HC_AWSIZE      ),
  .S2_AXI_HP_HC_ARPROT      (S2_AXI_HP_HC_ARPROT      ),
  .S2_AXI_HP_HC_AWPROT      (S2_AXI_HP_HC_AWPROT      ),
  .S2_AXI_HP_HC_ARADDR      (S2_AXI_HP_HC_ARADDR      ),
  .S2_AXI_HP_HC_AWADDR      (S2_AXI_HP_HC_AWADDR      ),
  .S2_AXI_HP_HC_ARCACHE     (S2_AXI_HP_HC_ARCACHE     ),
  .S2_AXI_HP_HC_ARLEN       (S2_AXI_HP_HC_ARLEN       ),
  .S2_AXI_HP_HC_ARQOS       (S2_AXI_HP_HC_ARQOS       ),
  .S2_AXI_HP_HC_AWCACHE     (S2_AXI_HP_HC_AWCACHE     ),
  .S2_AXI_HP_HC_AWLEN       (S2_AXI_HP_HC_AWLEN       ),
  .S2_AXI_HP_HC_AWQOS       (S2_AXI_HP_HC_AWQOS       ),
  .S2_AXI_HP_HC_ARID        (S2_AXI_HP_HC_ARID        ),
  .S2_AXI_HP_HC_AWID        (S2_AXI_HP_HC_AWID        ),
  .S2_AXI_HP_HC_WID         (S2_AXI_HP_HC_WID         ),
  .S2_AXI_HP_HC_WDATA       (S2_AXI_HP_HC_WDATA       ),
  .S2_AXI_HP_HC_WSTRB       (S2_AXI_HP_HC_WSTRB       ), 

  .S3_AXI_HP_HC_ARREADY     (S3_AXI_HP_HC_ARREADY     ),
  .S3_AXI_HP_HC_AWREADY     (S3_AXI_HP_HC_AWREADY     ),
  .S3_AXI_HP_HC_BVALID      (S3_AXI_HP_HC_BVALID      ),
  .S3_AXI_HP_HC_RLAST       (S3_AXI_HP_HC_RLAST       ),
  .S3_AXI_HP_HC_RVALID      (S3_AXI_HP_HC_RVALID      ),
  .S3_AXI_HP_HC_WREADY      (S3_AXI_HP_HC_WREADY      ),
  .S3_AXI_HP_HC_BRESP       (S3_AXI_HP_HC_BRESP       ),
  .S3_AXI_HP_HC_RRESP       (S3_AXI_HP_HC_RRESP       ),
  .S3_AXI_HP_HC_BID         (S3_AXI_HP_HC_BID         ),
  .S3_AXI_HP_HC_RID         (S3_AXI_HP_HC_RID         ),
  .S3_AXI_HP_HC_RDATA       (S3_AXI_HP_HC_RDATA       ),
  .S3_AXI_HP_HC_ARVALID     (S3_AXI_HP_HC_ARVALID     ),
  .S3_AXI_HP_HC_AWVALID     (S3_AXI_HP_HC_AWVALID     ),
  .S3_AXI_HP_HC_BREADY      (S3_AXI_HP_HC_BREADY      ),
  .S3_AXI_HP_HC_RREADY      (S3_AXI_HP_HC_RREADY      ),
  .S3_AXI_HP_HC_WLAST       (S3_AXI_HP_HC_WLAST       ),
  .S3_AXI_HP_HC_WVALID      (S3_AXI_HP_HC_WVALID      ),
  .S3_AXI_HP_HC_ARBURST     (S3_AXI_HP_HC_ARBURST     ),
  .S3_AXI_HP_HC_ARLOCK      (S3_AXI_HP_HC_ARLOCK      ),
  .S3_AXI_HP_HC_ARSIZE      (S3_AXI_HP_HC_ARSIZE      ),
  .S3_AXI_HP_HC_AWBURST     (S3_AXI_HP_HC_AWBURST     ),
  .S3_AXI_HP_HC_AWLOCK      (S3_AXI_HP_HC_AWLOCK      ),
  .S3_AXI_HP_HC_AWSIZE      (S3_AXI_HP_HC_AWSIZE      ),
  .S3_AXI_HP_HC_ARPROT      (S3_AXI_HP_HC_ARPROT      ),
  .S3_AXI_HP_HC_AWPROT      (S3_AXI_HP_HC_AWPROT      ),
  .S3_AXI_HP_HC_ARADDR      (S3_AXI_HP_HC_ARADDR      ),
  .S3_AXI_HP_HC_AWADDR      (S3_AXI_HP_HC_AWADDR      ),
  .S3_AXI_HP_HC_ARCACHE     (S3_AXI_HP_HC_ARCACHE     ),
  .S3_AXI_HP_HC_ARLEN       (S3_AXI_HP_HC_ARLEN       ),
  .S3_AXI_HP_HC_ARQOS       (S3_AXI_HP_HC_ARQOS       ),
  .S3_AXI_HP_HC_AWCACHE     (S3_AXI_HP_HC_AWCACHE     ),
  .S3_AXI_HP_HC_AWLEN       (S3_AXI_HP_HC_AWLEN       ),
  .S3_AXI_HP_HC_AWQOS       (S3_AXI_HP_HC_AWQOS       ),
  .S3_AXI_HP_HC_ARID        (S3_AXI_HP_HC_ARID        ),
  .S3_AXI_HP_HC_AWID        (S3_AXI_HP_HC_AWID        ),
  .S3_AXI_HP_HC_WID         (S3_AXI_HP_HC_WID         ),
  .S3_AXI_HP_HC_WDATA       (S3_AXI_HP_HC_WDATA       ),
  .S3_AXI_HP_HC_WSTRB       (S3_AXI_HP_HC_WSTRB       ), 

  .pl_awaddr                (pl_awaddr                ),
  .pl_awdata                (pl_awdata                ),
  .pl_awen                  (pl_awen                  ),
  .pl_awinfo                (pl_awinfo                ),
  .pl_awlast                (pl_awlast                ),
  .pl_awvalid               (pl_awvalid               ),
  .pl_awready               (pl_awready               ),
  .pl_araddr                (pl_araddr                ),
  .pl_arinfo                (pl_arinfo                ),
  .pl_arlast                (pl_arlast                ),
  .pl_arvalid               (pl_arvalid               ),
  .pl_arready               (pl_arready               ),
  .pl_rdata                 (pl_rdata                 ),
  .pl_rvalid                (pl_rvalid                ),
  .pl_rlast                 (pl_rlast                 ),
  .pl_rready                (pl_rready                ),
  .pl_bvalid                (pl_bvalid                ),  //30TAI
  .pl_bready                (pl_bready                ),  //30TAI  
  .pl_ra_awaddr             (pl_ra_awaddr             ),
  .pl_ra_awdata             (pl_ra_awdata             ),
  .pl_ra_awvalid            (pl_ra_awvalid            ),
  .pl_ra_awready            (pl_ra_awready            ),
  .pl_ra_araddr             (pl_ra_araddr             ),
  .pl_ra_arvalid            (pl_ra_arvalid            ),
  .pl_ra_arready            (pl_ra_arready            ),
  .pl_ra_rdata              (pl_ra_rdata              ),
  .pl_ra_rvalid             (pl_ra_rvalid             ),
  .pl_ra_rready             (pl_ra_rready             ),
  .pl_int_info              (pl_int_info              ),  //30TAI  
  .pl_int_valid             (pl_int_valid             ),  //30TAI
  .pl_int_ready             (pl_int_ready             ),  //30TAI  
  .pl_ra_clk                (pl_ra_clk                ),
  .pl_itf_clk               (pl_itf_clk               ),
  .pl_rst_n                 (pl_rst_n                 ),
  .pl_clk_en_b              (pl_clk_en_b              ),
  .pl_bist_clk              (pl_bist_clk              ),
  .pl_bist_rstn             (pl_bist_rstn             ),
  .pl_bist_en               (pl_bist_en               ),
  .pl_bist_err              (pl_bist_err              ),
  .pl_bist_done             (pl_bist_done             ),
  .pl_repair_done           (pl_repair_done           ),
  .pl_repair_fail           (pl_repair_fail           ),
  .pl_bist_err_inv          (pl_bist_err_inv          ),
  .pl_clk_div_out           (pl_clk_div_out           ),
  .pl_scan_mode_b           (pl_scan_mode_b           ),
  .pl_scan_en               (pl_scan_en               ),
  .pl_scan_clk              (pl_scan_clk              ),
  .pl_scan_rst_n            (pl_scan_rst_n            ),
  .pl_scan_i                (pl_scan_i                ),
  .pl_scan_o                (pl_scan_o                ),

  //UserCustomOp_0 BUS
  .UserCustomOp_0_awwaddr   ( User_Ddr_awwaddr  ),
  .UserCustomOp_0_awwdata   ( User_Ddr_awwdata  ),
  .UserCustomOp_0_awwinfo   ( User_Ddr_awwinfo  ), //{1'b0,pl_awen[63:0],pl_awinfo[5:0],pl_awlast[0]}
  .UserCustomOp_0_awwvalid  ( User_Ddr_awwvalid ),
  .UserCustomOp_0_awwready  ( User_Ddr_awwready ),

  .UserCustomOp_0_araddr    ( User_Ddr_araddr   ),
  .UserCustomOp_0_arvalid   ( User_Ddr_arvalid  ),
  .UserCustomOp_0_arinfo    ( User_Ddr_arinfo   ),  //{25'h0,pl_arinfo,pl_arlast}
  .UserCustomOp_0_arready   ( User_Ddr_arready  ),
  .UserCustomOp_0_rdata     ( User_Ddr_rdata    ),
  .UserCustomOp_0_rvalid    ( User_Ddr_rvalid   ),
  .UserCustomOp_0_rinfo     ( User_Ddr_rinfo    ),  //{25'h0,pl_rinfo,pl_rlast}
  .UserCustomOp_0_rready    ( User_Ddr_rready   ),

  //irq
  .customop_irq             (customop_irq             ),
  .ai_irq                   (ai_irq                  )     
);


mig_7series_0 mig_ddr3_u0 (
  .ddr3_dq             (ddr3_dq            ),
  .ddr3_dqs_n          (ddr3_dqs_n         ),
  .ddr3_dqs_p          (ddr3_dqs_p         ),
  .ddr3_addr           (ddr3_addr          ),
  .ddr3_ba             (ddr3_ba            ),
  .ddr3_ras_n          (ddr3_ras_n         ),
  .ddr3_cas_n          (ddr3_cas_n         ),
  .ddr3_we_n           (ddr3_we_n          ),
  .ddr3_reset_n        (ddr3_reset_n       ),
  .ddr3_ck_p           (ddr3_ck_p          ),
  .ddr3_ck_n           (ddr3_ck_n          ),
  .ddr3_cke            (ddr3_cke           ),
  .ddr3_cs_n           (ddr3_cs_n          ),
  .ddr3_dm             (ddr3_dm            ),
  .ddr3_odt            (ddr3_odt           ),

  .init_calib_complete (ddr3_init_done     ),

  .app_addr            (app_addr           ),
  .app_cmd             (app_cmd            ),
  .app_en              (app_en             ),
  .app_wdf_data        (app_wdf_data       ),
  .app_wdf_end         (app_wdf_end        ),
  .app_wdf_wren        (app_wdf_wren       ),
  .app_rd_data         (app_rd_data        ),
  .app_rd_data_end     (app_rd_data_end    ),
  .app_rd_data_valid   (app_rd_data_valid  ),
  .app_rdy             (app_rdy            ),
  .app_wdf_rdy         (app_wdf_rdy        ),
  .app_wdf_mask        (app_wdf_mask       ),

  .app_sr_req          (1'b0               ),
  .app_ref_req         (1'b0               ),
  .app_zq_req          (1'b0               ),
  .app_sr_active       (                   ),
  .app_ref_ack         (                   ),
  .app_zq_ack          (                   ),

  .ui_clk              (ddr_clk            ),
  .ui_clk_sync_rst     (ddr_ui_rst         ),

  .sys_clk_p           (sys_clk_p          ),
  .sys_clk_n           (sys_clk_n          ),
  .device_temp_i       ('d0                ),  // input [11:0]			device_temp_i
  .sys_rst             (sys_rst            )
);

endmodule