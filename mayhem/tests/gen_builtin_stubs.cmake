# Same text as the //xls/dslx/frontend:builtin_stubs_gen genrule: wraps builtin_stubs.x in a raw string.
file(READ "${IN}" body)
file(WRITE "${OUT}" "#pragma once\n#include <string_view>\ninline constexpr std::string_view kBuiltinStubs = R\"stubs(\n${body})stubs\";\n")
