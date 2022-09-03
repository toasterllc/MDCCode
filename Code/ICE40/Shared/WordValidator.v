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
    reg         _checksum_clk   = 0;
    reg         _checksum_rst   = 0;
    reg         _checksum_en    = 0;
    reg[15:0]   _checksum_din   = 0;
    wire[31:0]  _checksum_dout;
    FletcherChecksumCorrect #(
        .Width(32)
    ) FletcherChecksumCorrect32(
        .clk    (_checksum_clk  ),
        .rst    (_checksum_rst  ),
        .en     (_checksum_en   ),
        .din    (_checksum_din  ),
        .dout   (_checksum_dout )
    );
    
    task _ChecksumConsumeWord(input[15:0] word); begin
        // Treat the word as a little-endian uint16, mimicking the checksum
        // algorithm on the host computer reading from the SD card
        _checksum_din   = HostFromLittle16.Swap(word);
        _checksum_en    = 1; #1;
        _checksum_clk   = 1; #1;
        _checksum_clk   = 0; #1;
        _checksum_en    = 0; #1;
    end endtask
    
    reg[31:0]   _cfgHeaderWordCount         = 0;
    reg[31:0]   _cfgBodyWordCount           = 0;
    reg[31:0]   _cfgBodyWordInitialValue    = 0;
    reg         _cfgBodyWordDeltaValidate   = 0;
    integer     _cfgBodyWordDelta           = 0;
    reg[31:0]   _cfgChecksumValidate        = 0;
    
    reg[31:0]   _wordCounter                = 0;
    reg[15:0]   _wordPrev                   = 0;
    reg         _wordValidationStarted      = 0;
    reg         _checksumReceived           = 0;
    
    task Config(
        input[31:0] headerWordCount,        // Number of 16-bit words to ignore at the beginning of the received data
        input[31:0] bodyWordCount,          // Number of 16-bit words to validate
        input[31:0] bodyWordInitialValue,   // Expected value of the first word
        input       bodyWordDeltaValidate,     // Enable checking the delta between words
        integer     bodyWordDelta,          // Expected difference between current word value and previous word value
        input[31:0] checksumValidate        // Whether to check the checksum appended to the data
    ); begin
        _cfgHeaderWordCount        = headerWordCount;
        _cfgBodyWordCount          = bodyWordCount;
        _cfgBodyWordInitialValue   = bodyWordInitialValue;
        _cfgBodyWordDeltaValidate  = bodyWordDeltaValidate;
        _cfgBodyWordDelta          = bodyWordDelta;
        _cfgChecksumValidate       = checksumValidate;
    end endtask
    
    task Validate(input[15:0] word); begin
        if (_wordCounter < _cfgHeaderWordCount) begin
            _ChecksumConsumeWord(word);
        
        end else if (_wordCounter < _cfgHeaderWordCount+_cfgBodyWordCount) begin
            reg[15:0] wordExpected;
            reg[15:0] wordGot;
            
            _ChecksumConsumeWord(word);
            
            if (_cfgBodyWordDeltaValidate) begin
                if (!_wordValidationStarted                 ||
                    (_cfgBodyWordDelta>0 && (&_wordPrev))   ||      // Check for overflow
                    (_cfgBodyWordDelta<0 && (!_wordPrev))) begin    // Check for overflow
                    wordExpected = _cfgBodyWordInitialValue;
                end else begin
                    wordExpected = HostFromLittle16.Swap(_wordPrev)+_cfgBodyWordDelta;
                end
            
                wordGot = HostFromLittle16.Swap(word); // Unpack little-endian
            
                if (wordExpected === wordGot) begin
                    $display("[WordValidator] Received valid word (expected:%h, got:%h) ✅", wordExpected, wordGot);
                end else begin
                    $display("[WordValidator] Received invalid word (expected:%h, got:%h) ❌", wordExpected, wordGot);
                    `Finish;
                end
            
                _wordValidationStarted = 1;
            end
        
        end else if (_wordCounter == _cfgHeaderWordCount+_cfgBodyWordCount+1) begin
            // Validate checksum
            if (_cfgChecksumValidate) begin
                // Supply one last clock to get the correct output
                _checksum_clk   = 1; #1;
                _checksum_clk   = 0; #1;
                
                begin
                    reg[31:0] checksumExpected;
                    reg[31:0] checksumGot;
                    
                    checksumExpected    = _checksum_dout;
                    checksumGot         = HostFromLittle32.Swap(_wordPrev<<16|word);
                    _checksumReceived    = 1;
                    
                    if (checksumExpected === checksumGot) begin
                        $display("[WordValidator] Checksum valid [expected:%h got:%h] ✅", checksumExpected, checksumGot);
                    end else begin
                        $display("[WordValidator] Checksum invalid [expected:%h got:%h] ❌", checksumExpected, checksumGot);
                        `Finish;
                    end
                end
            end
        end
        
        _wordPrev = word;
        _wordCounter = _wordCounter+1;
    end endtask
    
    task Reset; begin
        if (_wordCounter && _cfgChecksumValidate && !_checksumReceived) begin
            $display("[WordValidator] Didn't receive checksum ❌");
            `Finish;
        end
        
        _wordCounter             = 0;
        _wordPrev                = 0;
        _wordValidationStarted   = 0;
        _checksumReceived        = 0;
        
        _checksum_rst = 1; #1;
        _checksum_clk = 1; #1;
        _checksum_clk = 0; #1;
        _checksum_rst = 0; #1;
    end endtask
endmodule

`endif // WordValidator_v