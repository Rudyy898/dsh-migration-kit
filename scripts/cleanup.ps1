# ============================================================================
# dsh-migration-kit 清理脚本 (cleanup.ps1) — Windows 一键清理 C 盘
# 用法: powershell -ExecutionPolicy Bypass -File cleanup.ps1
#       powershell -ExecutionPolicy Bypass -File cleanup.ps1 -DryRun  # 只预览不清
#       powershell -ExecutionPolicy Bypass -File cleanup.ps1 -CleanGames  # 含游戏残留清理
# ============================================================================
param(
  [switch]$DryRun,        # 只显示将清理什么，不实际删除
  [switch]$CleanGames,    # 额外清理游戏平台残留（Epic/Steam/暴雪等目录）
  [switch]$Quiet          # 安静模式（不暂停）
)

$ErrorActionPreference = "Continue"
$startFree = [math]::Round((Get-PSDrive C).Free/1GB, 2)

function Log($msg) { Write-Host "[cleanup] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }

function Remove-Safe($path, $label) {
  if (Test-Path $path) {
    if ($DryRun) { Log "将清理: $label ($path)" }
    else { Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue; Log "已清理: $label" }
  }
}

Write-Host "==== dsh-migration-kit C 盘清理 ====" -ForegroundColor Cyan
if ($DryRun) { Write-Host "（DryRun 模式：只显示将清理的内容）" -ForegroundColor Yellow }
Write-Host "清理前 C 盘空闲: $startFree GB`n"

# ---- 1. 临时文件 ----
Log "--- 临时文件 ---"
Remove-Safe "C:\Users\king\AppData\Local\Temp\*" "用户 Temp"
Remove-Safe "C:\Windows\Temp\*" "系统 Temp"

# ---- 2. 缓存 ----
Log "--- 包管理器缓存 ---"
if (-not $DryRun) {
  npm cache clean --force 2>$null | Out-Null
  pip cache purge 2>$null | Out-Null
  Log "npm/pip 缓存已清"
}
Remove-Safe "C:\Users\king\AppData\Local\pnpm-cache" "pnpm 缓存"
Remove-Safe "C:\Users\king\AppData\Local\npm-cache" "npm 缓存"
Remove-Safe "C:\Users\king\.cache" "通用缓存"

# ---- 3. 浏览器缓存 ----
Log "--- 浏览器缓存 ---"
Remove-Safe "C:\Users\king\AppData\Local\Microsoft\Edge\User Data\Default\Cache\*" "Edge 缓存"
Remove-Safe "C:\Users\king\AppData\Local\Google\Chrome\User Data\Default\Cache\*" "Chrome 缓存"

# ---- 4. 崩溃转储/日志 ----
Log "--- 崩溃转储 ---"
Remove-Safe "C:\Users\king\AppData\Local\CrashDumps\*" "CrashDumps"
Remove-Safe "C:\ProgramData\*.tmp" "ProgramData 临时目录"

# ---- 5. Windows 更新缓存 ----
Log "--- Windows 更新缓存 ---"
if (-not $DryRun) {
  Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
  Remove-Safe "C:\Windows\SoftwareDistribution\Download\*" "Windows 更新下载缓存"
  Start-Service wuauserv -ErrorAction SilentlyContinue
}

# ---- 6. 腾讯/聊天缓存（可选） ----
Log "--- 腾讯缓存 ---"
Remove-Safe "C:\Users\king\AppData\Roaming\Tencent\Logs" "Tencent Logs"
Remove-Safe "C:\Users\king\AppData\Roaming\Tencent\xwechat\XPlugin" "微信 XPlugin 缓存"
Remove-Safe "C:\Users\king\AppData\Roaming\Tencent\xwechat\update" "微信更新缓存"
Remove-Safe "C:\Users\king\AppData\Roaming\Tencent\xwechat\log" "微信日志"
Remove-Safe "C:\Users\king\AppData\Roaming\Tencent\QQ\Skins" "QQ 皮肤缓存"
Remove-Safe "C:\Users\king\AppData\Roaming\Tencent\QQ\Temp" "QQ 临时"

# ---- 7. 游戏残留（-CleanGames 才清理） ----
if ($CleanGames) {
  Log "--- 游戏平台残留 ---"
  foreach ($g in @(
    "C:\ProgramData\Battle.net", "C:\ProgramData\Blizzard Entertainment",
    "C:\ProgramData\EA Desktop", "C:\ProgramData\Electronic Arts", "C:\ProgramData\Origin",
    "C:\ProgramData\Epic", "C:\ProgramData\GOG.com", "C:\ProgramData\Nexon",
    "C:\ProgramData\Riot Games", "C:\ProgramData\Hogwarts Legacy",
    "C:\ProgramData\Mount and Blade II Bannerlord", "C:\ProgramData\Frontier Developments",
    "C:\ProgramData\PopCap Games", "C:\ProgramData\Sony Interactive Entertainment Inc",
    "C:\ProgramData\AntiCheatExpert", "C:\Users\king\curseforge",
    "C:\Users\king\Zomboid", "C:\Users\king\Saved Games"
  )) {
    Remove-Safe $g ([System.IO.Path]::GetFileName($g))
  }
}

# ---- 结果 ----
$endFree = [math]::Round((Get-PSDrive C).Free/1GB, 2)
$freed = [math]::Round($endFree - $startFree, 2)
Write-Host ""
Log "清理完成!"
Write-Host "C 盘空闲: $startFree GB → $endFree GB (释放 $freed GB)" -ForegroundColor Cyan

if (-not $Quiet -and -not $DryRun) {
  Write-Host ""
  Read-Host "按回车关闭..."
}
