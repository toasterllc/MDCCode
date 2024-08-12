#import <Foundation/Foundation.h>
#import <optional>
#import "Prefs.h"
#import "ImageCorner/ImageCorner.h"
#import "ImageExporter/ImageExporterTypes.h"

namespace MDCStudio::PrefsUtil {

inline const char* PreviousImageExportFormat() {
    return PrefsGlobal()->get("PreviousImageExportFormat", ImageExporter::Formats::JPEG.name);
}

inline void PreviousImageExportFormat(const char* x) {
    PrefsGlobal()->set("PreviousImageExportFormat", x);
}

namespace Timestamp {

    inline ImageCorner Corner() {
        return PrefsGlobal()->get("Timestamp.Corner", ImageCorner::BottomRight);
    }
    
    inline void Corner(ImageCorner x) {
        PrefsGlobal()->set("Timestamp.Corner", x);
    }
    
    inline bool Visible() {
        return PrefsGlobal()->get("Timestamp.Visible", false);
    }
    
    inline void Visible(bool x) {
        PrefsGlobal()->set("Timestamp.Visible", x);
    }

} // namespace Timestamp

namespace DragAndDrop {

//    inline const char* ExportFormat() {
//        return PrefsGlobal()->get("DragAndDrop.ExportFormat", ImageExporter::Formats::JPEG.name);
//    }
//    
//    inline void ExportFormat(const char* x) {
//        PrefsGlobal()->set("DragAndDrop.ExportFormat", x);
//    }
    
    inline const MDCStudio::ImageExporter::Format* ExportFormat() {
        const char* fmtName = PrefsGlobal()->get("DragAndDrop.ExportFormat", ImageExporter::Formats::JPEG.name);
        return MDCStudio::ImageExporter::Formats::FormatForName(fmtName);
    }
    
    inline void ExportFormat(const MDCStudio::ImageExporter::Format* x) {
        PrefsGlobal()->set("DragAndDrop.ExportFormat", x->name);
//        return MDCStudio::ImageExporter::Formats::FormatForName(fmtName);
//        
//        PrefsGlobal()->set("DragAndDrop.ExportFormat", x);
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
