// Fuzzes the DSLX scanner alone, with and without whitespace/comment tokens.
#include <cstddef>
#include <cstdint>
#include <string>

#include "xls/dslx/frontend/pos.h"
#include "xls/dslx/frontend/scanner.h"
#include "xls/dslx/frontend/token.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 1) return -1;
  bool include_trivia = data[0] & 1;
  std::string text(reinterpret_cast<const char*>(data) + 1, size - 1);
  xls::dslx::FileTable file_table;
  xls::dslx::Fileno fileno = file_table.GetOrCreate("fuzz.x");
  xls::dslx::Scanner scanner(file_table, fileno, std::move(text), include_trivia);
  auto tokens = scanner.PopAll();
  if (!tokens.ok()) return -1;
  for (const xls::dslx::Token& t : *tokens) { (void)t.ToString(); (void)t.ToRepr(file_table); }
  return 0;
}
