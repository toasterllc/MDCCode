#import <Cocoa/Cocoa.h>
#import "ImageExporter/ImageExporterTypes.h"

namespace MDCStudio::ImageExportDialog {

using Handler = void(^)(const ImageExporter::Format* fmt, NSString* path);
void Show(NSWindow* window, bool batch, Handler handler);

} // namespace MDCStudio::ImageExportDialog

