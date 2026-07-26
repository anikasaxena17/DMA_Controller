module dma_top
#(
    //------------------------------------------------------
    // Project Parameters (Replaces dma_pkg)
    //------------------------------------------------------
    parameter CHANNELS      = 4,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter LENGTH_WIDTH  = 16,
    parameter CHANNEL_WIDTH = 2 // $clog2(CHANNELS)
)
(
    input  wire clk,
    input  wire rst,

    //--------------------------------------------------
    // CPU Interface
    //--------------------------------------------------
    input  wire                       cpu_wr_en,
    input  wire [CHANNEL_WIDTH-1:0]   cpu_channel,
    input  wire [ADDR_WIDTH-1:0]      cpu_src_addr,
    input  wire [ADDR_WIDTH-1:0]      cpu_dst_addr,
    input  wire [LENGTH_WIDTH-1:0]    cpu_length,

    //--------------------------------------------------
    // Interrupt
    //--------------------------------------------------
    output wire                       interrupt,
    output wire [CHANNEL_WIDTH-1:0]   interrupt_channel
);

/////////////////////////////////////////////////////////
// Internal Signals
/////////////////////////////////////////////////////////

wire [CHANNELS-1:0]      valid_vector;

wire [CHANNEL_WIDTH-1:0] grant_channel;
wire                     grant_valid;
wire                     dma_idle;

wire [CHANNEL_WIDTH-1:0] rd_channel;

wire [ADDR_WIDTH-1:0]    src_addr;
wire [ADDR_WIDTH-1:0]    dst_addr;

wire [LENGTH_WIDTH-1:0]  length;

wire                     descriptor_done;
wire [CHANNEL_WIDTH-1:0] done_channel;

wire                     mem_read;
wire                     mem_write;

wire [ADDR_WIDTH-1:0]    mem_addr;
wire [DATA_WIDTH-1:0]    mem_write_data;
wire [DATA_WIDTH-1:0]    mem_read_data;
wire                     mem_ready;

assign rd_channel = grant_channel;

/////////////////////////////////////////////////////////
// Module Instantiations
/////////////////////////////////////////////////////////

descriptor_table #(
    .CHANNELS(CHANNELS),
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .LENGTH_WIDTH(LENGTH_WIDTH),
    .CHANNEL_WIDTH(CHANNEL_WIDTH)
) descriptor_table_inst (
    .clk(clk),
    .rst(rst),
    .cpu_wr_en(cpu_wr_en),
    .cpu_channel(cpu_channel),
    .cpu_src_addr(cpu_src_addr),
    .cpu_dst_addr(cpu_dst_addr),
    .cpu_length(cpu_length),
    .dma_clear_valid(descriptor_done),
    .dma_channel(done_channel),
    .valid_vector(valid_vector),
    .rd_channel(rd_channel),
    .src_addr(src_addr),
    .dst_addr(dst_addr),
    .length(length)
);

scheduler #(
    .CHANNELS(CHANNELS)
) scheduler_inst (
    .clk(clk),
    .rst(rst),
    .next_request(dma_idle),
    .valid(valid_vector),
    .grant(grant_channel),
    .grant_valid(grant_valid)
);

dma_controller #(
    .CHANNELS(CHANNELS),
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .LENGTH_WIDTH(LENGTH_WIDTH),
    .CHANNEL_WIDTH(CHANNEL_WIDTH)
) controller_inst (
    .clk(clk),
    .rst(rst),
    .grant_valid(grant_valid),
    .grant_channel(grant_channel),
    .dma_idle(dma_idle), // Fixed missing comma here
    .src_addr(src_addr),
    .dst_addr(dst_addr),
    .length(length),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .mem_read_data(mem_read_data),
    .mem_ready(mem_ready),
    .descriptor_done(descriptor_done),
    .done_channel(done_channel),
    .interrupt(interrupt),
    .interrupt_channel(interrupt_channel)
);

simple_memory #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(1024)
) memory_inst (
    .clk(clk),
    .rst(rst),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .mem_addr(mem_addr),
    .mem_write_data(mem_write_data),
    .mem_read_data(mem_read_data),
    .mem_ready(mem_ready)
);

endmodule