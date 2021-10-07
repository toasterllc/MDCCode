`ifndef WordValidator_v
`define WordValidator_v

`include "Util.v"
`include "FletcherChecksum.v"

`timescale 1ns/1ps

module WordValidator();
    EndianSwap #(.Width(16)) HostFromLittle16();
    EndianSwap #(.Width(32)) HostFromLittle32();
    
    // Checksum of written data
    // This is to validate the Fletcher32 checksum appended to the image data
    reg         checksum_clk    = 0;
    reg         checksum_rst    = 0;
    reg         checksum_en     = 0;
    reg[15:0]   checksum_din    = 0;
    wire[31:0]  checksum_dout;
    FletcherChecksumCorrect #(
        .Width(32)
    ) FletcherChecksumCorrect32(
        .clk    (checksum_clk   ),
        .rst    (checksum_rst   ),
        .en     (checksum_en    ),
        .din    (checksum_din   ),
        .dout   (checksum_dout  )
    );
    
    task _ChecksumConsumeWord(input[15:0] word); begin
        // Treat the word as a little-endian uint16, mimicking the checksum
        // algorithm on the host computer reading from the SD card
        checksum_din   = HostFromLittle16.Swap(word);
        checksum_en    = 1; #1;
        checksum_clk   = 1; #1;
        checksum_clk   = 0; #1;
        checksum_en    = 0; #1;
    end endtask
    
    reg[31:0] _HeaderWordCount     = 0;
    reg[31:0] _WordCount           = 0;
    reg[31:0] _WordInitialValue    = 0;
    reg[31:0] _WordDelta           = 0;
    reg[31:0] _ValidateChecksum    = 0;
    
    reg[31:0]   wordCounter             = 0;
    reg[15:0]   wordPrev                = 0;
    reg         wordValidationStarted   = 0;
    
    task Config(
        input[31:0] headerWordCount,    // Number of 16-bit words to ignore at the beginning of the received data
        input[31:0] wordCount,          // Number of 16-bit words to validate
        input[31:0] wordInitialValue,   // Expected value of the first word
        input[31:0] wordDelta,          // Expected difference between current word value and previous word value
        input[31:0] validateChecksum    // Whether to check the checksum appended to the data
    ); begin
        _HeaderWordCount   = headerWordCount;
        _WordCount         = wordCount;
        _WordInitialValue  = wordInitialValue;
        _WordDelta         = wordDelta;
        _ValidateChecksum  = validateChecksum;
    end endtask
    
    task Validate(input[15:0] word); begin
        if (wordCounter < _HeaderWordCount) begin
            _ChecksumConsumeWord(word);
        
        end else if (wordCounter < _HeaderWordCount+_WordCount) begin
            reg[15:0] wordExpected;
            reg[15:0] wordGot;
            
            _ChecksumConsumeWord(word);
            
            if (!wordValidationStarted) begin
                wordExpected = _WordInitialValue;
            end else begin
                wordExpected = HostFromLittle16.Swap(wordPrev)+_WordDelta;
            end
            
            wordGot = HostFromLittle16.Swap(word); // Unpack little-endian
            
            if (wordExpected === wordGot) begin
                $display("[WordValidator] Received valid word (expected:%h, got:%h) ✅", wordExpected, wordGot);
            end else begin
                $display("[WordValidator] Received invalid word (expected:%h, got:%h) ❌", wordExpected, wordGot);
                `Finish;
            end
            
            wordValidationStarted = 1;
        
        end else if (wordCounter == _HeaderWordCount+_WordCount+1) begin
            // Validate checksum
            if (_ValidateChecksum) begin
                // Supply one last clock to get the correct output
                checksum_clk   = 1; #1;
                checksum_clk   = 0; #1;
                
                begin
                    reg[31:0] checksumExpected;
                    reg[31:0] checksumGot;
                    
                    checksumExpected    = checksum_dout;
                    checksumGot         = HostFromLittle32.Swap(wordPrev<<16|word);
                    
                    if (checksumExpected === checksumGot) begin
                        $display("[WordValidator] Checksum valid [expected:%h got:%h] ✅", checksumExpected, checksumGot);
                    end else begin
                        $display("[WordValidator] Checksum invalid [expected:%h got:%h] ❌", checksumExpected, checksumGot);
                        `Finish;
                    end
                end
            end
        end
        
        wordPrev = word;
        wordCounter = wordCounter+1;
    end endtask
    
    task Reset; begin
        wordCounter = 0;
        wordPrev = 0;
        wordValidationStarted = 0;
        
        checksum_rst = 1; #1;
        checksum_clk = 1; #1;
        checksum_clk = 0; #1;
        checksum_rst = 0; #1;
    end endtask
endmodule

`endif // WordValidator_v