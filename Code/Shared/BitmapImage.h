#import <Cocoa/Cocoa.h>
#import <filesystem>

template<typename T>
class BitmapImage {
public:
    BitmapImage(const std::filesystem::path& path) : BitmapImage([NSData dataWithContentsOfFile:@(path.c_str())]) {}
    
    BitmapImage(NSData* nsdata) {
        image = [NSBitmapImageRep imageRepWithData:nsdata];
        assert(image);
        
        assert([image bitsPerSample] == 8*sizeof(T));
        width = [image pixelsWide];
        height = [image pixelsHigh];
        // samplesPerPixel = number of samples per pixel, including padding samples
        // validSamplesPerPixel = number of samples per pixel, excluding padding samples
        // For example, sometimes the alpha channel exists but isn't used, in which case:
        //        samplesPerPixel = 4
        //   validSamplesPerPixel = 3
        samplesPerPixel = ([image bitsPerPixel]/8) / sizeof(T);
        assert(samplesPerPixel==3 || samplesPerPixel==4);
        validSamplesPerPixel = [image samplesPerPixel];
        assert(validSamplesPerPixel==3 || validSamplesPerPixel==4);
        data = (T*)[image bitmapData];
        dataLen = width*height*samplesPerPixel*sizeof(T);
    }
    
    T sample(int y, int x, size_t channel) {
        assert(channel < validSamplesPerPixel);
        const size_t sx = _mirrorClamp(width, x);
        const size_t sy = _mirrorClamp(height, y);
        const size_t idx = samplesPerPixel*(width*sy+sx) + channel;
        assert(idx < dataLen);
        return data[idx];
    }
    
    NSBitmapImageRep* image = nullptr;
    size_t width = 0;
    size_t height = 0;
    size_t samplesPerPixel = 0;
    size_t validSamplesPerPixel = 0;
    T* data = nullptr;
    size_t dataLen = 0;
    
private:
    static size_t _mirrorClamp(size_t N, int n) {
        if (n < 0)                  return -n;
        else if ((size_t)n >= N)    return 2*(N-1)-(size_t)n;
        else                        return n;
    }
};
