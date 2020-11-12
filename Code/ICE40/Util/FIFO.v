`ifndef FIFO_v
`define FIFO_v

module FIFO(
    input logic clk,
    
    input logic din,
    input logic[Width-1:0] d,
    
    input logic qout,
    output logic[Width-1:0] q,
    output logic qValid
);
    parameter Width = 12;
    parameter Slots = 3;
    
    logic[(Width*Slots)-1:0] slots;
    logic[Slots-1:0] qSlot;
    initial begin
        slots = 0;
        qSlot = 0;
    end
    
    logic empty;
    assign empty = qSlot==0;
    
    logic full;
    assign full = qSlot[Slots-1];
    
    always @(posedge clk) begin
        // Data in + data out
        if (din & qout) begin
            slots <= (slots<<Width) | d;
            qSlot <= (empty ? 1 : qSlot);
        
        // Data in
        end else if (din) begin
            slots <= (slots<<Width) | d;
            qSlot <= (empty ? 1 : (full ? qSlot : qSlot<<1));
        
        // Data out
        end else if (qout) begin
            qSlot <= qSlot>>1;
        end
    end
    
    integer i;
    always @* begin
        q = 0;
        for (i=0; i<Slots; i=i+1) begin
            if (qSlot[i]) begin
                q = q|slots[(Width*(i+1))-1 -: Width];
            end
        end
    end
    
    assign qValid = !empty;
endmodule

`endif
