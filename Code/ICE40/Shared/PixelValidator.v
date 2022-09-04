`ifndef PixelValidator_v
`define PixelValidator_v

`include "Util.v"
`include "FletcherChecksum.v"
`include "EndianSwap.v"

`timescale 1ns/1ps

module PixelValidator();
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
    
    integer     _cfgHeaderWordCount     = 0;
    integer     _cfgImageWidth          = 0;
    integer     _cfgImageHeight         = 0;
    integer     _cfgPaddingWordCount    = 0;
    integer     _cfgPixelValidate       = 0;
    reg[15:0]   _cfgPixelInitial        = 0;
    integer     _cfgPixelDelta          = 0;
    integer     _cfgPixelFilterPeriod   = 0;
    integer     _cfgPixelFilterKeep     = 0;
    integer     _cfgChecksumValidate    = 0;
    
    `define ImagePixelCount     (_cfgImageWidth*_cfgImageHeight)
    `define ChecksumWordCount   2
    `define ImageWordCount      (_cfgHeaderWordCount + `ImagePixelCount + `ChecksumWordCount + _cfgPaddingWordCount)
    
    integer     _wordCounter                = 0;
    reg[15:0]   _wordPrev                   = 0;
    reg         _pixelValidationStarted     = 0;
    reg         _checksumReceived           = 0;
    
    task Config(
        input integer headerWordCount,      // Number of 16-bit words to ignore at the beginning of the received data
        input integer imageWidth,           // Pixel width of image
        input integer imageHeight,          // Pixel height of image
        input integer paddingWordCount,     // Number of padding words expected after the checksum
        input integer pixelValidate,        // Enable checking values of pixels
        input[15:0]   pixelInitial,         // Expected value of the first pixel
        input integer pixelDelta,           // Expected difference between current word value and previous word value
        input integer pixelFilterPeriod,    // Period of the pixel filter (used for thumbnailing)
        input integer pixelFilterKeep,      // Count of pixels to keep at the beginning of a period (used for thumbnailing)
        input integer checksumValidate      // Enable validating checksum appended to the data
    ); begin
        _cfgHeaderWordCount     = headerWordCount;
        _cfgImageWidth          = imageWidth;
        _cfgImageHeight         = imageHeight;
        _cfgPaddingWordCount    = paddingWordCount;
        _cfgPixelValidate       = pixelValidate;
        _cfgPixelInitial        = pixelInitial;
        _cfgPixelDelta          = pixelDelta;
        _cfgPixelFilterPeriod   = pixelFilterPeriod;
        _cfgPixelFilterKeep     = pixelFilterKeep;
        _cfgChecksumValidate    = checksumValidate;
        
        _wordCounter            = 0;
        _wordPrev               = 0;
        _pixelValidationStarted = 0;
        _checksumReceived       = 0;
        
        _checksum_rst = 1; #1;
        _checksum_clk = 1; #1;
        _checksum_clk = 0; #1;
        _checksum_rst = 0; #1;
    end endtask
    
    task Validate(input[15:0] word); begin
        if (_wordCounter < _cfgHeaderWordCount) begin
            _ChecksumConsumeWord(word);
        
        end else if (_wordCounter < _cfgHeaderWordCount+`ImagePixelCount) begin
            reg[15:0] wordExpected;
            reg[15:0] wordGot;
            
            _ChecksumConsumeWord(word);
            
            if (_cfgPixelValidate) begin
                if (!_pixelValidationStarted            ||
                    (_cfgPixelDelta>0 && (&_wordPrev))  ||      // Check for overflow
                    (_cfgPixelDelta<0 && (!_wordPrev))) begin   // Check for overflow
                    wordExpected = _cfgPixelInitial;
                end else begin
                    wordExpected = HostFromLittle16.Swap(_wordPrev)+_cfgPixelDelta;
                end
            
                wordGot = HostFromLittle16.Swap(word); // Unpack little-endian
            
                if (wordExpected === wordGot) begin
                    $display("[PixelValidator] Received valid word (expected:%h, got:%h) ✅", wordExpected, wordGot);
                end else begin
                    $display("[PixelValidator] Received invalid word (expected:%h, got:%h) ❌", wordExpected, wordGot);
                    `Finish;
                end
            
                _pixelValidationStarted = 1;
            end
        
        end else if (_wordCounter == _cfgHeaderWordCount+`ImagePixelCount+1) begin
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
                        $display("[PixelValidator] Checksum valid [expected:%h got:%h] ✅", checksumExpected, checksumGot);
                    end else begin
                        $display("[PixelValidator] Checksum invalid [expected:%h got:%h] ❌", checksumExpected, checksumGot);
                        `Finish;
                    end
                end
            end
        end
        
        _wordPrev = word;
        _wordCounter = _wordCounter+1;
    end endtask
    
    task Done; begin
        if (_wordCounter === `ImageWordCount) begin
            $display("[PixelValidator] Received word count: %0d (expected: %0d) ✅", _wordCounter, `ImageWordCount);
        end else begin
            $display("[PixelValidator] Received word count: %0d (expected: %0d) ❌", _wordCounter, `ImageWordCount);
            `Finish;
        end
    end endtask
endmodule

`endif // PixelValidator_v