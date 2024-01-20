#import "ImageSource.h"

namespace MDCStudio {

struct MDCDevice : ImageSource {

    void init(const Path& dir) {
        printf("MDCDevice::init() %p\n", this);
        ImageSource::init(dir); // Call super
        
        // Give device a default name
        if (name() == "") {
            name("Photon");
        }
    }

};
using MDCDevicePtr = SharedPtr<MDCDevice>;

} // namespace MDCStudio
