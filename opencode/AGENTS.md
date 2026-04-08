# General rules

## Build Commands

- Always run build tools in their nix development shell if there is a flake file 
- Always run unit tests
- always run coverage tools, Try to achieve 90% coverage, a bit less is ok, and disable functions or methods that cannot contribute to coverage (as ui functions)

## Workflow

- Always make code changes in a feature branch, created from 'main', unless told otherwise
- Commit messages to follow conventional commits format

# Rust Coding Rules for AI Code Generation

## 🦀 Core Principles

-   Prefer ownership and borrowing over cloning
-   Avoid unwrap() and expect() in production code
-   Use Result\<T, E\> and Option\<T\> for error handling
-   Favor immutability by default
-   Keep functions small and composable

## ⚠️ Error Handling

-   Use the ? operator for propagation
-   Define custom error types when needed
-   Avoid panics in library code

## 🚀 Performance & Memory

-   Avoid unnecessary heap allocations
-   Prefer slices over owned collections
-   Avoid cloning unless necessary

## 🧩 Idiomatic Rust

-   Use match for pattern matching
-   Follow naming conventions
-   Implement common traits (Debug, Clone, Default)

## 🔄 Concurrency & Async

-   Prefer async/await
-   Avoid shared mutable state
-   Use channels over locks when possible

## 🧼 Code Quality & Tooling

-   Use cargo fmt
-   Use cargo clippy
-   Write tests
-   Always run cargo tarpaulin, target 90% coverage, a bit less is ok, take functions out of coverage where you see fit. like ui code or cuda functions. 

## 🔒 Safety

-   Minimize unsafe usage
-   Document unsafe blocks clearly

## Code Generation

-   Always generate compilable code
-   Avoid placeholders
-   Prefer clarity over cleverness

