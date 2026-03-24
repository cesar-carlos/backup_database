cmake_minimum_required(VERSION 3.14)
project(legacy_profile_scanner LANGUAGES CXX)

add_executable(legacy_profile_scanner
  "main.cpp"
)

apply_standard_settings(legacy_profile_scanner)

set_target_properties(legacy_profile_scanner PROPERTIES
  WIN32_EXECUTABLE FALSE
)
