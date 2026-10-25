#!/bin/bash
# ClearDisplay 发布脚本：签名 → 公证 → 装订
#
# 用法：
#   export APPLE_ID="你的 Apple ID"
#   export TEAM_ID="你的 Team ID（10 位）"
#   export APP_PASSWORD="App 专用密码"   # 在 appleid.apple.com 生成，不是登录密码
#   ./release.sh
#
# 前置条件：
#   钥匙串里有 "Developer ID Application: 你的名字 (TEAMID)" 证书
#   检查：security find-identity -v -p codesigning

set -euo pipefail

APP="ClearDisplay.app"
BUNDLE_ID="com.cleardisplay.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="ClearDisplay-${VERSION}.zip"

echo "=== ClearDisplay ${VERSION} 发布流程 ==="
echo

# ---------- 1. 检查签名身份 ----------
echo "[1/5] 检查签名证书"
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)

if [ -z "$IDENTITY" ]; then
  cat <<'MSG'
  ✗ 没找到 "Developer ID Application" 证书。

  获取方法：
    1. 打开 https://developer.apple.com/account/resources/certificates
    2. 点 + 号，选 "Developer ID Application"
    3. 按提示生成 CSR（钥匙串访问 → 证书助理 → 从证书颁发机构请求证书）
    4. 下载 .cer 双击安装到钥匙串

  装好后重跑本脚本。
MSG
  exit 1
fi
echo "  ✓ $IDENTITY"
echo

# ---------- 2. 检查环境变量 ----------
echo "[2/5] 检查公证凭据"
: "${APPLE_ID:?请先 export APPLE_ID}"
: "${TEAM_ID:?请先 export TEAM_ID}"
: "${APP_PASSWORD:?请先 export APP_PASSWORD（App 专用密码，不是登录密码）}"
echo "  ✓ Apple ID: $APPLE_ID"
echo "  ✓ Team ID : $TEAM_ID"
echo

# ---------- 3. 签名 ----------
echo "[3/5] 深度签名（启用强化运行时 + 安全时间戳）"
codesign --force --deep --options runtime --timestamp \
  --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "  ✓ 签名完成"
echo

# ---------- 4. 打包并提交公证 ----------
echo "[4/5] 打包并提交 Apple 公证（通常 2-10 分钟）"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "  包大小：$(du -h "$ZIP" | cut -f1)"

xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD" \
  --wait
echo

# ---------- 5. 装订 ----------
echo "[5/5] 把公证票据装订进应用"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
echo

# ---------- 验收 ----------
echo "=== 验收 ==="
spctl -a -vvv -t install "$APP" 2>&1 | sed 's/^/  /'
echo
echo "全部完成。可以分发的文件："
echo "  $APP"
echo
echo "建议再用另一台电脑（或新用户账户）下载测试一次，"
echo "确认双击打开时没有「无法打开，来自身份不明的开发者」提示。"
