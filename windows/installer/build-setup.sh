#!/bin/bash
# 把已发布的 Windows 程序打成一个安装包 Perch-1.1.0-setup.exe。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$DOTNET_ROOT:$PATH"
if [[ ! -f "$ROOT/windows/dist/win-x64/Perch.exe" ]]; then
  echo "先运行 windows/publish.sh，再打安装包" >&2
  exit 1
fi
python3 - <<PY
import os, zipfile
root = "$ROOT/windows/dist/win-x64"
out = "$ROOT/windows/dist/Perch-1.1.0-win-x64.zip"
if os.path.exists(out):
    os.remove(out)
with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=1) as z:
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root)
            z.write(full, os.path.join("Perch", rel))
print(out)
PY
cd "$ROOT/windows"
dotnet run --project Perch.Setup/Perch.Setup.csproj -c Release -- --extract-test
dotnet publish Perch.Setup/Perch.Setup.csproj -c Release -r win-x64 --self-contained true \
  -p:PublishSingleFile=true -o "$ROOT/windows/dist/setup"
cp "$ROOT/windows/dist/setup/Perch-Setup.exe" "$ROOT/windows/dist/Perch-1.1.0-setup.exe"
echo "$ROOT/windows/dist/Perch-1.1.0-setup.exe"
