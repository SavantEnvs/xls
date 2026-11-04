// Fuzzes the DSLX frontend: scan + parse a whole module, then pretty-print it.
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

#include "xls/dslx/frontend/module.h"
#include "xls/dslx/frontend/parser.h"
#include "xls/dslx/frontend/pos.h"
#include "xls/dslx/frontend/scanner.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  std::string text(reinterpret_cast<const char*>(data), size);
  xls::dslx::FileTable file_table;
  xls::dslx::Fileno fileno = file_table.GetOrCreate("fuzz.x");
  xls::dslx::Scanner scanner(file_table, fileno, std::move(text));
  xls::dslx::Parser parser("fuzz", &scanner);
  auto module = parser.ParseModule();
  if (!module.ok()) return -1;
  (void)(*module)->ToString();
  return 0;
}
