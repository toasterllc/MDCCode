#pragma once

namespace MDCStudio::ImageExporter {

struct Format {
    const char* name;
    const char* extension;
};

static const Format FormatJPEG = { "JPEG", "jpg" };
static const Format FormatPNG  = { "PNG",  "png" };

static const Format* Formats[] = {
    &FormatJPEG,
    &FormatPNG,
};

} // namespace MDCStudio::ImageExporter
