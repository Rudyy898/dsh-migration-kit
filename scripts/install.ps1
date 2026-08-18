# ============================================================================
# dsh-migration-kit install.ps1 — Windows 一键迁移安装脚本
# 把当前机器的 DSH 环境（插件、配置、人格、skills）还原到新 Windows 电脑
# macOS / Linux 见 install.sh
#
# 用法（PowerShell）:
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -FromBackup D:\dsh-full-backup-xxx.tar.gz
#   或（右键 → 用 PowerShell 运行）
#
# 还原内容:
#   - DSH runtime（npx @deepseek-ai/dsh）
#   - web profile + 全部插件（宠物、梁神、全家桶等，见 profile-template/package.json）
#   - 跨平台素材桥（dsh-migration-assets，取代 mac 专用 54123 launchd 进程）
#   - 用户配置模板（settings.yaml / AGENTS.md 大肥鱼人格 / .credentials.yaml 空模板）
#   - 宠物素材（迁移包 assets/ → $env:USERPROFILE\.dsh\data\pet-assets\）
#   - skills（迁移包 skills/ → ~\.agents\skills\）
#   - [-FromBackup] 密钥、会话历史、宠物好感度、codex skills（完全一致迁移）
#
# 注意: 普通安装 API Key 不随仓库分发，需手动填写；-FromBackup 模式从备份恢复。
# ============================================================================
param(
  [string]$FromBackup = ""
)
$ErrorActionPreference = "Stop"

# ---------- 常量 ----------
# RepoDir = 迁移包根目录（本脚本在 scripts\ 下）
$ScriptPath = $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent (Split-Path -Parent $ScriptPath)
$DSHHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE ".dsh" }
$ProfileName = "web"
$ProfileDir = Join-Path $DSHHome "profiles\$ProfileName"
$PetAssetsDir = Join-Path $DSHHome "data\pet-assets"

function Log($msg)  { Write-Host "[install] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Err($msg)  { Write-Host "[error] $msg" -ForegroundColor Red }

# ---------- 依赖检测 ----------
function Ensure-Node {
  if (Get-Command node -ErrorAction SilentlyContinue) {
    $v = & node -v
    Log "Node.js 已安装: $v"
    return
  }
  Warn "未检测到 Node.js。请先安装 Node.js LTS: https://nodejs.org/"
  Write-Host "  下载 Windows Installer (.msi)，一路 Next 即可（勾选 'Add to PATH'）"
  $ans = Read-Host "安装好后输入 y 继续，或 Ctrl-C 退出"
  if ($ans -ne "y" -and $ans -ne "Y") { Err "用户取消"; exit 1 }
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Err "仍检测不到 node，请新开一个 PowerShell 窗口后重试"; exit 1
  }
}

function Ensure-Pnpm {
  if (Get-Command pnpm -ErrorAction SilentlyContinue) {
    Log "pnpm 已安装: $(& pnpm -v)"
    return
  }
  Log "安装 pnpm..."
  corepack enable 2>$null
  if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    npm install -g pnpm
  }
  if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    Err "pnpm 安装失败，请手动执行: npm install -g pnpm"; exit 1
  }
}

# ---------- 步骤 1: 初始化 DSH_HOME ----------
function Ensure-DSHHome {
  if ((Test-Path (Join-Path $DSHHome "settings.yaml")) -and (Test-Path (Join-Path $DSHHome "profiles"))) {
    Log "检测到已有 DSH 环境: $DSHHome（跳过 runtime 初始化）"
    return
  }
  Log "初始化 DSH_HOME: $DSHHome"
  # 首次运行触发目录创建（--dump-config 只组合配置不启动 GUI）
  & npx -y "@deepseek-ai/dsh" --profile $ProfileName --dump-config 2>$null | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $DSHHome "profiles") | Out-Null
}

# ---------- 步骤 2: 搭建 web profile ----------
function Setup-Profile {
  Log "搭建 profile: $ProfileName"
  New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null

  # vendor/plugins: 复制未发布 npm 的本地包到 profile 的 .local/（模板用 file:.local/... 引用）
  $local = Join-Path $ProfileDir ".local"
  if (-not (Test-Path $local)) {
    New-Item -ItemType Directory -Force -Path $local | Out-Null
    Copy-Item -Recurse (Join-Path $RepoDir "vendor") (Join-Path $local "vendor")
    Copy-Item -Recurse (Join-Path $RepoDir "plugins") (Join-Path $local "plugins")
    Log ".local/ 已复制（vendor=dsh-bridge-browser, plugins=素材桥）"
  }

  # profile package.json（git 依赖已去掉本地 link 路径，全平台可装）
  Copy-Item (Join-Path $RepoDir "profile-template\package.json") (Join-Path $ProfileDir "package.json") -Force
  Copy-Item (Join-Path $RepoDir "profile-template\cordis.patch.yml") (Join-Path $ProfileDir "cordis.patch.yml") -Force
  # pnpm workspace（nodeLinker/allowBuilds 与原机一致；缺失会导致原生模块被 pnpm 拦截）
  if (-not (Test-Path (Join-Path $ProfileDir "pnpm-workspace.yaml"))) {
    Copy-Item (Join-Path $RepoDir "profile-template\pnpm-workspace.yaml") (Join-Path $ProfileDir "pnpm-workspace.yaml")
  }
}

# ---------- 步骤 3: pnpm 安装插件 ----------
function Install-Plugins {
  # 用官方 registry：npmmirror 不同步 DSH 的 rc 版本（0.1.0-rc.x），会导致解析失败。
  # allowBuilds 已在 pnpm-workspace.yaml 放行原生模块；pnpm 11 对"新出现的"构建脚本
  # 仍会拦截（ERR_PNPM_IGNORED_BUILDS），此时用 approve-builds --all 非交互放行后重试。
  function Run-PnpmInstall {
    if ((Test-Path (Join-Path $ProfileDir "node_modules")) -and (Test-Path (Join-Path $ProfileDir "pnpm-lock.yaml"))) {
      Push-Location $ProfileDir
      try {
        & pnpm install --frozen-lockfile --registry=https://registry.npmjs.org 2>$null
        if ($LASTEXITCODE -ne 0) { & pnpm install --registry=https://registry.npmjs.org }
      } finally { Pop-Location }
    } else {
      Push-Location $ProfileDir
      try { & pnpm install --registry=https://registry.npmjs.org } finally { Pop-Location }
    }
    return $LASTEXITCODE
  }

  if ((Run-PnpmInstall) -eq 0) {
    Log "插件安装完成"
    return
  }

  Warn "pnpm 拦截了原生模块构建脚本，自动放行（approve-builds --all）..."
  Push-Location $ProfileDir
  try { & pnpm approve-builds --all 2>$null | Out-Null } finally { Pop-Location }
  if ((Run-PnpmInstall) -eq 0) {
    Log "插件安装完成（构建已放行）"
    return
  }

  Err "pnpm install 最终失败。请手动执行:"
  Err "  cd `"$ProfileDir`""
  Err "  pnpm approve-builds --all"
  Err "  pnpm install --registry=https://registry.npmjs.org"
  exit 1
}

# ---------- 步骤 4: 部署宠物素材 ----------
function Deploy-PetAssets {
  $src = Join-Path $RepoDir "assets"
  if (-not (Test-Path (Join-Path $src "pet")) -or -not (Test-Path (Join-Path $src "whale-pet.png"))) {
    Warn "迁移包 assets/ 不完整（缺 pet/ 或 whale-pet.png）"
    return
  }
  New-Item -ItemType Directory -Force -Path $PetAssetsDir | Out-Null
  Copy-Item -Recurse -Force (Join-Path $src "pet") $PetAssetsDir
  Copy-Item -Force (Join-Path $src "whale-pet.png") $PetAssetsDir
  Log "宠物素材已部署: $PetAssetsDir"
}

# ---------- 步骤 5: 部署用户配置模板 ----------
function Deploy-HomeTemplates {
  New-Item -ItemType Directory -Force -Path $DSHHome | Out-Null

  if (-not (Test-Path (Join-Path $DSHHome "settings.yaml"))) {
    Copy-Item (Join-Path $RepoDir "home-template\settings.yaml") (Join-Path $DSHHome "settings.yaml")
    Log "settings.yaml 模板已部署（describe-image.apiKey 需手动填写）"
  } else { Warn "settings.yaml 已存在，跳过" }

  if (-not (Test-Path (Join-Path $DSHHome "AGENTS.md"))) {
    Copy-Item (Join-Path $RepoDir "home-template\AGENTS.md") (Join-Path $DSHHome "AGENTS.md")
    Log "AGENTS.md（大肥鱼人格）已部署"
  } else { Warn "AGENTS.md 已存在，跳过" }

  if (-not (Test-Path (Join-Path $DSHHome ".credentials.yaml"))) {
    Copy-Item (Join-Path $RepoDir "home-template\.credentials.yaml") (Join-Path $DSHHome ".credentials.yaml")
    Log ".credentials.yaml 空模板已部署，请手动填入 API Key"
  }
}

# ---------- 步骤 6: 部署 skills（DSH 在 ~\.agents\skills 发现） ----------
function Deploy-Skills {
  $src = Join-Path $RepoDir "skills"
  if (-not (Test-Path $src)) { return }
  $agentsHome = if ($env:DSH_AGENTS_HOME) { $env:DSH_AGENTS_HOME } else { Join-Path $env:USERPROFILE ".agents" }
  $skillsDir = Join-Path $agentsHome "skills"
  New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null
  Get-ChildItem $src -Directory | ForEach-Object {
    Copy-Item -Recurse -Force $_.FullName (Join-Path $skillsDir $_.Name)
    Log "skill 已部署: $($_.Name)（→ $skillsDir）"
  }
}

# ---------- 步骤 7: 从备份恢复（完全一致迁移） ----------
function Restore-Backup {
  if ([string]::IsNullOrEmpty($FromBackup)) { return }
  if (-not (Test-Path $FromBackup)) { Err "备份文件不存在: $FromBackup"; exit 1 }
  Log "从备份恢复: $FromBackup"
  if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
    Err "未找到 tar.exe（Windows 10+ 自带）。请手动把备份中的文件复制到对应位置。"
    exit 1
  }
  Push-Location $env:USERPROFILE
  try {
    & tar -xzf $FromBackup
    if ($LASTEXITCODE -ne 0) { throw "tar 解包失败" }
  } finally { Pop-Location }
  Log "备份恢复完成（密钥/会话/好感度/skills 已还原）"
}

# ---------- 主流程 ----------
if ($FromBackup) { Write-Host "模式: 完全一致迁移（-FromBackup）" -ForegroundColor Yellow }
Write-Host "dsh-migration-kit 安装器 — DSH_HOME: $DSHHome" -ForegroundColor Cyan
Write-Host ""

Ensure-Node
Ensure-Pnpm
Ensure-DSHHome
Setup-Profile
Install-Plugins
Deploy-PetAssets
Deploy-HomeTemplates
Deploy-Skills
Restore-Backup

Write-Host ""
Log "安装完成! 🎉"
Write-Host ""
if ($FromBackup) {
  Write-Host "已从备份恢复密钥与个人数据，直接启动即可:"
} else {
  Write-Host "下一步:"
  Write-Host "  1. 编辑 $DSHHome\settings.yaml，填写 describe-image.apiKey（硅基流动）"
  Write-Host "  2. 编辑 $DSHHome\.credentials.yaml，填写 DEEPSEEK_API_KEY 等 4 个 Key"
}
Write-Host "  3. 启动: cd $ProfileDir; dsh --profile $ProfileName"
Write-Host "     （或 npx -y @deepseek-ai/dsh --profile $ProfileName）"
Write-Host ""
if (-not $FromBackup) { Warn "提示: 首次启动 web GUI 若提示缺模型 Key，在 GUI 设置里补齐即可。" }
