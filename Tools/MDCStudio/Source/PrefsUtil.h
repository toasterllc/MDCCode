#import <Foundation/Foundation.h>
#import <optional>
#import "Prefs.h"
#import "ImageCorner/ImageCorner.h"
#import "ImageExporter/ImageExporterTypes.h"

namespace MDCStudio::PrefsUtil {

inline ImageCorner TimestampImageCorner() {
    return PrefsGlobal()->get("TimestampImageCorner", ImageCorner::BottomRight);
}

inline void TimestampImageCorner(ImageCorner x) {
    PrefsGlobal()->set("TimestampImageCorner", x);
}

inline const char* PreviousImageExportFormat() {
    return PrefsGlobal()->get("PreviousImageExportFormat", ImageExporter::Formats::JPEG.name);
}

inline void PreviousImageExportFormat(const char* x) {
    PrefsGlobal()->set("PreviousImageExportFormat", x);
}

namespace DragAndDrop {

    inline const char* ExportFormat() {
        return PrefsGlobal()->get("DragAndDrop.ExportFormat", ImageExporter::Formats::JPEG.name);
    }
    
    inline void ExportFormat(const char* x) {
        PrefsGlobal()->set("DragAndDrop.ExportFormat", x);
    }
    
    inline bool IncludeTimestamp() {
        return PrefsGlobal()->get("DragAndDrop.IncludeTimestamp", false);
    }
    
    inline void IncludeTimestamp(bool x) {
        PrefsGlobal()->set("DragAndDrop.IncludeTimestamp", x);
    }

} // namespace DragAndDrop

namespace ImageGrid {

    inline bool SortNewestFirst() {
        return PrefsGlobal()->get("ImageGrid.SortNewestFirst", true);
    }
    
    inline void SortNewestFirst(bool x) {
        return PrefsGlobal()->set("ImageGrid.SortNewestFirst", x);
    }

} // namespace ImageGrid

} // namespace MDCStudio::PrefsUtil
