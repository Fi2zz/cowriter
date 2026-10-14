#!/usr/bin/env bash
# 把 cowriter 打包成单个自包含可执行文件（内嵌 Dart runtime）。
#
# 默认产出 <包根>/dist/cowriter，可用第一个参数覆盖输出路径；脚本不依赖
# 调用时的 cwd：
#   bash tool/build_binary.sh                    # -> <包根>/dist/cowriter
#   bash tool/build_binary.sh /tmp/cowriter      # -> /tmp/cowriter
#
# 产物换机器直接可用（不需要目标机器装 Dart SDK）；但 OS 沙箱后端（launcher）
# 仍在运行时从 pub 缓存定位，清空 pub 缓存后沙箱会 fail-closed，详见 README。
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$package_root/dist/cowriter}"

mkdir -p "$(dirname "$output")"
version="$(grep '^version:' "$package_root/pubspec.yaml" | awk '{print $2}')"
dart compile exe "$package_root/bin/cowriter.dart" \
  -DCOWRITER_VERSION="$version" -o "$output"
chmod +x "$output"

echo "产物：${output}（$(du -h "$output" | awk '{print $1}')）"
