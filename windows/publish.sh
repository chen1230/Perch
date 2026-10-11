#!/bin/bash
# 在 Mac 上打出 Windows 11 可直接运行的 Perch.exe。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$DOTNET_ROOT:$PATH"
cd "$ROOT/windows"
dotnet test Perch.Windows.Tests/Perch.Windows.Tests.csproj -c Release
dotnet publish Perch.Windows/Perch.Windows.csproj -c Release -r win-x64 --self-contained true -o "$ROOT/windows/dist/win-x64"
echo "$ROOT/windows/dist/win-x64/Perch.exe"
