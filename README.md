# godot-cpp zig template

This repository serves as a quickstart template for GDExtension development with Godot 4.0+ using the Zig build system.

# Prerequisites

To use this locally on your machine, you will need the following:

- [**Zig**](https://ziglang.org/) 0.16.0+
- [**Python**](https://www.python.org/) 3.5+
- [**Git**](https://git-scm.com/) 1.5.3+

## Usage
Click the green **"Use this template"** button on GitHub to create a copy with a clean git history.

> [!NOTE]
> Bindings will be generated automatically on first build and your compiled library will be output to `project/bin/<platform>/`

1. Clone your repository: `git clone --recurse-submodules <your-repo-url>`
2. Open `build.zig.zon`:
   - Change `.name = .my_extension` to your extension's name e.g. `.name = .cool_extension`
   - Delete the `.fingerprint = ...` line
3. Rename `project/bin/my_extension.gdextension` to match your extension name and update path references inside it from `my_extension` to your chosen name
5. Run `zig build`

## Build Profile
To reduce compile times and binary size, you can modify the `build_profile.json` in the project root to strip unused Godot classes from the bindings.
