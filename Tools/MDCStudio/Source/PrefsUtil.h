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




inline const char* DragAndDropExportFormat() {
    return PrefsGlobal()->get("DragAndDropExportFormat", ImageExporter::Formats::JPEG.name);
}

inline void DragAndDropExportFormat(const char* x) {
    PrefsGlobal()->set("DragAndDropExportFormat", x);
}




inline bool DragAndDropIncludeTimestamp() {
    return PrefsGlobal()->get("DragAndDropIncludeTimestamp", false);
}

inline void DragAndDropIncludeTimestamp(bool x) {
    PrefsGlobal()->set("DragAndDropIncludeTimestamp", x);
}





inline const char* PreviousImageExportFormat() {
    return PrefsGlobal()->get("PreviousImageExportFormat", ImageExporter::Formats::JPEG.name);
}

inline void PreviousImageExportFormat(const char* x) {
    PrefsGlobal()->set("PreviousImageExportFormat", x);
}





} // namespace MDCStudio
