#import <Cocoa/Cocoa.h>
#import <optional>
#import <functional>
#import "ImageExporter/ImageExporterTypes.h"

namespace MDCStudio::ImageExportSaveDialog {

struct Result {
    const ImageExporter::Format* format;
    NSString* path;
};

using Handler = std::function<void(const Result&)>;
void Show(NSWindow* window, bool batch, NSString* filename, Handler handler);

} // namespace MDCStudio::ImageExportSaveDialog

