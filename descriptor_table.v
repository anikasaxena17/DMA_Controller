module descriptor_table
#(
    //------------------------------------------------------
    // Project Parameters (Moved from dma_pkg)
    //------------------------------------------------------
    parameter CHANNELS      = 4,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter LENGTH_WIDTH  = 16,
    parameter CHANNEL_WIDTH = $clog2(CHANNELS)
)
(
    input  wire clk,
    input  wire rst,

    //--------------------------------------------------
    // CPU Interface
    //--------------------------------------------------
    input  wire cpu_wr_en,
    input  wire [CHANNEL_WIDTH-1:0] cpu_channel,
    input  wire [ADDR_WIDTH-1:0]    cpu_src_addr,
    input  wire [ADDR_WIDTH-1:0]    cpu_dst_addr,
    input  wire [LENGTH_WIDTH-1:0]  cpu_length,

    //--------------------------------------------------
    // DMA Interface
    //--------------------------------------------------
    input  wire dma_clear_valid,
    input  wire [CHANNEL_WIDTH-1:0] dma_channel,

    //--------------------------------------------------
    // Scheduler Interface
    //--------------------------------------------------
    output reg  [CHANNELS-1:0]      valid_vector,

    //--------------------------------------------------
    // FSM Read Interface
    //--------------------------------------------------
    input  wire [CHANNEL_WIDTH-1:0] rd_channel,
    output reg  [ADDR_WIDTH-1:0]    src_addr,
    output reg  [ADDR_WIDTH-1:0]    dst_addr,
    output reg  [LENGTH_WIDTH-1:0]  length
);

    //------------------------------------------------------
    // Flattened Struct Array Replacements
    //------------------------------------------------------
    reg [ADDR_WIDTH-1:0]   table_src_addr [0:CHANNELS-1];
    reg [ADDR_WIDTH-1:0]   table_dst_addr [0:CHANNELS-1];
    reg [LENGTH_WIDTH-1:0] table_length   [0:CHANNELS-1];
    reg                    table_valid    [0:CHANNELS-1];

    integer i;

    ///////////////////////////////////////////////////////
    // Sequential Write Logic
    ///////////////////////////////////////////////////////
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < CHANNELS; i = i + 1) begin
                table_src_addr[i] <= {ADDR_WIDTH{1'b0}};
                table_dst_addr[i] <= {ADDR_WIDTH{1'b0}};
                table_length[i]   <= {LENGTH_WIDTH{1'b0}};
                table_valid[i]    <= 1'b0;
            end
        end 
        else begin
            //--------------------------------------------
            // CPU writes descriptor
            //--------------------------------------------
            if (cpu_wr_en) begin
                // Reject zero-length descriptors
                if (cpu_length != 0) begin
                    table_src_addr[cpu_channel] <= cpu_src_addr;
                    table_dst_addr[cpu_channel] <= cpu_dst_addr;
                    table_length[cpu_channel]   <= cpu_length;
                    table_valid[cpu_channel]    <= 1'b1;
                end
            end

            //--------------------------------------------
            // DMA clears valid bit
            //--------------------------------------------
            if (dma_clear_valid) begin
                table_valid[dma_channel] <= 1'b0;
            end
        end
    end

    ///////////////////////////////////////////////////////
    // Descriptor Read
    ///////////////////////////////////////////////////////
    always @(*) begin
        src_addr = table_src_addr[rd_channel];
        dst_addr = table_dst_addr[rd_channel];
        length   = table_length[rd_channel];
    end

    ///////////////////////////////////////////////////////
    // Valid Vector Generation
    ///////////////////////////////////////////////////////
    always @(*) begin
        for (i = 0; i < CHANNELS; i = i + 1) begin
            valid_vector[i] = table_valid[i];
        end
    end

endmodule