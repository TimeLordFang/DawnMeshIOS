#!/usr/bin/env bash
# Prefer an explicit SDK, then project-local tools, then tools on PATH.
dawnmesh_ios_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for dawnmesh_tools in "$dawnmesh_ios_root/.tools" "$dawnmesh_ios_root/../DawnMesh/.tools"; do
  if [[ -z "${FLUTTER_ROOT:-}" && -x "$dawnmesh_tools/flutter-3.47.8/bin/flutter" ]]; then
    export FLUTTER_ROOT="$dawnmesh_tools/flutter-3.47.8"
  fi
  if ! command -v cmake >/dev/null && [[ -x "$dawnmesh_tools/cmake-4.4.4/CMake.app/Contents/bin/cmake" ]]; then
    export PATH="$dawnmesh_tools/cmake-4.4.4/CMake.app/Contents/bin:$PATH"
  fi
done
