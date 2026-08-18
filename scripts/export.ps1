# ============================================================================
# dsh-migration-kit export.ps1 — 从当前机器导出"完全一致"备份（Windows 版）
# 生成 dsh-full-backup-<日期>.tar.gz，包含密钥、会话、好感度、skills 等，
# 供新机器 install.ps1 -FromBackup 恢复。
#
# 用法（PowerShell）:
#   powershell -ExecutionPolicy Bypass -File export.ps1
#   powershell -ExecutionPolicy Bypass -File export.ps1 -OutDir D:\backups
#
# ⚠️ 备份包含真实 API Key 与个人数据，请加密/私有传输，勿公开。
# ============================================================================
$ErrorActionPreference = "Stop"

param(
  [string]$OutDir = "."
)

$DSHHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE ".dsh" }

function Log($msg)  { Write-Host "[export] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }

# 要打包的项（存在才打包）
$items = @()
$candidates = @(
  (Join-Path $DSHHome ".credentials.yaml"),
  (Join-Path $DSHHome "settings.yaml"),
  (Join-Path $DSHHome "AGENTS.md"),
  (Join-Path $DSHHome "pet.json"),
  (Join-Path $DSHHome "sessions"),
  (Join-Path $DSHHome "storages"),
  (Join-Path $DSHHome "browser-sessions"),
  (Join-Path $DSHHome "attachments"),
  (Join-Path $env:USERPROFILE ".codex\skills"),
  (Join-Path $env:USERPROFILE ".agents\skills")
)
foreach ($c in $candidates) { if (Test-Path $c) { $items += $c } }

if ($items.Count -eq 0) { Warn "没有找到任何可导出的内容（DSH_HOME=$DSHHome）"; exit 1 }

$date = Get-Date -Format "yyyyMMdd-HHmmss"
$outFile = Join-Path $OutDir "dsh-full-backup-$date.tar.gz"

Log "打包 $($items.Count) 项 → $outFile"
# 用 7z 或 tar 打包（Windows 10+ 自带 tar.exe）
if (Get-Command tar -ErrorAction SilentlyContinue) {
  # 用相对路径打包，恢复到用户目录
  Push-Location $env:USERPROFILE
  try {
    $rel = $items | ForEach-Object { $_.Replace("$env:USERPROFILE\", "") }
    & tar -czf $outFile $rel 2>$null
    if ($LASTEXITCODE -ne 0) { throw "tar 打包失败" }
  } finally { Pop-Location }
} else {
  Err "未找到 tar.exe（Windows 10+ 自带）。请手动复制以下内容到新机器:"
  $items | ForEach-Object { Write-Host "  $_" }
  exit 1
}

Log "备份完成: $outFile"
Write-Host ""
Write-Host "下一步（新机器）:"
Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -FromBackup $outFile"
Warn "备份含敏感信息，请用加密/私有方式传输。"
