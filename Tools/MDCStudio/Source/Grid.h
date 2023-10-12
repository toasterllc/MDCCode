#pragma once

#ifdef __METAL_VERSION__
namespace std = metal;
#else
#include <algorithm>
#endif

#ifdef __METAL_VERSION__
#define CONSTANT constant const
#define CONSTANT_IF_METAL constant const
#else
#define CONSTANT const
#define CONSTANT_IF_METAL
#endif

#warning TODO: migrate int32_t to uint32_t where it makes sense (eg: containerWidth, elementCount). currently everything is int32_t.
#warning TODO: can we de-metalify this class but still use it from Metal?

class Grid {
public:
    struct Vector {
        int32_t x = 0;
        int32_t y = 0;
    };
    
    using Size = Vector;
    using Point = Vector;
    
    struct Rect {
        Point point;
        Size size;
    };
    
    struct IndexRange {
        int32_t start = 0;
        int32_t count = 0;
    };
    
    struct IndexRect {
        IndexRange x;
        IndexRange y;
    };
    
    struct BorderSize {
        int32_t left    = 0;
        int32_t right   = 0;
        int32_t top     = 0;
        int32_t bottom  = 0;
    };
    
    CONSTANT BorderSize& borderSize() CONSTANT { return _borderSize; }
    void setBorderSize(CONSTANT BorderSize& x) {
        _borderSize = x;
        _computed.valid = false;
    }
    
    CONSTANT Size& cellSize() CONSTANT { return _cellSize; }
    void setCellSize(CONSTANT Size& x) {
        _cellSize = x;
        _computed.valid = false;
    }
    
    CONSTANT Size& cellSpacing() CONSTANT { return _cellSpacing; }
    void setCellSpacing(CONSTANT Size& x) {
        _cellSpacing = x;
        _computed.valid = false;
    }
    
    int32_t containerWidth() CONSTANT { return _containerWidth; }
    void setContainerWidth(int32_t x) {
        _containerWidth = x;
        _computed.valid = false;
    }
    
    int32_t elementCount() CONSTANT { return _elementCount; }
    void setElementCount(int32_t x) {
        _elementCount = x;
        _computed.valid = false;
    }
    
    int32_t columnCount()     CONSTANT_IF_METAL { recompute(); return _computed.columnCount; }
    int32_t rowCount()        CONSTANT_IF_METAL { recompute(); return _computed.rowCount; }
    int32_t containerHeight() CONSTANT_IF_METAL { recompute(); return _computed.containerHeight; }
    int32_t extraBorderX()    CONSTANT_IF_METAL { recompute(); return _computed.extraBorderX; }
    
    void recompute() CONSTANT_IF_METAL {
#ifdef __METAL_VERSION__
        assert(_computed.valid);
#else
        if (_computed.valid) return;
        
        // Compute .columnCount
        {
            const int32_t usableWidth = std::max((int32_t)0, _containerWidth-_borderSize.left-_borderSize.right);
            _computed.columnCount = std::max((int32_t)1, usableWidth / (_cellSize.x + _cellSpacing.x));
            
            const int32_t minUsedWidth = (_computed.columnCount*_cellSize.x) + ((_computed.columnCount-1) * _cellSpacing.x);
            
            // The last cell doesn't have horizontal spacing, so it's possible that we miscalculated
            // columnCount and it's 1 less than the correct value, so correct that.
            if ((minUsedWidth + _cellSize.x + _cellSpacing.x) <= usableWidth) {
                _computed.columnCount++;
            }
        }
        
        // Compute .rowCount
        {
            _computed.rowCount = std::max((int32_t)1, (_elementCount/_computed.columnCount) + ((_elementCount%_computed.columnCount) ? 1 : 0));
        }
        
        // Compute .containerHeight
        {
            _computed.containerHeight = _borderSize.top+_borderSize.bottom + (_computed.rowCount*_cellSize.y) + ((_computed.rowCount-1)*_cellSpacing.y);
        }
        
        // Compute _computed.extraBorderX
        {
            if (_computed.rowCount > 1) {
                const int32_t usedWidth = _borderSize.left + _borderSize.right + (_computed.columnCount*_cellSize.x) + ((_computed.columnCount-1)*_cellSpacing.x);
                _computed.extraBorderX = (_containerWidth-usedWidth)/2;
            } else {
                _computed.extraBorderX = 0;
            }
        }
        
        _computed.valid = true;
#endif
    }
    
    Rect rectForCellIndex(int32_t cellIndex) CONSTANT_IF_METAL {
        recompute();
        
        const int32_t xIndex = cellIndex % _computed.columnCount;
        const int32_t yIndex = cellIndex / _computed.columnCount;
        return Rect{
            .point = {
                _borderSize.left + _computed.extraBorderX + (xIndex * (_cellSize.x + _cellSpacing.x)),
                _borderSize.top + (yIndex * (_cellSize.y + _cellSpacing.y)),
            },
            .size = _cellSize,
        };
    }
    
    // indexRectForRect(): returns the row/column range for the given rect
    IndexRect indexRectForRect(Rect rect) CONSTANT_IF_METAL {
        recompute();
        
        const int32_t combinedCellWidth = (_cellSize.x + _cellSpacing.x);
        const int32_t combinedCellHeight = (_cellSize.y + _cellSpacing.y);
        
        const int32_t minX = rect.point.x - _borderSize.left - _computed.extraBorderX;
        const int32_t maxX = (rect.point.x + rect.size.x) - _borderSize.left - _computed.extraBorderX - 1;
        const int32_t minY = rect.point.y - _borderSize.top;
        const int32_t maxY = (rect.point.y + rect.size.y) - _borderSize.top - 1;
        
        int32_t minXIndex = _DivFloor(minX, combinedCellWidth);
        int32_t maxXIndex = _DivFloor(maxX, combinedCellWidth);
        int32_t minYIndex = _DivFloor(minY, combinedCellHeight);
        int32_t maxYIndex = _DivFloor(maxY, combinedCellHeight);
        
        const bool minXInCell = _InRangeExclusive(minX%combinedCellWidth, 0, _cellSize.x) && _InRange(minXIndex, 0, _computed.columnCount-1);
        const bool minYInCell = _InRangeExclusive(minY%combinedCellHeight, 0, _cellSize.y) && _InRange(minYIndex, 0, _computed.rowCount-1);
        
        if (!minXInCell) minXIndex++;
        if (!minYInCell) minYIndex++;
        
        // Sanity-check our result
        if (minXIndex>maxXIndex || minYIndex>maxYIndex) {
            return IndexRect{};
        }
        
        if ((minXIndex<0 && maxXIndex<0) ||
            (minXIndex>=_computed.columnCount && maxXIndex>=_computed.columnCount)) {
            return IndexRect{};
        }
        
        if ((minYIndex<0 && maxYIndex<0) ||
            (minYIndex>=_computed.rowCount && maxYIndex>=_computed.rowCount)) {
            return IndexRect{};
        }
        
        minXIndex = std::clamp(minXIndex, 0, _computed.columnCount-1);
        maxXIndex = std::clamp(maxXIndex, 0, _computed.columnCount-1);
        minYIndex = std::clamp(minYIndex, 0, _computed.rowCount-1);
        maxYIndex = std::clamp(maxYIndex, 0, _computed.rowCount-1);
        
        return IndexRect{
            .x = {minXIndex, maxXIndex-minXIndex+1},
            .y = {minYIndex, maxYIndex-minYIndex+1},
        };
    }
    
    // indexRangeForIndexRect(): converts an IndexRect to a range of indexes
    // The returned range is clamped to the current valid range of indexes, based on _elementCount.
    IndexRange indexRangeForIndexRect(CONSTANT IndexRect& indexRect) CONSTANT_IF_METAL {
        recompute();
        
        if (!_elementCount) return IndexRange{};
        if (!indexRect.x.count) return IndexRange{};
        if (!indexRect.y.count) return IndexRange{};
        
        const int32_t xmin = indexRect.x.start;
        const int32_t ymin = indexRect.y.start;
        const int32_t xmax = xmin+indexRect.x.count-1;
        const int32_t ymax = ymin+indexRect.y.count-1;
        
        const int32_t start = std::clamp((ymin*_computed.columnCount+xmin), 0, _elementCount-1);
        const int32_t end = std::clamp((ymax*_computed.columnCount+xmax), 0, _elementCount-1);
        if (end < start) return IndexRange{};
        
        return IndexRange{start, end-start+1};
    }
    
private:
    template <typename T>
    static bool _InRange(T x, T lo, T hi) {
        return x>=lo && x<=hi;
    }
    
    template <typename T>
    static bool _InRangeExclusive(T x, T lo, T hi) {
        return x>=lo && x<hi;
    }
    
    static int32_t _DivFloor(int32_t num, int32_t denom) {
        if (num >= 0) {
            return num/denom;
        } else {
            return -((-num+denom-1)/denom);
        }
    }
    
    BorderSize _borderSize;
    Size _cellSize;
    Size _cellSpacing;
    int32_t _containerWidth = 0;
    int32_t _elementCount   = 0;
    
    // Computed properties
    struct {
        bool valid = false;
        int32_t columnCount     = 0;
        int32_t rowCount        = 0;
        int32_t containerHeight = 0;
        int32_t extraBorderX    = 0;
    } _computed;
};
