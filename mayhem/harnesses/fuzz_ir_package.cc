// Fuzzes the XLS IR text parser: Parser::ParsePackage (parse + verify) and the IR printer.
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string_view>

#include "xls/ir/ir_parser.h"
#include "xls/ir/package.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  std::string_view text(reinterpret_cast<const char*>(data), size);
  auto package = xls::Parser::ParsePackage(text);
  if (!package.ok()) return -1;
  (*package)->DumpIr();
  return 0;
}
