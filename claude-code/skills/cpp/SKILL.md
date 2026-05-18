---
name: cpp
description: C++ coding standards, CMake conventions, and tooling for modern C++ projects.
paths: "*.cpp, *.hpp, *.h, *.cc, *.cxx, CMakeLists.txt"
---

# C++

Language-specific rules for C++ projects. Load this skill when working in
any repository that uses CMake or Make.

## Core Principles

- Prefer modern C++ (C++17 or later)
- Use RAII (Resource Acquisition Is Initialization) for resource management
- Avoid raw pointers; prefer smart pointers (`std::unique_ptr`, `std::shared_ptr`)
- Avoid manual memory management (`new`/`delete`)
- Prefer const-correctness and immutability by default

## Error Handling

- Use exceptions for exceptional conditions (not for control flow)
- Use `std::optional<T>` for values that may not exist
- Use `std::expected<T, E>` (C++23) or similar for error propagation
- Never ignore errors silently
- Provide clear error messages in exceptions

## Performance & Memory

- Avoid unnecessary heap allocations
- Prefer stack allocation and move semantics
- Use `std::string_view` instead of `std::string` when borrowing
- Profile before optimizing; do not guess at bottlenecks
- Use `const` and `constexpr` liberally

## Idiomatic C++

- Follow C++ Core Guidelines
- Use range-based `for` loops instead of index-based loops
- Prefer algorithms from `<algorithm>` over manual loops
- Use `auto` to reduce verbosity, but be explicit when clarity matters
- Implement move constructors and move assignment operators for types that own resources

## Code Quality & Tooling

- Run `clang-format` before declaring done; fix all formatting issues
- Run `clang-tidy` with strict checks; fix all warnings
- Use `ctest` for running tests; ensure all tests pass
- Compile with `-Wall -Wextra -Werror` to catch warnings as errors
- Always run inside the Nix dev shell if a `flake.nix` is present: `nix develop --command <cmd>`

## Safety

- Minimize use of `reinterpret_cast` and `const_cast`
- Prefer `static_cast` when type conversion is necessary
- Avoid C-style casts entirely
- Use bounds-checking containers (`std::array`, `std::vector`) instead of raw arrays
- Enable AddressSanitizer and UndefinedBehaviorSanitizer during development

## Testing

- Use a modern C++ testing framework (e.g., Google Test, Catch2)
- Co-locate test files next to source: `select_model_test.cpp` beside `select_model.cpp`
- Structure tests with test fixtures and parameterized tests
- One logical assertion per test when practical
- Name tests as observable behavior: `ReturnsLocalModelInEditorMode`

## CMake Conventions

- Use modern CMake (3.15+)
- Prefer `target_*` commands over `add_*` commands
- Use `PUBLIC`, `PRIVATE`, `INTERFACE` keywords explicitly
- Organize targets by purpose: libraries, executables, tests
- Use `find_package` for external dependencies

## Code Review

- Flag any raw pointers (except in performance-critical code with clear justification)
- Flag any `new`/`delete` usage (should use smart pointers)
- Check for const-correctness violations
- Verify all resources are properly managed (RAII)
- Ensure all compiler warnings are addressed

## Code Generation

- Always generate compilable code
- Avoid placeholders or `TODO` stubs in production paths
- Prefer clarity over cleverness
- Include all necessary `#include` directives
- Use proper namespacing to avoid collisions
