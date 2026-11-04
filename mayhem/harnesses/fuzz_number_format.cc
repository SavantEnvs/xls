// Fuzzes number-literal parsing (ParseNumber and friends) and IR format-string parsing.
// The first input byte selects the entry point.
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <vector>

#include "xls/ir/bits.h"
#include "xls/ir/format_strings.h"
#include "xls/ir/number_parser.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 1) return -1;
  uint8_t selector = data[0] % 6;
  std::string_view text(reinterpret_cast<const char*>(data) + 1, size - 1);
  switch (selector) {
    case 0: {
      auto bits = xls::ParseNumber(text);
      if (!bits.ok()) return -1;
      (void)bits->ToDebugString();
      return 0;
    }
    case 1: return xls::ParseNumberAsInt64(text).ok() ? 0 : -1;
    case 2: return xls::ParseNumberAsUint64(text).ok() ? 0 : -1;
    case 3: return xls::ParseNumberAsBool(text).ok() ? 0 : -1;
    case 4: {
      auto sm = xls::GetSignAndMagnitude(text);
      return sm.ok() ? 0 : -1;
    }
    default: {
      auto steps = xls::ParseFormatString(text);
      if (!steps.ok()) return -1;
      (void)xls::OperandsExpectedByFormat(*steps);
      (void)xls::StepsToXlsFormatString(*steps);
      (void)xls::StepsToVerilogFormatString(*steps);
      return 0;
    }
  }
}
