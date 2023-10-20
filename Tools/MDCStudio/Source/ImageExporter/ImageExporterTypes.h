#pragma once

namespace MDCStudio::ImageExporter {

struct Format {
    const char* name;
    const char* extension;
    NSString* uti;
};

static const Format FormatJPEG = { "JPEG", "jpg", (NSString*)kUTTypeJPEG };
static const Format FormatPNG  = { "PNG",  "png", (NSString*)kUTTypePNG };

static const Format* Formats[] = {
    &FormatJPEG,
    &FormatPNG,
};

} // namespace MDCStudio::ImageExporter
