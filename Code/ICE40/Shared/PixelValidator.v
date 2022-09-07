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
        // $display("[PixelValidator] checksum consume word (index: %0d): %h", _wordIdx, word);
        
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
    integer     _cfgChecksumWordCount   = 0;
    integer     _cfgPaddingWordCount    = 0;
    integer     _cfgPixelValidate       = 0;
    reg[15:0]   _cfgPixelInitial        = 0;
    integer     _cfgPixelDelta          = 0;
    integer     _cfgPixelFilterPeriod   = 0;
    integer     _cfgPixelFilterKeep     = 0;
    
    `define ImagePixelCount     (_cfgImageWidth*_cfgImageHeight)
    `define ImageWordCount      (_cfgHeaderWordCount + `ImagePixelCount + _cfgChecksumWordCount + _cfgPaddingWordCount)
    
    integer     _wordIdx                    = 0;
    reg[15:0]   _wordPrev                   = 0;
    integer     _pixelIdx                   = 0;
    
    task Config(
        input integer headerWordCount,      // Number of 16-bit words to ignore at the beginning of the received data
        input integer imageWidth,           // Pixel width of image
        input integer imageHeight,          // Pixel height of image
        input integer checksumWordCount,    // Number of checksum words expected after the pixels
        input integer paddingWordCount,     // Number of padding words expected after the checksum
        input integer pixelValidate,        // Enable checking values of pixels
        input[15:0]   pixelInitial,         // Expected value of the first pixel
        input integer pixelDelta,           // Expected difference between current word value and previous word value
        input integer pixelFilterPeriod,    // Period of the pixel filter (used for thumbnailing)
        input integer pixelFilterKeep       // Count of pixels to keep at the beginning of a period (used for thumbnailing)
    ); begin
        _cfgHeaderWordCount     = headerWordCount;
        _cfgImageWidth          = imageWidth;
        _cfgImageHeight         = imageHeight;
        _cfgChecksumWordCount   = checksumWordCount;
        _cfgPaddingWordCount    = paddingWordCount;
        _cfgPixelValidate       = pixelValidate;
        _cfgPixelInitial        = pixelInitial;
        _cfgPixelDelta          = pixelDelta;
        _cfgPixelFilterPeriod   = pixelFilterPeriod;
        _cfgPixelFilterKeep     = pixelFilterKeep;
        
        _wordIdx                = 0;
        _wordPrev               = 0;
        _pixelIdx               = 0;
        
        _checksum_rst = 1; #1;
        _checksum_clk = 1; #1;
        _checksum_clk = 0; #1;
        _checksum_rst = 0; #1;
        
        // Validate _cfgChecksumWordCount
        if (_cfgChecksumWordCount!==0 && _cfgChecksumWordCount!==2) begin
            $display("[PixelValidator] Invalid checksum word count: %0d ❌", _cfgChecksumWordCount);
            `Finish;
        end
        
        $display("[PixelValidator] Config() called:");
        $display("[PixelValidator]   _cfgHeaderWordCount:   %0d",  _cfgHeaderWordCount);
        $display("[PixelValidator]   _cfgImageWidth:        %0d",  _cfgImageWidth);
        $display("[PixelValidator]   _cfgImageHeight:       %0d",  _cfgImageHeight);
        $display("[PixelValidator]   _cfgChecksumWordCount: %0d",  _cfgChecksumWordCount);
        $display("[PixelValidator]   _cfgPaddingWordCount:  %0d",  _cfgPaddingWordCount);
        $display("[PixelValidator]   _cfgPixelValidate:     %0d",  _cfgPixelValidate);
        $display("[PixelValidator]   _cfgPixelInitial:      0x%x", _cfgPixelInitial);
        $display("[PixelValidator]   _cfgPixelDelta:        %0d",  _cfgPixelDelta);
        $display("[PixelValidator]   _cfgPixelFilterPeriod: %0d",  _cfgPixelFilterPeriod);
        $display("[PixelValidator]   _cfgPixelFilterKeep:   %0d",  _cfgPixelFilterKeep);
        $display("[PixelValidator]   _cfgHeaderWordCount:   %0d",  _cfgHeaderWordCount);
    end endtask
    
    function[15:0] PixelExpectedValue();
        integer imgWidth;
        integer kx;
        integer ky;
        integer px;
        integer py;
        integer pidx;
        // reg[31:0] pixelX;
        // reg[31:0] pixelY;
        begin
            // Translate the thumbnail pixel index `_pixelIdx` to the absolute index in the full-size image
            imgWidth = (_cfgImageWidth*_cfgPixelFilterPeriod)/_cfgPixelFilterKeep;
            kx = _pixelIdx % _cfgImageWidth;
            ky = _cfgPixelFilterKeep * _cfgImageWidth;
            px = (kx/_cfgPixelFilterKeep)*_cfgPixelFilterPeriod + (kx%_cfgPixelFilterKeep);
            py = (_pixelIdx/ky)          *_cfgPixelFilterPeriod + ((_pixelIdx%ky)/_cfgImageWidth);
            pidx = (py*imgWidth) + px;
            // $display("[PixelValidator] _pixelIdx:%0d -> px:%0d py:%0d [imgWidth:%0d]", _pixelIdx, px, py, imgWidth);
            // Calculate the expected pixel value given the pixel index
            PixelExpectedValue = _cfgPixelInitial + (pidx*_cfgPixelDelta);
        end
    endfunction
    
    task Validate(input[15:0] word); begin
        // Handle header words
        if (_wordIdx < _cfgHeaderWordCount) begin
            _ChecksumConsumeWord(word);
        
        // Handle pixels
        end else if (_wordIdx < _cfgHeaderWordCount+`ImagePixelCount) begin
            reg[15:0] pixelExpected;
            reg[15:0] pixelGot;
            
            _ChecksumConsumeWord(word);
            
            if (_cfgPixelValidate) begin
                pixelExpected = PixelExpectedValue();
                pixelGot = HostFromLittle16.Swap(word); // Unpack little-endian
                
                if (pixelExpected === pixelGot) begin
                    $display("[PixelValidator] Received valid pixel (index:%0d, expected:%h, got:%h) ✅", _wordIdx, pixelExpected, pixelGot);
                end else begin
                    $display("[PixelValidator] Received invalid pixel (index:%0d, expected:%h, got:%h) ❌", _wordIdx, pixelExpected, pixelGot);
                    `Finish;
                end
                
                _pixelIdx++;
            end
        
        // Handle checksum
        end else if (_cfgChecksumWordCount && (_wordIdx === _cfgHeaderWordCount+`ImagePixelCount+1)) begin
            // Validate checksum
            // Supply one last clock to get the correct output
            _checksum_clk   = 1; #1;
            _checksum_clk   = 0; #1;
            
            begin
                reg[31:0] checksumExpected;
                reg[31:0] checksumGot;
                
                checksumExpected    = _checksum_dout;
                checksumGot         = HostFromLittle32.Swap(_wordPrev<<16|word);
                
                if (checksumExpected === checksumGot) begin
                    $display("[PixelValidator] Checksum valid [index:%0d, expected:%h got:%h] ✅", _wordIdx, checksumExpected, checksumGot);
                end else begin
                    $display("[PixelValidator] Checksum invalid [index:%0d, expected:%h got:%h] ❌", _wordIdx, checksumExpected, checksumGot);
                    `Finish;
                end
            end
        
        // Handle padding words
        end else if (_wordIdx >= _cfgHeaderWordCount+`ImagePixelCount+_cfgChecksumWordCount) begin
            if (_wordIdx < `ImageWordCount) begin
                $display("[PixelValidator] Received expected padding word (index:%0d, word:%h, expectedCount:%0d) ✅", _wordIdx, HostFromLittle16.Swap(word), `ImageWordCount);
            end else begin
                $display("[PixelValidator] Received unexpected padding word (index:%0d, word:%h, expectedCount:%0d) ❌", _wordIdx, HostFromLittle16.Swap(word), `ImageWordCount);
                `Finish;
            end
        end
        
        _wordPrev = word;
        _wordIdx = _wordIdx+1;
    end endtask
    
    task Done; begin
        if (_wordIdx === `ImageWordCount) begin
            $display("[PixelValidator] Received expected word count: %0d (expected: %0d) ✅", _wordIdx, `ImageWordCount);
        end else begin
            $display("[PixelValidator] Received unexpected word count: %0d (expected: %0d) ❌", _wordIdx, `ImageWordCount);
            `Finish;
        end
    end endtask
endmodule

`endif // PixelValidator_v