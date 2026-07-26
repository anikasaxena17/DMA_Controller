module scheduler
#(
    parameter CHANNELS = 4
)
(
    input  wire clk,
    input  wire rst,

    input  wire next_request,

    input  wire [CHANNELS-1:0] valid,

    output reg  [1:0] grant,
    output reg        grant_valid
);

reg [1:0] last_grant;

// Next values computed combinationally
reg [1:0] next_grant;
reg       next_grant_valid;
reg [2:0] candidate;

integer i;

/////////////////////////////////////////////////////
// Combinational Search Logic
/////////////////////////////////////////////////////

always @(*)
begin
    next_grant       = grant;
    next_grant_valid = 1'b0;

    for(i = 1; i <= CHANNELS; i = i + 1)
    begin
        candidate = last_grant + i;

        if(candidate >= CHANNELS)
            candidate = candidate - CHANNELS;

        // If a valid request is found and we haven't already assigned a grant
        if(valid[candidate] && !next_grant_valid)
        begin
            next_grant       = candidate[1:0];
            next_grant_valid = 1'b1;
        end
    end
end

/////////////////////////////////////////////////////
// Sequential Registers
/////////////////////////////////////////////////////

always @(posedge clk)
begin
    if(rst)
    begin
        last_grant  <= 2'd3;
        grant       <= 2'd0;
        grant_valid <= 1'b0;
    end
    else if(next_request)
    begin
        grant       <= next_grant;
        grant_valid <= next_grant_valid;

        if(next_grant_valid)
            last_grant <= next_grant;
    end
    else begin
        // FIX: Clear the valid signal when DMA is busy so it doesn't double-trigger
        grant_valid <= 1'b0; 
    end
end

endmodule