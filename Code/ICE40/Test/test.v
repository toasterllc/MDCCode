// iverilog -o test.vvp -g2012 test.v ; ./test.vvp

module main();
    reg clk = 0;
    reg rst = 0;
    wire rst_ = !rst;
    
    initial forever begin
        clk = !clk;
        #21;
    end
    
    reg rstReg=0, rstRegTmp=0;
    always @(posedge clk, negedge rst_) begin
        if (!rst_) rstReg <= 1;
        else begin
            {rstReg, rstRegTmp} <= {rstRegTmp, 1'b0};
        end
    end
    
    reg[1:0] state = 0;
    always @(posedge clk, negedge rst_) begin
        case (state)
        0: begin
            state <= 1;
        end
        
        1: begin
            rst <= 1;
            state <= 2;
        end
        
        2: begin
            $display("rstReg A: %b", rstReg);
            state <= 3;
        end
        
        3: begin
            $display("rstReg B: %b", rstReg);
            $finish;
        end
        endcase
    end
endmodule
