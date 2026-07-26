`timescale 1ns/1ps

module dma_top_tb;

    localparam int CHANNELS      = 4;
    localparam int ADDR_WIDTH    = 32;
    localparam int DATA_WIDTH    = 32;
    localparam int LENGTH_WIDTH  = 16;
    localparam int CHANNEL_WIDTH = 2;
    localparam int MEM_DEPTH     = 1024;

    localparam time CLK_PERIOD = 10ns;

    logic                      clk;
    logic                      rst;

    logic                      cpu_wr_en;
    logic [CHANNEL_WIDTH-1:0]  cpu_channel;
    logic [ADDR_WIDTH-1:0]     cpu_src_addr;
    logic [ADDR_WIDTH-1:0]     cpu_dst_addr;
    logic [LENGTH_WIDTH-1:0]   cpu_length;

    logic                      interrupt;
    logic [CHANNEL_WIDTH-1:0]  interrupt_channel;

    int errors            = 0;
    int checks_run        = 0;
    int tests_run         = 0;
    int tests_passed      = 0;

    dma_top #(
        .CHANNELS      (CHANNELS),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .LENGTH_WIDTH  (LENGTH_WIDTH),
        .CHANNEL_WIDTH (CHANNEL_WIDTH)
    ) dut (
        .clk                (clk),
        .rst                (rst),
        .cpu_wr_en          (cpu_wr_en),
        .cpu_channel        (cpu_channel),
        .cpu_src_addr       (cpu_src_addr),
        .cpu_dst_addr       (cpu_dst_addr),
        .cpu_length         (cpu_length),
        .interrupt          (interrupt),
        .interrupt_channel  (interrupt_channel)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        $dumpfile("dma_top_tb.vcd");
        $dumpvars(0, dma_top_tb);
    end

    int irq_queue[$];

    always @(posedge clk) begin
        if (!rst && interrupt) begin
            irq_queue.push_back(int'(interrupt_channel));
        end
    end

    task automatic reset_dut();
        rst          = 1'b1;
        cpu_wr_en    = 1'b0;
        cpu_channel  = '0;
        cpu_src_addr = '0;
        cpu_dst_addr = '0;
        cpu_length   = '0;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
    endtask

    task automatic mem_seed_region(input int base_addr, input int len, input logic [DATA_WIDTH-1:0] seed);
        int i;
        for (i = 0; i < len; i++) begin
            dut.memory_inst.memory[base_addr + i] = seed + i;
        end
    endtask

    task automatic mem_poison_region(input int base_addr, input int len);
        int i;
        for (i = 0; i < len; i++) begin
            dut.memory_inst.memory[base_addr + i] = 32'hDEAD_BEEF;
        end
    endtask

    task automatic write_descriptor(
        input [CHANNEL_WIDTH-1:0] channel,
        input [ADDR_WIDTH-1:0]    src,
        input [ADDR_WIDTH-1:0]    dst,
        input [LENGTH_WIDTH-1:0]  len
    );
        @(posedge clk);
        cpu_wr_en    <= 1'b1;
        cpu_channel  <= channel;
        cpu_src_addr <= src;
        cpu_dst_addr <= dst;
        cpu_length   <= len;
        @(posedge clk);
        cpu_wr_en    <= 1'b0;
    endtask

    task automatic wait_for_interrupt(
        output int channel_seen,
        output bit timeout,
        input  int max_cycles = 3000
    );
        int cycles;
        bit done;
        timeout      = 1'b0;
        channel_seen = -1;
        cycles       = 0;
        done         = 1'b0;
        while (!done) begin
            if (irq_queue.size() > 0) begin
                channel_seen = irq_queue.pop_front();
                done = 1'b1;
            end
            else begin
                @(posedge clk);
                cycles++;
                if (cycles > max_cycles) begin
                    timeout = 1'b1;
                    done = 1'b1;
                end
            end
        end
    endtask

    task automatic check_region(
        input int    src_base,
        input int    dst_base,
        input int    len,
        input string name
    );
        int i;
        bit region_pass;
        region_pass = 1'b1;
        for (i = 0; i < len; i++) begin
            checks_run++;
            if (dut.memory_inst.memory[dst_base+i] !== dut.memory_inst.memory[src_base+i]) begin
                $error("[%0t] [%s] Mismatch word %0d: dst[0x%0h]=0x%08h expected(src)=0x%08h",
                        $time, name, i, dst_base+i,
                        dut.memory_inst.memory[dst_base+i],
                        dut.memory_inst.memory[src_base+i]);
                region_pass = 1'b0;
                errors++;
            end
        end
        if (region_pass)
            $display("[%0t]   -> data check PASS: %0d word(s) matched (src=0x%0h dst=0x%0h)",
                       $time, len, src_base, dst_base);
        else
            $display("[%0t]   -> data check FAIL: %s", $time, name);
    endtask

    task automatic test_start(input string name);
        tests_run++;
        $display("\n============================================================");
        $display("[%0t] TEST %0d: %s", $time, tests_run, name);
        $display("============================================================");
    endtask

    task automatic test_end(input string name, input int errors_before);
        if (errors == errors_before) begin
            tests_passed++;
            $display("[%0t] TEST %0d (%s): PASS", $time, tests_run, name);
        end else begin
            $display("[%0t] TEST %0d (%s): FAIL (%0d error(s))",
                       $time, tests_run, name, errors - errors_before);
        end
    endtask

    int    err_snapshot;
    int    irq_channel;
    bit    irq_timeout;
    int    seen_mask;

    initial begin
        errors = 0;

        test_start("Reset behavior");
        err_snapshot = errors;
        reset_dut();
        checks_run++;
        if (dut.dma_idle !== 1'b1) begin
            $error("[%0t] Expected dma_idle=1 after reset, got %0b", $time, dut.dma_idle);
            errors++;
        end
        checks_run++;
        if (interrupt !== 1'b0) begin
            $error("[%0t] Expected interrupt=0 after reset, got %0b", $time, interrupt);
            errors++;
        end
        test_end("Reset behavior", err_snapshot);

        test_start("Single channel, single-word transfer");
        err_snapshot = errors;
        begin
            int src_base = 0;
            int dst_base = 100;
            mem_seed_region(src_base, 1, 32'hA5A5_0001);
            mem_poison_region(dst_base, 1);

            write_descriptor(2'd0, src_base, dst_base, 16'd1);

            wait_for_interrupt(irq_channel, irq_timeout);
            if (irq_timeout) begin
                $error("[%0t] Timed out waiting for interrupt", $time);
                errors++;
            end else begin
                $display("[%0t] Interrupt observed on channel %0d", $time, irq_channel);
                if (irq_channel != 0) begin
                    $error("[%0t] Expected interrupt on channel 0, got %0d", $time, irq_channel);
                    errors++;
                end
                check_region(src_base, dst_base, 1, "single-word transfer");
            end
        end
        test_end("Single channel, single-word transfer", err_snapshot);

        test_start("Single channel, multi-word burst transfer");
        err_snapshot = errors;
        begin
            int src_base = 10;
            int dst_base = 200;
            int len      = 16;
            mem_seed_region(src_base, len, 32'h1000_0000);
            mem_poison_region(dst_base, len);

            write_descriptor(2'd1, src_base, dst_base, len[LENGTH_WIDTH-1:0]);

            wait_for_interrupt(irq_channel, irq_timeout);
            if (irq_timeout) begin
                $error("[%0t] Timed out waiting for interrupt", $time);
                errors++;
            end else begin
                $display("[%0t] Interrupt observed on channel %0d", $time, irq_channel);
                if (irq_channel != 1) begin
                    $error("[%0t] Expected interrupt on channel 1, got %0d", $time, irq_channel);
                    errors++;
                end
                check_region(src_base, dst_base, len, "burst transfer");
            end
        end
        test_end("Single channel, multi-word burst transfer", err_snapshot);

        test_start("Zero-length descriptor rejected");
        err_snapshot = errors;
        begin
            int src_base = 50;
            int dst_base = 250;
            mem_seed_region(src_base, 1, 32'hDEAD_0002);
            mem_poison_region(dst_base, 1);

            write_descriptor(2'd2, src_base, dst_base, 16'd0);

            repeat (50) @(posedge clk);

            checks_run++;
            if (dut.dma_idle !== 1'b1) begin
                $error("[%0t] Expected dma_idle to remain 1 for zero-length descriptor", $time);
                errors++;
            end
            checks_run++;
            if (irq_queue.size() != 0) begin
                $error("[%0t] Unexpected interrupt observed for zero-length descriptor", $time);
                errors++;
            end
            checks_run++;
            if (dut.memory_inst.memory[dst_base] !== 32'hDEAD_BEEF) begin
                $error("[%0t] Destination memory was modified despite zero-length descriptor", $time);
                errors++;
            end else begin
                $display("[%0t]   -> zero-length descriptor correctly ignored", $time);
            end
        end
        test_end("Zero-length descriptor rejected", err_snapshot);

        test_start("Simultaneous multi-channel arbitration");
        err_snapshot = errors;
        begin
            static int src_base[CHANNELS];
            static int dst_base[CHANNELS];
            static int len     [CHANNELS];
            int ch;

            src_base[0] = 0;   dst_base[0] = 100; len[0] = 4;
            src_base[1] = 400; dst_base[1] = 500; len[1] = 8;
            src_base[2] = 600; dst_base[2] = 700; len[2] = 2;
            src_base[3] = 800; dst_base[3] = 900; len[3] = 6;

            for (ch = 0; ch < CHANNELS; ch++) begin
                mem_seed_region(src_base[ch], len[ch], 32'h2000_0000 + (ch << 16));
                mem_poison_region(dst_base[ch], len[ch]);
            end

            for (ch = 0; ch < CHANNELS; ch++) begin
                write_descriptor(ch[CHANNEL_WIDTH-1:0], src_base[ch], dst_base[ch], len[ch][LENGTH_WIDTH-1:0]);
            end

            seen_mask = 0;
            for (ch = 0; ch < CHANNELS; ch++) begin
                wait_for_interrupt(irq_channel, irq_timeout);
                if (irq_timeout) begin
                    $error("[%0t] Timed out waiting for interrupt #%0d", $time, ch);
                    errors++;
                end else begin
                    $display("[%0t] Interrupt observed on channel %0d", $time, irq_channel);
                    if (seen_mask[irq_channel]) begin
                        $error("[%0t] Channel %0d generated more than one interrupt", $time, irq_channel);
                        errors++;
                    end
                    seen_mask[irq_channel] = 1'b1;
                end
            end

            checks_run++;
            if (seen_mask !== ((1 << CHANNELS) - 1)) begin
                $error("[%0t] Not all channels were serviced, seen_mask=0b%0b", $time, seen_mask);
                errors++;
            end else begin
                $display("[%0t]   -> all %0d channels serviced exactly once", $time, CHANNELS);
            end

            for (ch = 0; ch < CHANNELS; ch++) begin
                check_region(src_base[ch], dst_base[ch], len[ch], $sformatf("channel %0d arbitration transfer", ch));
            end
        end
        test_end("Simultaneous multi-channel arbitration", err_snapshot);

        test_start("Back-to-back descriptors on same channel");
        err_snapshot = errors;
        begin
            int src_a = 300, dst_a = 350, len_a = 3;
            int src_b = 360, dst_b = 380, len_b = 5;

            mem_seed_region(src_a, len_a, 32'h3000_0000);
            mem_poison_region(dst_a, len_a);
            mem_seed_region(src_b, len_b, 32'h4000_0000);
            mem_poison_region(dst_b, len_b);

            write_descriptor(2'd3, src_a, dst_a, len_a[LENGTH_WIDTH-1:0]);
            wait_for_interrupt(irq_channel, irq_timeout);
            if (irq_timeout) begin
                $error("[%0t] Timed out waiting for first interrupt", $time);
                errors++;
            end else begin
                if (irq_channel != 3) begin
                    $error("[%0t] Expected interrupt on channel 3, got %0d", $time, irq_channel);
                    errors++;
                end
                check_region(src_a, dst_a, len_a, "back-to-back transfer A");
            end

            write_descriptor(2'd3, src_b, dst_b, len_b[LENGTH_WIDTH-1:0]);
            wait_for_interrupt(irq_channel, irq_timeout);
            if (irq_timeout) begin
                $error("[%0t] Timed out waiting for second interrupt", $time);
                errors++;
            end else begin
                if (irq_channel != 3) begin
                    $error("[%0t] Expected interrupt on channel 3, got %0d", $time, irq_channel);
                    errors++;
                end
                check_region(src_b, dst_b, len_b, "back-to-back transfer B");
            end
        end
        test_end("Back-to-back descriptors on same channel", err_snapshot);

        repeat (10) @(posedge clk);
        $display("\n============================================================");
        $display("SIMULATION SUMMARY");
        $display("============================================================");
        $display("Tests run     : %0d", tests_run);
        $display("Tests passed  : %0d", tests_passed);
        $display("Tests failed  : %0d", tests_run - tests_passed);
        $display("Data checks   : %0d", checks_run);
        $display("Total errors  : %0d", errors);
        if (errors == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: FAILURES DETECTED");
        $display("============================================================\n");

        $finish;
    end

    initial begin
        #500000;
        $display("[%0t] WATCHDOG TIMEOUT: simulation did not complete in time", $time);
        $finish;
    end

endmodule