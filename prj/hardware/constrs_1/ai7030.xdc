set_property SEVERITY {Warning} [get_drc_checks {REQP-44}]
set_property SEVERITY {Warning} [get_drc_checks {REQP-46}]
set_property SEVERITY {Warning} [get_drc_checks {REQP-52}]
set_property SEVERITY {Warning} [get_drc_checks {REQP-56}]

set_property LOC PLLE2_ADV_X1Y3 [get_cells U0_ps_ai_peripheral/ZGolo/u_AI_Mate_top/clkrst_wrapper_u0/AI_CORE_CLK/inst/plle2_adv_inst]

set_false_path -from [get_ports sys_rst]
set_false_path -to [get_ports {led[0]}]
set_false_path -to [get_ports {led[1]}]
set_false_path -from [get_clocks clk_out1_clk_wiz_0] -to [get_clocks clk_out2_clk_wiz_0]
set_false_path -from [get_clocks clk_out2_clk_wiz_0] -to [get_clocks clk_out1_clk_wiz_0]
set_false_path -from [get_clocks clk_out1_clk_wiz_0] -to [get_clocks clk_pll_i]
set_false_path -from [get_clocks clk_pll_i] -to [get_clocks clk_out1_clk_wiz_0]



## gp_clk and cam_clk

# 27MHz and RXOUTCLK

# from ddr_clk to cam_clk

#from cam_clk to gp_clk

# unknown
