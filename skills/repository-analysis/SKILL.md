---
name: repository-analysis
description: Systematic repository exploration — understanding codebase structure, patterns, and conventions
version: "1.0"
owner: Explorer
prerequisites: repo access
---

# Repository Analysis

## When to use this skill

- First encounter with a repository
- Understanding a new area of a familiar repository
- Before architectural or implementation decisions

## Step-by-step procedure

### 1. Orientation
- Read README, package.json/pyproject.toml, or equivalent
- Identify the project's purpose, language, and framework
- Note the top-level structure

### 2. Entry points
- Find the main entry points (main, index, app)
- Trace the execution flow from entry to key functionality
- Identify the public API surface

### 3. Structure
- Map the directory structure to logical components
- Identify module boundaries and dependencies
- Note naming conventions

### 4. Build & test
- Identify the build system and commands
- Find the test suite and how to run it
- Check for linting, type-checking, CI configuration

### 5. Conventions
- Note coding style (formatting, naming, patterns)
- Identify architectural patterns (MVC, layered, etc.)
- Check for existing documentation of conventions

### 6. Dependencies
- Review external dependencies
- Note version constraints and lock files
- Identify any custom or vendored dependencies

## Common pitfalls

- Exploring too broadly (lost in the codebase)
- Not recording findings (have to re-explore)
- Confusing what exists with what is intended
- Not distinguishing generated from hand-written code
- Ignoring test files (they reveal intent)

## Evidence requirements

- File:line references for key findings
- Confidence levels for uncertain findings
- Questions for follow-up investigation

## Exit criteria

- System map with key files and their roles
- Confidence levels for each finding
- Open questions listed
- Findings recorded in report
