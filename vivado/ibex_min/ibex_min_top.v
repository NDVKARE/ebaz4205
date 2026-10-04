module ibex_min_top (
    inout wire [14:0] DDR_addr,
    inout wire [2:0] DDR_ba,
    inout wire  DDR_cas_n,
    inout wire  DDR_ck_n,
    inout wire  DDR_ck_p,
    inout wire  DDR_cke,
    inout wire  DDR_cs_n,
    inout wire [3:0] DDR_dm,
    inout wire [31:0] DDR_dq,
    inout wire [3:0] DDR_dqs_n,
    inout wire [3:0] DDR_dqs_p,
    inout wire  DDR_odt,
    inout wire  DDR_ras_n,
    inout wire  DDR_reset_n,
    inout wire  DDR_we_n,
    inout wire  FIXED_IO_ddr_vrn,
    inout wire  FIXED_IO_ddr_vrp,
    inout wire [53:0] FIXED_IO_mio,
    inout wire  FIXED_IO_ps_clk,
    inout wire  FIXED_IO_ps_porb,
    inout wire  FIXED_IO_ps_srstb,
    output wire led6_green_n,
    output wire led6_red_n,
    output wire [3:0] data_gpio
);
    wire [31:0] M_AXI_araddr;
    wire [2:0] M_AXI_arprot;
    wire  M_AXI_arready;
    wire  M_AXI_arvalid;
    wire [31:0] M_AXI_awaddr;
    wire [2:0] M_AXI_awprot;
    wire  M_AXI_awready;
    wire  M_AXI_awvalid;
    wire  M_AXI_bready;
    wire [1:0] M_AXI_bresp;
    wire  M_AXI_bvalid;
    wire [31:0] M_AXI_rdata;
    wire  M_AXI_rready;
    wire [1:0] M_AXI_rresp;
    wire  M_AXI_rvalid;
    wire [31:0] M_AXI_wdata;
    wire  M_AXI_wready;
    wire [3:0] M_AXI_wstrb;
    wire  M_AXI_wvalid;
    wire  clk25;
    wire [0:0] resetn;
    ibex_ps_wrapper ps (
        .DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .M_AXI_araddr(M_AXI_araddr),
        .M_AXI_arprot(M_AXI_arprot),
        .M_AXI_arready(M_AXI_arready),
        .M_AXI_arvalid(M_AXI_arvalid),
        .M_AXI_awaddr(M_AXI_awaddr),
        .M_AXI_awprot(M_AXI_awprot),
        .M_AXI_awready(M_AXI_awready),
        .M_AXI_awvalid(M_AXI_awvalid),
        .M_AXI_bready(M_AXI_bready),
        .M_AXI_bresp(M_AXI_bresp),
        .M_AXI_bvalid(M_AXI_bvalid),
        .M_AXI_rdata(M_AXI_rdata),
        .M_AXI_rready(M_AXI_rready),
        .M_AXI_rresp(M_AXI_rresp),
        .M_AXI_rvalid(M_AXI_rvalid),
        .M_AXI_wdata(M_AXI_wdata),
        .M_AXI_wready(M_AXI_wready),
        .M_AXI_wstrb(M_AXI_wstrb),
        .M_AXI_wvalid(M_AXI_wvalid),
        .clk25(clk25),
        .resetn(resetn)
    );
    ibex_soc soc (
        .clk(clk25), .resetn(resetn), .led6_green_n(led6_green_n), .led6_red_n(led6_red_n), .data_gpio(data_gpio), .cpu_fault(),
        .s_axi_awaddr(M_AXI_awaddr),
        .s_axi_awvalid(M_AXI_awvalid),
        .s_axi_awready(M_AXI_awready),
        .s_axi_wdata(M_AXI_wdata),
        .s_axi_wstrb(M_AXI_wstrb),
        .s_axi_wvalid(M_AXI_wvalid),
        .s_axi_wready(M_AXI_wready),
        .s_axi_bresp(M_AXI_bresp),
        .s_axi_bvalid(M_AXI_bvalid),
        .s_axi_bready(M_AXI_bready),
        .s_axi_araddr(M_AXI_araddr),
        .s_axi_arvalid(M_AXI_arvalid),
        .s_axi_arready(M_AXI_arready),
        .s_axi_rdata(M_AXI_rdata),
        .s_axi_rresp(M_AXI_rresp),
        .s_axi_rvalid(M_AXI_rvalid),
        .s_axi_rready(M_AXI_rready)
    );
endmodule

