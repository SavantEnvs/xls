// Replaces //xls/common:xls_gunit_main, which needs fuzztest and XLS's flag/log initialisation.
#include "gtest/gtest.h"

int main(int argc, char** argv) {
  testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
