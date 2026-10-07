cmake_minimum_required(VERSION 3.16)
project(aura_pad_viewport C)
# Thin viewport: reads Soft SNAP blocks and blits. No edit logic here.
#   cmake -S c -B out/cmake && cmake --build out/cmake && cmake --install out/cmake
# installs aura-pad to ~/.local/bin (override with -DCMAKE_INSTALL_PREFIX=...)
# and the pad's Soft files to <prefix>/share/aura-pad/soft/pad.
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT AND DEFINED ENV{HOME})
  set(CMAKE_INSTALL_PREFIX "$ENV{HOME}/.local" CACHE PATH "install prefix" FORCE)
endif()

add_executable(pad_view snap.c pad_view.c)
target_compile_options(pad_view PRIVATE -O2 -Wall -Wextra -pedantic)

add_executable(pad_play snap.c play_loop.c pad_play.c)
target_compile_options(pad_play PRIVATE -O2 -Wall -Wextra -pedantic)

add_executable(aura-pad snap.c play_loop.c aura_pad.c)
target_compile_options(aura-pad PRIVATE -O2 -Wall -Wextra -pedantic)
target_compile_definitions(aura-pad PRIVATE
  AURA_PAD_SHARE="${CMAKE_INSTALL_PREFIX}/share/aura-pad")

install(TARGETS aura-pad RUNTIME DESTINATION bin)
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../soft/pad/
        DESTINATION share/aura-pad/soft/pad
        FILES_MATCHING PATTERN "*.aura"
        PATTERN "fixtures" EXCLUDE)
