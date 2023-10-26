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

inline std::string ImageLibraryStatus(size_t count, Time::Instant first, Time::Instant last,
    std::string_view singular, std::string_view plural) {
    
    std::stringstream ss;
    ss << count << " ";
    ss << (count==1 ? singular : plural);
    
    if (Time::Absolute(first) && Time::Absolute(last)) {
        const auto tFirst = Time::Clock::TimePointFromTimeInstant(first);
        const auto tLast = Time::Clock::TimePointFromTimeInstant(last);
        const std::string strFirst = Calendar::MonthYearString(tFirst);
        const std::string strLast = Calendar::MonthYearString(tLast);
        ss << " from ";
        ss << strFirst;
//        ss << " – " << strLast; // Debug
        if (strFirst != strLast) ss << " – " << strLast;
    }
    
    return ss.str();
}

inline std::string ImageLibraryStatus(ImageLibraryPtr lib, std::string noPhotos="No photos") {
    auto lock = std::unique_lock(*lib);
    if (lib->empty()) return noPhotos;
    
    // itFirst: first loaded record
    auto itFirst = _FirstLoaded(lib);
    // No loaded photos yet
    if (itFirst == lib->end()) return noPhotos;
    // itLast: last loaded record
    auto itLast = _LastLoaded(lib);
    return ImageLibraryStatus(lib->recordCount(),
        (*itFirst)->info.timestamp, (*itLast)->info.timestamp,
        "photo", "photos");
}

} // namespace MDCStudio
