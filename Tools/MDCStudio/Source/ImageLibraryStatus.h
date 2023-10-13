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
    
    using namespace std::chrono;
    const auto tFirst = Time::Clock::TimePointFromTimeInstant(first);
    const auto tLast = Time::Clock::TimePointFromTimeInstant(last);
    const std::string strFirst = Calendar::MonthYearString(tFirst);
    const std::string strLast = Calendar::MonthYearString(tLast);
    const std::string dateDesc = strFirst + (strFirst == strLast ? "" : " – " + strLast);
    if (count == 1) {
        return std::to_string(count) + " " + std::string(singular) + " from " + dateDesc;
    } else {
        return std::to_string(count) + " " + std::string(plural) + " from " + dateDesc;
    }
}

inline std::string ImageLibraryStatus(ImageLibraryPtr lib, std::string noPhotos="no photos") {
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
