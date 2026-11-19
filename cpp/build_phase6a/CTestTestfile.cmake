# CMake generated Testfile for 
# Source directory: C:/projects/chess_research/chess-engine/cpp
# Build directory: C:/projects/chess_research/chess-engine/cpp/build_phase6a
# 
# This file includes the relevant testing commands required for 
# testing this directory and lists subdirectories to be tested as well.
if(CTEST_CONFIGURATION_TYPE MATCHES "^([Dd][Ee][Bb][Uu][Gg])$")
  add_test("chess_engine_tests" "C:/projects/chess_research/chess-engine/cpp/build_phase6a/Debug/chess_engine_test.exe")
  set_tests_properties("chess_engine_tests" PROPERTIES  _BACKTRACE_TRIPLES "C:/projects/chess_research/chess-engine/cpp/CMakeLists.txt;94;add_test;C:/projects/chess_research/chess-engine/cpp/CMakeLists.txt;0;")
elseif(CTEST_CONFIGURATION_TYPE MATCHES "^([Rr][Ee][Ll][Ee][Aa][Ss][Ee])$")
  add_test("chess_engine_tests" "C:/projects/chess_research/chess-engine/cpp/build_phase6a/Release/chess_engine_test.exe")
  set_tests_properties("chess_engine_tests" PROPERTIES  _BACKTRACE_TRIPLES "C:/projects/chess_research/chess-engine/cpp/CMakeLists.txt;94;add_test;C:/projects/chess_research/chess-engine/cpp/CMakeLists.txt;0;")
elseif(CTEST_CONFIGURATION_TYPE MATCHES "^([Mm][Ii][Nn][Ss][Ii][Zz][Ee][Rr][Ee][Ll])$")
  add_test("chess_engine_tests" "C:/projects/chess_research/chess-engine/cpp/build_phase6a/MinSizeRel/chess_engine_test.exe")
  set_tests_properties("chess_engine_tests" PROPERTIES  _BACKTRACE_TRIPLES "C:/projects/chess_research/chess-engine/cpp/CMakeLists.txt;94;add_test;C:/projects/chess_research/chess-engine/cpp/CMakeLists.txt;0;")
elseif(CTEST_CONFIGURATION_TYPE MATCHES "^([Rr][Ee][Ll][Ww][Ii][Tt][Hh][Dd][Ee][Bb][Ii][Nn][Ff][Oo])$")
  add_test("chess_engine_tests" "C:/projects/chess_research/chess-engine/cpp/build_phase6a/RelWithDebInfo/chess_engine_test.exe")
  set_tests_properties("chess_engine_tests" PROPERTIES  _BACKTRACE_TRIPLES "C:/projects/chess_research/chess-engine/cpp/CMakeLists.txt;94;add_test;C:/projects/chess_research/chess-engine/cpp/CMakeLists.txt;0;")
else()
  add_test("chess_engine_tests" NOT_AVAILABLE)
endif()
