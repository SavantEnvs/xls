// Known-answer probe over the XLS IR/DSLX/number parsers. Prints one `name=value` line per check;
// mayhem/test.sh compares each line against the expected value.
#include <cstdint>
#include <iostream>
#include <memory>
#include <string>

#include "absl/status/statusor.h"
#include "xls/dslx/frontend/module.h"
#include "xls/dslx/frontend/parser.h"
#include "xls/dslx/frontend/pos.h"
#include "xls/dslx/frontend/scanner.h"
#include "xls/ir/format_preference.h"
#include "xls/ir/function.h"
#include "xls/ir/ir_parser.h"
#include "xls/ir/number_parser.h"
#include "xls/ir/package.h"
#include "xls/ir/value.h"

namespace {
template <typename T>
std::string Show(const absl::StatusOr<T>& v) {
  return v.ok() ? "ok" : "error";
}

void IrPackage() {
  const char* kIr = R"(package kat

top fn add3(x: bits[32], y: bits[32], z: bits[32]) -> bits[32] {
  a: bits[32] = add(x, y, id=4)
  ret b: bits[32] = add(a, z, id=5)
}
)";
  auto pkg = xls::Parser::ParsePackage(kIr);
  std::cout << "ir_parse=" << Show(pkg) << "\n";
  if (!pkg.ok()) return;
  std::cout << "ir_package_name=" << (*pkg)->name() << "\n";
  std::cout << "ir_function_count=" << (*pkg)->functions().size() << "\n";
  auto fn = (*pkg)->GetFunction("add3");
  std::cout << "ir_function_found=" << Show(fn) << "\n";
  if (fn.ok()) {
    std::cout << "ir_function_params=" << (*fn)->params().size() << "\n";
    std::cout << "ir_function_nodes=" << (*fn)->node_count() << "\n";
    std::cout << "ir_return_op=" << xls::OpToString((*fn)->return_value()->op()) << "\n";
  }
  auto bad = xls::Parser::ParsePackage("package kat\nfn f(x: bits[8]) -> bits[8] {\n  ret y: bits[8] = bogus(x, id=2)\n}\n");
  std::cout << "ir_reject_bad_op=" << Show(bad) << "\n";
}

void IrValue() {
  auto v = xls::Parser::ParseTypedValue("bits[8]:0x12");
  std::cout << "value_parse=" << Show(v) << "\n";
  if (v.ok()) {
    std::cout << "value_hex=" << v->ToString(xls::FormatPreference::kHex) << "\n";
    std::cout << "value_dec=" << v->ToString(xls::FormatPreference::kUnsignedDecimal) << "\n";
  }
  auto t = xls::Parser::ParseTypedValue("(bits[1]:1, bits[4]:0x9)");
  if (t.ok()) std::cout << "tuple_dec=" << t->ToString(xls::FormatPreference::kUnsignedDecimal) << "\n";
}

void Dslx() {
  xls::dslx::FileTable file_table;
  xls::dslx::Fileno fileno = file_table.GetOrCreate("kat.x");
  std::string text = "fn add(x: u32, y: u32) -> u32 { x + y }\nfn main() -> u32 { add(u32:1, u32:2) }\n";
  xls::dslx::Scanner scanner(file_table, fileno, text);
  xls::dslx::Parser parser("kat", &scanner);
  auto module = parser.ParseModule();
  std::cout << "dslx_parse=" << Show(module) << "\n";
  if (module.ok()) {
    std::cout << "dslx_module_name=" << (*module)->name() << "\n";
    std::cout << "dslx_function_count=" << (*module)->GetFunctionNames().size() << "\n";
    std::cout << "dslx_has_add=" << ((*module)->GetFunction("add").has_value() ? 1 : 0) << "\n";
  }
  xls::dslx::Scanner s2(file_table, fileno, "fn f( -> {");
  xls::dslx::Parser p2("bad", &s2);
  std::cout << "dslx_reject_bad=" << Show(p2.ParseModule()) << "\n";
  xls::dslx::Scanner s3(file_table, fileno, "let x = 1;");
  auto toks = s3.PopAll();
  std::cout << "dslx_token_count=" << (toks.ok() ? static_cast<int>(toks->size()) : -1) << "\n";
}

void Numbers() {
  auto a = xls::ParseNumber("0x1234");
  std::cout << "num_hex_bits=" << (a.ok() ? a->bit_count() : -1) << "\n";
  auto i = xls::ParseNumberAsInt64("-17");
  std::cout << "num_int64=" << (i.ok() ? *i : 0) << "\n";
  auto u = xls::ParseNumberAsUint64("0b1010_0101");
  std::cout << "num_uint64=" << (u.ok() ? *u : 0) << "\n";
  std::cout << "num_reject=" << Show(xls::ParseNumberAsInt64("12ab")) << "\n";
  auto steps = xls::ParseFormatString("x={:x} y={:d}");
  std::cout << "fmt_steps=" << (steps.ok() ? static_cast<int>(steps->size()) : -1) << "\n";
  if (steps.ok()) std::cout << "fmt_operands=" << xls::OperandsExpectedByFormat(*steps) << "\n";
}
}  // namespace

int main() {
  IrPackage();
  IrValue();
  Dslx();
  Numbers();
  return 0;
}
