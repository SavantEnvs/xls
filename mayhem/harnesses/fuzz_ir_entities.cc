// Fuzzes the per-entity IR parsers (function, proc, block, channel, types) inside an empty package.
// The first input byte selects the entry point; the rest is the IR text.
#include <cstddef>
#include <cstdint>
#include <string_view>

#include "xls/ir/ir_parser.h"
#include "xls/ir/package.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 1) return -1;
  uint8_t selector = data[0] % 7;
  std::string_view text(reinterpret_cast<const char*>(data) + 1, size - 1);
  xls::Package package("fuzz");
  bool ok = false;
  switch (selector) {
    case 0: ok = xls::Parser::ParseFunction(text, &package).ok(); break;
    case 1: ok = xls::Parser::ParseProc(text, &package).ok(); break;
    case 2: ok = xls::Parser::ParseBlock(text, &package).ok(); break;
    case 3: ok = xls::Parser::ParseChannel(text, &package).ok(); break;
    case 4: ok = xls::Parser::ParseFunctionType(text, &package).ok(); break;
    case 5: ok = xls::Parser::ParseType(text, &package).ok(); break;
    case 6: ok = xls::Parser::ParseScheduledFunction(text, &package).ok(); break;
  }
  if (!ok) return -1;
  package.DumpIr();
  return 0;
}
