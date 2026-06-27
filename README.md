# godot-cpp zig template

This repository serves as a quickstart template for GDExtension development with Godot 4.0+ using the Zig build system.

# Prerequisites

To use this locally on your machine, you will need the following:

- [**Zig**](https://ziglang.org/) 0.16.0+
- [**Python**](https://www.python.org/) 3.5+
- [**Git**](https://git-scm.com/) 1.5.3+

## Usage

To use this template, log in to GitHub and click the green **"Use this template"** button at the top of the repository page to create a copy with a clean git history. 

Once created, get started with your new GDExtension by running these steps:

1. Clone your repository
2. Initialize the godot-cpp git submodule with `git submodule update --init`
3. Rename the template extension *(replace `SOME_SUPER_AWESOME_NAME` with your project name)*
   * **Windows (PowerShell):**
     ```powershell
     Get-ChildItem -Recurse -File | ForEach-Object { (Get-Content \(_.FullName) -replace '\bmy_extension\b', 'SOME_SUPER_AWESOME_NAME' \vert{} Set-Content\)_.FullName }
     ```
   * **macOS:**
     ```bash
     find . -type f -exec sed -i '' 's/\bmy_extension\b/SOME_SUPER_AWESOME_NAME/g' {} +
     ```
   * **Linux / WSL / Git Bash:**
     ```bash
     find . -type f -exec sed -i 's/\bmy_extension\b/SOME_SUPER_AWESOME_NAME/g' {} +
     ```
4. Open `build.zig.zon` and delete the `.fingerprint = ...` line
5. Build the project with `zig build`
