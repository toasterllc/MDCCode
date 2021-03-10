#import "MetalTypes.h"
#import "Enum.h"

namespace CFAViewer {
    namespace ImageLayerTypes {
        enum class CFAColor : uint8_t {
            Red     = 0,
            Green   = 1,
            Blue    = 2,
        };
        
        struct RenderContext {
            simd::float3x3 colorMatrix = {
                simd::float3{1,0,0},
                simd::float3{0,1,0},
                simd::float3{0,0,1},
            };
            
            simd::float3 whitePoint_XYY_D50;
            simd::float3 whitePoint_CamRaw_D50;
            
            simd::float3 highlightFactorR = {0,0,0};
            simd::float3 highlightFactorG = {0,0,0};
            simd::float3 highlightFactorB = {0,0,0};
            
            struct {
                uint32_t left = 0;
                uint32_t right = 0;
                uint32_t top = 0;
                uint32_t bottom = 0;
                
                uint32_t width() MetalConst { return right-left; }
                uint32_t height() MetalConst { return bottom-top; }
                uint32_t count() MetalConst { return width()*height(); }
            } sampleRect;
            
            uint32_t viewWidth = 0;
            uint32_t viewHeight = 0;
            
            uint32_t imageWidth = 0;
            uint32_t imageHeight = 0;
            
            CFAColor cfa[2][2] = {{
                CFAColor::Green,
                CFAColor::Red,
            }, {
                CFAColor::Blue,
                CFAColor::Green,
            }};
            
            template <typename T>
            CFAColor cfaColor(T x, T y) MetalConst {
                return cfa[y&1][x&1];
            }
            
            template <typename T>
            CFAColor cfaColor(T pos) MetalConst {
                return cfaColor(pos.x, pos.y);
            }
        };
        
        class TileAxis {
        private:
            static uint32_t _tileCount(uint32_t axisSize, uint32_t tileSize) {
                const uint32_t count = axisSize/tileSize;
                const uint32_t excess = axisSize%tileSize;
                const uint32_t rightSlice = excess/2;
                const uint32_t leftSlice = excess-rightSlice;
                return count + (leftSlice?1:0) + (rightSlice?1:0);
            }
            
        public:
            TileAxis(uint32_t axisSize, uint32_t tileSize) {
                _axisSize = axisSize;
                _tileSize = tileSize;
                
                const uint32_t excess = _axisSize%_tileSize;
                _rightSlice = excess/2;
                _leftSlice = excess-_rightSlice;
                tileCount = (_axisSize/_tileSize) + (_leftSlice?1:0) + (_rightSlice?1:0);
            }
            
            // tileOffset(): returns of the offset for the tile at a given index.
            // Border tiles and interior tiles will overlap.
            uint32_t tileOffset(uint32_t idx) MetalConst {
                if (_leftSlice && idx==0) return 0;
                if (_rightSlice && idx==tileCount-1) return _axisSize-_tileSize;
                return _leftSlice + _tileSize*(_leftSlice ? idx-1 : idx);
            }
            
            // tileIndex(): returns the index for a tile at the given offset.
            // For border tiles that overlap interior tiles, gives precedence to interior tiles.
            uint32_t tileIndex(uint32_t off) MetalConst {
                if (off < _leftSlice) return 0;
                if (off >= _axisSize-_rightSlice) return tileCount-1;
                return ((off-_leftSlice)/_tileSize) + (_leftSlice?1:0);
            }
            
            // Templated to allow support for doubles, while also being usable
            // from Metal shader contexts (which doesn't support doubles).
            template <typename T>
            T tileNormalizedCenter(uint32_t idx) MetalConst {
                return ((T)tileOffset(idx) + (T)_tileSize/2) / _axisSize;
            }
            
            uint32_t tileCount = 0;
            
        private:
            uint32_t _axisSize = 0;
            uint32_t _tileSize = 0;
            uint32_t _leftSlice = 0;
            uint32_t _rightSlice = 0;
        };
        
        class TileGrid {
        public:
            TileGrid(uint32_t imageWidth, uint32_t imageHeight, uint32_t tileSize) :
            x(imageWidth, tileSize),
            y(imageHeight, tileSize) {}
            
            const TileAxis x;
            const TileAxis y;
        };
        
        enum class TileDir : uint8_t {
            X = 0,
            Y = 1,
        };
        
        class TileShifts {
        private:
            static MetalConst size_t _MaxLen = 20;
            float _shifts[_MaxLen][_MaxLen]; // _shifts[TileY][TileX]
        
        public:
#if !__METAL_VERSION__
            float& operator()(uint32_t x, uint32_t y) { return _shifts[y][x]; }
#endif
            MetalConst float& operator()(uint32_t x, uint32_t y) MetalConst { return _shifts[y][x]; }
        };
    };
};
