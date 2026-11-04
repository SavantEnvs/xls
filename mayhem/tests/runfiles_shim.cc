// Stand-in for xls/common/file/get_runfile_path.cc, which needs Bazel's runfiles library. Upstream tests ask
// for files relative to the XLS source root, which is the directory test.sh runs from.
#include <filesystem>
#include <string>

#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "xls/common/file/get_runfile_path.h"

namespace xls {

absl::StatusOr<std::filesystem::path> GetXlsRunfilePath(
    const std::filesystem::path& path, std::string) {
  std::filesystem::path full = std::filesystem::current_path() / path;
  if (!std::filesystem::exists(full)) {
    return absl::NotFoundError("no such file: " + full.string());
  }
  return full;
}

absl::Status InitRunfilesDir(const std::string&) { return absl::OkStatus(); }

}  // namespace xls
