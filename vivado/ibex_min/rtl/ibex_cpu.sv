// Ibex RV32I, FPGA register file, no caches/M extension/PMP/lockstep.
module ibex_cpu (
 input wire clk, resetn, irq_external,
 output wire instr_req, input wire instr_gnt, instr_rvalid,
 output wire [31:0] instr_addr, input wire [31:0] instr_rdata,
 input wire instr_err,
 output wire data_req, data_we, output wire [3:0] data_be,
 output wire [31:0] data_addr, data_wdata,
 input wire data_gnt, data_rvalid, input wire [31:0] data_rdata,
 input wire data_err, output wire fault, sleeping
);
 import ibex_pkg::*;
 wire [4:0] ra, rb, wa;
 wire we, dummy_id, dummy_wb;
 wire [31:0] wd, rd_a, rd_b;
 wire alert0, alert1, alert2, double_fault;
 ibex_mubi_t busy;
 assign sleeping=(busy==IbexMuBiOff);
 wire [IC_TAG_SIZE-1:0] tag_zero [IC_NUM_WAYS];
 wire [IC_LINE_SIZE-1:0] line_zero [IC_NUM_WAYS];
 for (genvar i=0; i<IC_NUM_WAYS; i++) begin
   assign tag_zero[i]='0;
   assign line_zero[i]='0;
 end
 assign fault=alert0|alert1|alert2|double_fault;
 ibex_register_file_fpga rf (
   .clk_i(clk), .rst_ni(resetn), .test_en_i(1'b0),
   .dummy_instr_id_i(dummy_id), .dummy_instr_wb_i(dummy_wb),
   .raddr_a_i(ra), .raddr_b_i(rb), .waddr_a_i(wa),
   .wdata_a_i(wd), .we_a_i(we), .rdata_a_o(rd_a), .rdata_b_o(rd_b), .err_o()
 );
 ibex_core #(.RV32M(RV32MNone), .RV32B(RV32BNone),
   .PMPEnable(1'b0), .MHPMCounterNum(0), .ICache(1'b0),
   .BranchTargetALU(1'b0), .WritebackStage(1'b0), .SecureIbex(1'b0)) cpu (
   .clk_i(clk), .rst_ni(resetn), .hart_id_i(32'd0), .boot_addr_i(32'd0),
   .instr_req_o(instr_req), .instr_gnt_i(instr_gnt), .instr_rvalid_i(instr_rvalid),
   .instr_addr_o(instr_addr), .instr_rdata_i(instr_rdata), .instr_err_i(instr_err),
   .data_req_o(data_req), .data_we_o(data_we), .data_be_o(data_be),
   .data_addr_o(data_addr), .data_wdata_o(data_wdata), .data_gnt_i(data_gnt),
   .data_rvalid_i(data_rvalid), .data_rdata_i(data_rdata), .data_err_i(data_err),
   .dummy_instr_id_o(dummy_id), .dummy_instr_wb_o(dummy_wb),
   .rf_raddr_a_o(ra), .rf_raddr_b_o(rb), .rf_waddr_wb_o(wa), .rf_we_wb_o(we),
   .rf_wdata_wb_ecc_o(wd), .rf_rdata_a_ecc_i(rd_a), .rf_rdata_b_ecc_i(rd_b),
   .ic_tag_req_o(), .ic_tag_write_o(), .ic_tag_addr_o(), .ic_tag_wdata_o(),
   .ic_tag_rdata_i(tag_zero), .ic_data_req_o(), .ic_data_write_o(),
   .ic_data_addr_o(), .ic_data_wdata_o(), .ic_data_rdata_i(line_zero),
   .ic_scr_key_valid_i(1'b0), .ic_scr_key_req_o(),
   .irq_software_i(1'b0), .irq_timer_i(1'b0), .irq_external_i(irq_external),
   .irq_fast_i(15'd0), .irq_nm_i(1'b0), .irq_pending_o(), .debug_req_i(1'b0),
   .crash_dump_o(), .double_fault_seen_o(double_fault),
   .fetch_enable_i(IbexMuBiOn), .alert_minor_o(alert0),
   .alert_major_internal_o(alert1), .alert_major_bus_o(alert2), .core_busy_o(busy)
 );
endmodule
