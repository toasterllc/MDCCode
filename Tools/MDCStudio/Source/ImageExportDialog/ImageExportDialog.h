#import <Cocoa/Cocoa.h>
#import <optional>
#import "ImageExporter/ImageExporterTypes.h"

namespace MDCStudio::ImageExportDialog {

struct Result {
    const ImageExporter::Format* format;
    NSString* path;
};

std::optional<Result> Run(NSWindow* window, bool batch, NSString* filename);

} // namespace MDCStudio::ImageExportDialog

