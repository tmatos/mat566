
module de2i150_core (
	aes_core_0_clk_1_export,
	aes_core_0_debug_data_1_export,
	aes_core_0_rst_n_1_export,
	aes_core_0_switch_entrada_1_export,
	pcie_hard_ip_0_pcie_rstn_export,
	pcie_hard_ip_0_powerdown_pll_powerdown,
	pcie_hard_ip_0_powerdown_gxb_powerdown,
	pcie_hard_ip_0_refclk_export,
	pcie_hard_ip_0_rx_in_rx_datain_0,
	pcie_hard_ip_0_tx_out_tx_dataout_0);	

	input		aes_core_0_clk_1_export;
	output	[31:0]	aes_core_0_debug_data_1_export;
	input		aes_core_0_rst_n_1_export;
	input	[17:0]	aes_core_0_switch_entrada_1_export;
	input		pcie_hard_ip_0_pcie_rstn_export;
	input		pcie_hard_ip_0_powerdown_pll_powerdown;
	input		pcie_hard_ip_0_powerdown_gxb_powerdown;
	input		pcie_hard_ip_0_refclk_export;
	input		pcie_hard_ip_0_rx_in_rx_datain_0;
	output		pcie_hard_ip_0_tx_out_tx_dataout_0;
endmodule
