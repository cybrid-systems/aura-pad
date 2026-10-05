cmake_minimum_required(VERSION 3.16)
project(aura_pad_viewport C)
# Thin viewport: reads Soft SNAP blocks and blits. No edit logic here.
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

add_executable(pad_view snap.c pad_view.c)
target_compile_options(pad_view PRIVATE -O2 -Wall -Wextra -pedantic)

add_executable(pad_play snap.c pad_play.c)
target_compile_options(pad_play PRIVATE -O2 -Wall -Wextra -pedantic)
