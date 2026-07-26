module dma_controller
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
    // Scheduler Interface
    //--------------------------------------------------
    input  wire                       grant_valid,
    input  wire [CHANNEL_WIDTH-1:0]   grant_channel,
    output wire                       dma_idle,

    //--------------------------------------------------
    // Descriptor Table Interface
    //--------------------------------------------------
    input  wire [ADDR_WIDTH-1:0]      src_addr,
    input  wire [ADDR_WIDTH-1:0]      dst_addr,
    input  wire [LENGTH_WIDTH-1:0]    length,

    //--------------------------------------------------
    // Memory Interface
    //--------------------------------------------------
    output reg                        mem_read,
    output reg                        mem_write,
    output reg  [ADDR_WIDTH-1:0]      mem_addr,
    output reg  [DATA_WIDTH-1:0]      mem_write_data,
    input  wire [DATA_WIDTH-1:0]      mem_read_data,
    input  wire                       mem_ready,

    //--------------------------------------------------
    // Descriptor Table Interface
    //--------------------------------------------------
    output reg                        descriptor_done,
    output reg  [CHANNEL_WIDTH-1:0]   done_channel,

    //--------------------------------------------------
    // CPU Interface
    //--------------------------------------------------
    output reg                        interrupt,
    output reg  [CHANNEL_WIDTH-1:0]   interrupt_channel
);

/////////////////////////////////////////////////////////
// State Definition (Enum Replaced with localparam)
/////////////////////////////////////////////////////////

localparam [2:0]
    IDLE            = 3'd0,
    LOAD_DESCRIPTOR = 3'd1,
    READ_REQUEST    = 3'd2,
    WAIT_READ       = 3'd3,
    WRITE_REQUEST   = 3'd4,
    WAIT_WRITE      = 3'd5,
    UPDATE          = 3'd6,
    DONE            = 3'd7;

/////////////////////////////////////////////////////////
// State Registers
/////////////////////////////////////////////////////////

reg [2:0] state;
reg [2:0] next_state;

/////////////////////////////////////////////////////////
// Datapath Registers
/////////////////////////////////////////////////////////

reg [ADDR_WIDTH-1:0]    src_reg;
reg [ADDR_WIDTH-1:0]    next_src_reg;

reg [ADDR_WIDTH-1:0]    dst_reg;
reg [ADDR_WIDTH-1:0]    next_dst_reg;

reg [LENGTH_WIDTH-1:0]  remaining_count;
reg [LENGTH_WIDTH-1:0]  next_remaining_count;

reg [DATA_WIDTH-1:0]    data_reg;
reg [DATA_WIDTH-1:0]    next_data_reg;

reg [CHANNEL_WIDTH-1:0] current_channel;
reg [CHANNEL_WIDTH-1:0] next_current_channel;

assign dma_idle = (state == IDLE);

/////////////////////////////////////////////////////////
// State Register
/////////////////////////////////////////////////////////

always @(posedge clk)
begin
    if(rst)
        state <= IDLE;
    else
        state <= next_state;
end

/////////////////////////////////////////////////////////
// Datapath Registers
/////////////////////////////////////////////////////////

always @(posedge clk)
begin
    if(rst)
    begin
        src_reg         <= {ADDR_WIDTH{1'b0}};
        dst_reg         <= {ADDR_WIDTH{1'b0}};
        remaining_count <= {LENGTH_WIDTH{1'b0}};
        data_reg        <= {DATA_WIDTH{1'b0}};
        current_channel <= {CHANNEL_WIDTH{1'b0}};
    end
    else
    begin
        src_reg         <= next_src_reg;
        dst_reg         <= next_dst_reg;
        remaining_count <= next_remaining_count;
        data_reg        <= next_data_reg;
        current_channel <= next_current_channel;
    end
end

/////////////////////////////////////////////////////////
// Next State Logic
/////////////////////////////////////////////////////////

always @(*)
begin
    //--------------------------------------------------
    // Default
    //--------------------------------------------------
    next_state = state;

    //--------------------------------------------------
    // State Machine
    //--------------------------------------------------
    case(state)

        IDLE:
        begin
            if(grant_valid)
                next_state = LOAD_DESCRIPTOR;
        end

        LOAD_DESCRIPTOR:
        begin
            next_state = READ_REQUEST;
        end

        READ_REQUEST:
        begin
            next_state = WAIT_READ;
        end

        WAIT_READ:
        begin
            if(mem_ready)
                next_state = WRITE_REQUEST;
        end

        WRITE_REQUEST:
        begin
            next_state = WAIT_WRITE;
        end

        WAIT_WRITE:
        begin
            if(mem_ready)
                next_state = UPDATE;
        end

        UPDATE:
        begin
            if(remaining_count == 16'd1)
                next_state = DONE;
            else
                next_state = READ_REQUEST;
        end

        DONE:
        begin
            next_state = IDLE;
        end

        default:
        begin
            next_state = IDLE;
        end

    endcase
end

/////////////////////////////////////////////////////////
// Datapath Next Logic
/////////////////////////////////////////////////////////

always @(*)
begin
    //--------------------------------------------------
    // Default : Hold previous values
    //--------------------------------------------------
    next_src_reg         = src_reg;
    next_dst_reg         = dst_reg;
    next_remaining_count = remaining_count;
    next_data_reg        = data_reg;
    next_current_channel = current_channel;

    //--------------------------------------------------
    // State Based Datapath Updates
    //--------------------------------------------------
    case(state)

    LOAD_DESCRIPTOR:
    begin
        next_src_reg         = src_addr;
        next_dst_reg         = dst_addr;
        next_remaining_count = length;
        next_current_channel = grant_channel;
    end

    WAIT_READ:
    begin
        if(mem_ready)
        begin
            next_data_reg = mem_read_data;
        end
    end

    UPDATE:
    begin
        next_src_reg         = src_reg + 1;
        next_dst_reg         = dst_reg + 1;
        next_remaining_count = remaining_count - 1;
    end

    default:
    begin
        // Hold values
    end

    endcase
end

/////////////////////////////////////////////////////////
// Output Logic
/////////////////////////////////////////////////////////

always @(*)
begin
    //--------------------------------------------------
    // Default Outputs
    //--------------------------------------------------
    mem_read          = 1'b0;
    mem_write         = 1'b0;
    mem_addr          = {ADDR_WIDTH{1'b0}};
    mem_write_data    = data_reg;
    descriptor_done   = 1'b0;
    done_channel      = current_channel;
    interrupt         = 1'b0;
    interrupt_channel = current_channel;

    //--------------------------------------------------
    // State Outputs
    //--------------------------------------------------
    case(state)

    READ_REQUEST:
    begin
        mem_read = 1'b1;
        mem_addr = src_reg;
    end

    WRITE_REQUEST:
    begin
        mem_write = 1'b1;
        mem_addr  = dst_reg;
        // mem_write_data takes the default assignment (data_reg)
    end

    DONE:
    begin
        descriptor_done = 1'b1;
        interrupt       = 1'b1;
    end

    default:
    begin
        // Keep default outputs
    end

    endcase
end

endmodule