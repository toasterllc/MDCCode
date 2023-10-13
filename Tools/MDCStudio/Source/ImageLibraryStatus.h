#pragma once
#include "Calendar.h"

namespace MDCStudio {

inline auto _FirstLoaded(ImageLibraryPtr x) {
    for (auto it=x->begin(); it!=x->end(); it++) {
        if ((*it)->status.loadCount) return it;
    }
    return x->end();
}

inline auto _LastLoaded(ImageLibraryPtr x) {
    for (auto it=x->rbegin(); it!=x->rend(); it++) {
        if ((*it)->status.loadCount) return it;
    }
    return x->rend();
}

inline std::string ImageLibraryStatus(ImageLibraryPtr lib, std::string noPhotos="no photos") {
    using namespace std::chrono;
    
    auto lock = std::unique_lock(*lib);
    if (lib->empty()) return noPhotos;
    
    // itFirst: first loaded record
    auto itFirst = _FirstLoaded(lib);
    // No loaded photos yet
    if (itFirst == lib->end()) return noPhotos;
    // itLast: last loaded record
    auto itLast = _LastLoaded(lib);
    
    const auto tFirst = Time::Clock::TimePointFromTimeInstant((*itFirst)->info.timestamp);
    const auto tLast = Time::Clock::TimePointFromTimeInstant((*itLast)->info.timestamp);
    const std::string strFirst = Calendar::MonthYearString(tFirst);
    const std::string strLast = Calendar::MonthYearString(tLast);
    const std::string dateDesc = strFirst + (strFirst == strLast ? "" : " – " + strLast);
    return std::to_string(lib->recordCount()) + " photos from " + dateDesc;
}

} // namespace MDCStudio
