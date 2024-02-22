#pragma once
#include <filesystem>
#include <string_view>
#include <unistd.h>

namespace MDCStudio::TmpDir {

inline std::filesystem::path Path() {
    namespace fs = std::filesystem;
    return fs::temp_directory_path() / "llc.toaster.photon-transfer";
}

inline std::filesystem::path SubDirCreate(std::string_view prefix) {
    namespace fs = std::filesystem;
    // Ensure that our temporary directory exists
    fs::create_directories(Path());
    
    std::string pathTemplate = (Path() / (std::string(prefix) + ".XXXXXX")).string();
    char* path = mkdtemp(pathTemplate.data());
    assert(path);
    
    return path;
}

inline void Cleanup() {
    printf("Cleaning up temporary directory: %s\n", Path().c_str());
    std::filesystem::remove_all(Path());
}



} // namespace MDCStudio::TmpDir
