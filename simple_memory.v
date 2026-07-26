module simple_memory
#(
    //------------------------------------------------------
    // Project Parameters (Moved from dma_pkg)
    //------------------------------------------------------
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 1024
)
(
    input  wire clk,
    input  wire rst,

    //-------------------------
    // DMA Interface
    //-------------------------
    input  wire mem_read,
    input  wire mem_write,

    input  wire [ADDR_WIDTH-1:0] mem_addr,
    input  wire [DATA_WIDTH-1:0] mem_write_data,

    output reg  [DATA_WIDTH-1:0] mem_read_data,
    output reg                   mem_ready
);

// Memory Array
reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];

//-------------------------------------------
// Pipeline Registers
//-------------------------------------------
reg pending_read;
reg pending_write;

reg [ADDR_WIDTH-1:0] pending_addr;
reg [DATA_WIDTH-1:0] pending_write_data;

//-------------------------------------------
// Memory Logic
//-------------------------------------------
always @(posedge clk)
begin
    if(rst)
    begin
        pending_read  <= 1'b0;
        pending_write <= 1'b0;
        mem_ready     <= 1'b0;
        mem_read_data <= {DATA_WIDTH{1'b0}};
    end
    else
    begin
        //---------------------------------
        // Default
        //---------------------------------
        mem_ready <= 1'b0;

        //---------------------------------
        // Complete Pending Read
        //---------------------------------
        if(pending_read)
        begin
            mem_read_data <= memory[pending_addr];
            mem_ready     <= 1'b1;
            pending_read  <= 1'b0;
        end

        //---------------------------------
        // Complete Pending Write
        //---------------------------------
        if(pending_write)
        begin
            memory[pending_addr] <= pending_write_data;
            mem_ready            <= 1'b1;
            pending_write        <= 1'b0;
        end

        //---------------------------------
        // Capture New Read Request
        //---------------------------------
        if(mem_read && !pending_read && !pending_write)
        begin
            pending_read <= 1'b1;
            pending_addr <= mem_addr;
        end

        //---------------------------------
        // Capture New Write Request
        //---------------------------------
        if(mem_write && !pending_read && !pending_write)
        begin
            pending_write      <= 1'b1;
            pending_addr       <= mem_addr;
            pending_write_data <= mem_write_data;
        end
    end
end

endmodule