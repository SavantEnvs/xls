# Builds the slice of XLS the Mayhem harnesses need (IR parser + DSLX frontend) without Bazel.
# sources.txt / protos.txt hold the transitive closure of //xls/ir:ir_parser and
# //xls/dslx/frontend:parser, taken from the upstream BUILD files.
cmake_minimum_required(VERSION 3.20)
project(xls_mayhem C CXX)

set(XLS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." CACHE PATH "XLS source root")
set(XLS_DEPS "/opt/toolchains/xlsdeps" CACHE PATH "pre-built third-party prefix")
set(LSAN_OFF_OBJECT "" CACHE FILEPATH "compiled mayhem/lsan_off.cc (build.sh)")
set(FUZZ_MODE ON CACHE BOOL "sanitized fuzz build (harnesses) vs. plain build (KAT probe)")
set(CMAKE_PREFIX_PATH "${XLS_DEPS}")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

find_package(absl CONFIG REQUIRED)
find_package(Protobuf CONFIG REQUIRED)
find_package(re2 CONFIG REQUIRED)
find_package(OpenSSL CONFIG REQUIRED)

# --- protobuf codegen -------------------------------------------------------------------
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/protos.txt" PROTO_LIST)
set(GEN "${CMAKE_BINARY_DIR}/gen")
file(MAKE_DIRECTORY "${GEN}")
set(PB_SRCS)
foreach(p ${PROTO_LIST})
  string(REGEX REPLACE "\\.proto$" "" base "${p}")
  list(APPEND PB_SRCS "${GEN}/${base}.pb.cc")
  add_custom_command(
    OUTPUT "${GEN}/${base}.pb.cc" "${GEN}/${base}.pb.h"
    COMMAND "$<TARGET_FILE:protobuf::protoc>" -I "${XLS_ROOT}" -I "${XLS_DEPS}/include"
            --cpp_out "${GEN}" "${XLS_ROOT}/${p}"
    DEPENDS "${XLS_ROOT}/${p}" protobuf::protoc
    VERBATIM)
endforeach()

# googleapis, imported by module_signature.proto; lives in the deps prefix, not the XLS tree.
list(APPEND PB_SRCS "${GEN}/google/api/field_behavior.pb.cc")
add_custom_command(
  OUTPUT "${GEN}/google/api/field_behavior.pb.cc" "${GEN}/google/api/field_behavior.pb.h"
  COMMAND "$<TARGET_FILE:protobuf::protoc>" -I "${XLS_DEPS}/include" --cpp_out "${GEN}"
          "${XLS_DEPS}/include/google/api/field_behavior.proto"
  DEPENDS "${XLS_DEPS}/include/google/api/field_behavior.proto" protobuf::protoc
  VERBATIM)

# --- the XLS slice ----------------------------------------------------------------------
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/sources.txt" SRC_LIST)
set(XLS_SRCS)
foreach(s ${SRC_LIST})
  list(APPEND XLS_SRCS "${XLS_ROOT}/${s}")
endforeach()

add_library(xls_slice STATIC ${XLS_SRCS} ${PB_SRCS})
target_include_directories(xls_slice PUBLIC "${XLS_ROOT}" "${GEN}" "${CMAKE_CURRENT_SOURCE_DIR}/shim")
target_include_directories(xls_slice SYSTEM PUBLIC "${XLS_DEPS}/include")
target_compile_definitions(xls_slice PUBLIC _DEFAULT_SOURCE=1 NDEBUG_SANITIZER=1)
target_compile_options(xls_slice PRIVATE -w)

file(GLOB ABSL_LIBS "${XLS_DEPS}/lib/libabsl_*.a")
target_link_libraries(xls_slice PUBLIC
  protobuf::libprotobuf re2::re2 OpenSSL::Crypto
  -Wl,--start-group ${ABSL_LIBS} -Wl,--end-group Threads::Threads)
find_package(Threads REQUIRED)

if(FUZZ_MODE)
  # The standalone driver is C: compile it as C so its LLVMFuzzerTestOneInput reference keeps C linkage.
  add_library(standalone_main OBJECT "$ENV{STANDALONE_FUZZ_MAIN}")
  set_source_files_properties("$ENV{STANDALONE_FUZZ_MAIN}" PROPERTIES LANGUAGE C)

  file(GLOB HARNESS_SRCS "${CMAKE_CURRENT_SOURCE_DIR}/harnesses/fuzz_*.cc")
  foreach(h ${HARNESS_SRCS})
    get_filename_component(name "${h}" NAME_WE)
    add_executable(${name} "${h}" "${LSAN_OFF_OBJECT}")
    target_link_libraries(${name} PRIVATE xls_slice $ENV{LIB_FUZZING_ENGINE})
    set_target_properties(${name} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
    add_executable(${name}-standalone "${h}" $<TARGET_OBJECTS:standalone_main> "${LSAN_OFF_OBJECT}")
    target_link_libraries(${name}-standalone PRIVATE xls_slice)
    set_target_properties(${name}-standalone PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
  endforeach()
else()
  add_executable(xls_kat "${CMAKE_CURRENT_SOURCE_DIR}/kat/xls_kat.cc")
  target_link_libraries(xls_kat PRIVATE xls_slice)
  set_target_properties(xls_kat PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

  # Upstream's own gtest suites (tests.txt), built against the same slice with normal flags.
  find_package(GTest CONFIG REQUIRED)
  # builtin_stubs.h is a Bazel genrule upstream (//xls/dslx/frontend:builtin_stubs_gen); same output here.
  set(STUBS_H "${GEN}/xls/dslx/frontend/builtin_stubs.h")
  add_custom_command(
    OUTPUT "${STUBS_H}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${GEN}/xls/dslx/frontend"
    COMMAND ${CMAKE_COMMAND} -DIN=${XLS_ROOT}/xls/dslx/frontend/builtin_stubs.x -DOUT=${STUBS_H}
            -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/gen_builtin_stubs.cmake"
    DEPENDS "${XLS_ROOT}/xls/dslx/frontend/builtin_stubs.x" "${CMAKE_CURRENT_SOURCE_DIR}/tests/gen_builtin_stubs.cmake"
    VERBATIM)
  file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/tests_extra_sources.txt" TEST_EXTRA_LIST)
  set(TEST_EXTRA_SRCS)
  foreach(s ${TEST_EXTRA_LIST})
    list(APPEND TEST_EXTRA_SRCS "${XLS_ROOT}/${s}")
  endforeach()
  add_library(xls_test_support STATIC
    "${XLS_ROOT}/xls/common/status/matchers.cc" "${CMAKE_CURRENT_SOURCE_DIR}/tests/gtest_main.cc" "${CMAKE_CURRENT_SOURCE_DIR}/tests/runfiles_shim.cc"
    ${TEST_EXTRA_SRCS} "${STUBS_H}")
  target_compile_options(xls_test_support PUBLIC -w)
  target_link_libraries(xls_test_support PUBLIC xls_slice GTest::gmock GTest::gtest)
  file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/tests.txt" TEST_LIST)
  set(TEST_TARGETS)
  foreach(t ${TEST_LIST})
    get_filename_component(name "${t}" NAME_WE)
    add_executable(${name} "${XLS_ROOT}/${t}")
    target_link_libraries(${name} PRIVATE xls_test_support)
    set_target_properties(${name} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
    list(APPEND TEST_TARGETS ${name})
  endforeach()
  add_custom_target(xls_upstream_tests DEPENDS ${TEST_TARGETS})
endif()
