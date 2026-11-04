// Stand-in for googletest's gtest/gtest_prod.h: XLS headers only use FRIEND_TEST from it.
#ifndef MAYHEM_SHIM_GTEST_GTEST_PROD_H_
#define MAYHEM_SHIM_GTEST_GTEST_PROD_H_
#define FRIEND_TEST(test_case_name, test_name) friend class test_case_name##_##test_name##_Test
#endif
