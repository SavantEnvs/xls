// Fuzzes IR value literal parsing: ParseTypedValue("bits[8]:0x12", "(bits[1]:1, ...)") and, when the
// input holds a type line followed by a value line, ParseValue against that parsed type.
#include <cstddef>
#include <cstdint>
#include <string_view>

#include "xls/ir/format_preference.h"
#include "xls/ir/ir_parser.h"
#include "xls/ir/package.h"
#include "xls/ir/value.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  std::string_view text(reinterpret_cast<const char*>(data), size);
  bool ok = false;
  auto typed = xls::Parser::ParseTypedValue(text);
  if (typed.ok()) {
    ok = true;
    (void)typed->ToString(xls::FormatPreference::kHex);
    (void)typed->ToHumanString();
  }
  size_t nl = text.find('\n');
  if (nl != std::string_view::npos) {
    xls::Package package("fuzz");
    auto type = xls::Parser::ParseType(text.substr(0, nl), &package);
    if (type.ok()) {
      auto value = xls::Parser::ParseValue(text.substr(nl + 1), *type);
      if (value.ok()) {
        ok = true;
        (void)value->ToString(xls::FormatPreference::kBinary);
      }
    }
  }
  return ok ? 0 : -1;
}
