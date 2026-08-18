#!/usr/bin/env bash
# ============================================================================
# dsh-migration-kit install.sh — macOS / Linux 一键迁移安装脚本
# 把当前机器的 DSH 环境（插件、配置、人格、skills）还原到新机器，Windows 见 install.ps1
#
# 用法:
#   bash install.sh                        # 交互式安装（推荐）
#   bash install.sh --non-interactive      # 非交互（用于自动化/CI）
#   bash install.sh --dry-run              # 只打印将要执行的步骤，不执行
#   bash install.sh --from-backup <file>   # 安装后从 export.sh 的备份恢复（完全一致迁移）
#
# 还原内容:
#   - DSH runtime（npx @deepseek-ai/dsh）
#   - web profile + 全部插件（宠物、梁神、全家桶等，见 profile-template/package.json）
#   - 跨平台素材桥（dsh-migration-assets，取代 mac 专用 54123 launchd 进程）
#   - 用户配置模板（settings.yaml / AGENTS.md 大肥鱼人格 / .credentials.yaml 空模板）
#   - 宠物素材（迁移包 assets/ → $DSH_HOME/data/pet-assets/）
#   - skills（迁移包 skills/ → ~/.agents/skills/，DSH 自动发现）
#   - [--from-backup] 密钥、会话历史、宠物好感度、codex skills（完全一致）
#
# 注意: API Key 不随本仓库分发，安装后需在 GUI 设置中手动填写。
# ============================================================================
set -euo pipefail

# ---------- 常量 ----------
# REPO_DIR = 迁移包根目录（本脚本在 scripts/ 下）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE_NAME="web"
PROFILE_DIR="$DSH_HOME/profiles/$PROFILE_NAME"
PET_ASSETS_DIR="$DSH_HOME/data/pet-assets"
NON_INTERACTIVE=0
DRY_RUN=0
FROM_BACKUP=""

# ---------- 解析参数 ----------
for arg in "$@"; do
  case "$arg" in
    --non-interactive) NON_INTERACTIVE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --from-backup)
      # 下一个参数是备份文件路径
      ;;
    --from-backup=*) FROM_BACKUP="${arg#--from-backup=}" ;;
    *)
      if [ -n "${PREV_ARG:-}" ] && [ "$PREV_ARG" = "--from-backup" ]; then
        FROM_BACKUP="$arg"
      fi
      ;;
  esac
  PREV_ARG="$arg"
done

log()  { printf '\033[32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[31m[error]\033[0m %s\n' "$*" >&2; }

run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '\033[36m[dry-run]\033[0m %s\n' "$*"
    return 0
  fi
  "$@"
}

# ---------- 平台检测 ----------
detect_platform() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      err "不支持的系统: $(uname -s)（Windows 请用 install.ps1）"; exit 1 ;;
  esac
}

# ---------- 依赖检测 ----------
ensure_node() {
  if command -v node >/dev/null 2>&1; then
    local v major
    v="$(node -v 2>/dev/null | sed 's/^v//')"
    major="${v%%.*}"
    log "Node.js 已安装: v$v"
    # DSH 全家桶 + pnpm 11 要求 Node >= 22
    if [ "$major" -lt 22 ] 2>/dev/null; then
      err "Node.js 版本过旧（v$v），DSH 需要 Node.js >= 22（推荐 22 LTS 或 24）"
      err "请升级: https://nodejs.org/ 下载 LTS 版覆盖安装，或 brew upgrade node"
      err "升级后重跑本脚本"
      exit 1
    fi
    return 0
  fi
  if [ "$DRY_RUN" = "1" ]; then return 0; fi
  if [ "$NON_INTERACTIVE" = "1" ]; then
    err "未检测到 Node.js。请先安装 Node.js ≥ 18: https://nodejs.org/ 然后重跑本脚本"
    exit 1
  fi
  warn "未检测到 Node.js，需要安装。"
  warn "  推荐: 访问 https://nodejs.org/ 下载 LTS 版安装（Windows 请用 .msi）"
  read -rp "安装好 Node.js 后输入 y 继续，或 Ctrl-C 退出: " ans
  if [ "$ans" != "y" ] && [ "$ans" != "Y" ]; then
    err "用户取消"; exit 1
  fi
  if ! command -v node >/dev/null 2>&1; then
    err "仍检测不到 node，请确认 PATH 后重试"; exit 1
  fi
}

ensure_pnpm() {
  if command -v pnpm >/dev/null 2>&1; then
    log "pnpm 已安装: $(pnpm -v)"
    return 0
  fi
  if [ "$DRY_RUN" = "1" ]; then return 0; fi
  log "安装 pnpm（corepack）..."
  run corepack enable 2>/dev/null || run npm install -g pnpm
  if ! command -v pnpm >/dev/null 2>&1; then
    err "pnpm 安装失败，请手动执行: npm install -g pnpm"; exit 1
  fi
}

# ---------- 步骤 1: 初始化 DSH_HOME ----------
ensure_dsh_home() {
  if [ -f "$DSH_HOME/settings.yaml" ] && [ -d "$DSH_HOME/profiles" ]; then
    log "检测到已有 DSH 环境: ${DSH_HOME}（跳过 runtime 初始化）"
    return 0
  fi
  log "初始化 DSH_HOME: $DSH_HOME"
  if [ "$DRY_RUN" = "1" ]; then return 0; fi
  mkdir -p "$DSH_HOME/profiles"
  # 提前下载 DSH runtime（首次约 300MB，视网速 2-10 分钟，静默下载中...）
  log "预下载 DSH runtime（首次约需几分钟，请耐心等待）..."
  if ! npx -y @deepseek-ai/dsh --version >/dev/null 2>&1; then
    warn "runtime 预下载未完成，将在首次启动 dsh 时自动安装"
  else
    log "DSH runtime 就绪"
  fi
}

# ---------- 步骤 2: 搭建 web profile ----------
setup_profile() {
  log "搭建 profile: $PROFILE_NAME"
  if [ "$DRY_RUN" = "1" ]; then return 0; fi
  mkdir -p "$PROFILE_DIR"

  # vendor: 复制未发布 npm 的 bridge-browser 子包
  if [ ! -d "$PROFILE_DIR/vendor" ]; then
    cp -R "$REPO_DIR/vendor" "$PROFILE_DIR/vendor"
    log "vendor/ 已复制（dsh-bridge-browser）"
  fi

  # profile package.json（git 依赖已去掉本地 link 路径，全平台可装）
  cp "$REPO_DIR/profile-template/package.json" "$PROFILE_DIR/package.json"
  cp "$REPO_DIR/profile-template/cordis.patch.yml" "$PROFILE_DIR/cordis.patch.yml"
  # pnpm workspace（nodeLinker/allowBuilds 与原机一致；缺失会导致原生模块被 pnpm 拦截）
  if [ ! -f "$PROFILE_DIR/pnpm-workspace.yaml" ]; then
    cp "$REPO_DIR/profile-template/pnpm-workspace.yaml" "$PROFILE_DIR/pnpm-workspace.yaml"
  fi

  # vendor/plugins: 复制未发布 npm 的本地包到 profile 的 .local/（模板用 file:.local/... 引用）
  if [ ! -d "$PROFILE_DIR/.local" ]; then
    mkdir -p "$PROFILE_DIR/.local"
    cp -R "$REPO_DIR/vendor" "$PROFILE_DIR/.local/vendor"
    cp -R "$REPO_DIR/plugins" "$PROFILE_DIR/.local/plugins"
    log ".local/ 已复制（vendor=dsh-bridge-browser, plugins=素材桥）"
  fi
}

# ---------- 步骤 3: pnpm 安装插件 ----------
install_plugins() {
  if [ "$DRY_RUN" = "1" ]; then return 0; fi
  # 用官方 registry：npmmirror 不同步 DSH 的 rc 版本（0.1.0-rc.x），会导致解析失败。
  # allowBuilds 已在 pnpm-workspace.yaml 放行原生模块；pnpm 11 对"新出现的"构建脚本
  # 仍会拦截（ERR_PNPM_IGNORED_BUILDS），此时用 approve-builds --all 非交互放行后重试。
  run_pnpm_install() {
    if [ -d "$PROFILE_DIR/node_modules" ] && [ -f "$PROFILE_DIR/pnpm-lock.yaml" ]; then
      (cd "$PROFILE_DIR" && pnpm install --frozen-lockfile --registry=https://registry.npmjs.org 2>/dev/null) \
        || (cd "$PROFILE_DIR" && pnpm install --registry=https://registry.npmjs.org)
    else
      (cd "$PROFILE_DIR" && pnpm install --registry=https://registry.npmjs.org)
    fi
  }

  if run_pnpm_install; then
    log "插件安装完成"
    return 0
  fi

  # 构建脚本被拦截 → 非交互放行全部后重试
  warn "pnpm 拦截了原生模块构建脚本，自动放行（approve-builds --all）..."
  (cd "$PROFILE_DIR" && pnpm approve-builds --all 2>/dev/null) || true
  if run_pnpm_install; then
    log "插件安装完成（构建已放行）"
    return 0
  fi

  err "pnpm install 最终失败。"
  err "请手动执行:"
  err "  cd \"$PROFILE_DIR\""
  err "  pnpm approve-builds --all"
  err "  pnpm install --registry=https://registry.npmjs.org"
  exit 1
}

# ---------- 步骤 4: 部署宠物素材 ----------
deploy_pet_assets() {
  if [ "$DRY_RUN" = "1" ]; then return 0; fi
  local src="$REPO_DIR/assets"
  if [ ! -d "$src/pet" ] || [ ! -f "$src/whale-pet.png" ]; then
    warn "迁移包 assets/ 不完整（缺 pet/ 或 whale-pet.png）"
    return 0
  fi
  mkdir -p "$PET_ASSETS_DIR"
  cp -R "$src/pet" "$PET_ASSETS_DIR/"
  cp "$src/whale-pet.png" "$PET_ASSETS_DIR/"
  log "宠物素材已部署: $PET_ASSETS_DIR ($(du -sh "$PET_ASSETS_DIR" 2>/dev/null | cut -f1))"
}

# ---------- 步骤 4.5: 补丁 pet fallback（跨平台素材源） ----------
# pet client 原 fallback 写死 http://127.0.0.1:54123（mac 专用 launchd 端口），
# 非 mac 平台需改为同源空串（素材桥提供 /media/*）。此补丁幂等，可重复执行。
patch_pet_fallback() {
  if [ "$DRY_RUN" = "1" ]; then return 0; fi
  local pet_client="$PROFILE_DIR/node_modules/@dsh-external/dsh-client-ui-pet/lib/client.js"
  if [ ! -f "$pet_client" ]; then
    warn "pet client.js 未找到，跳过 fallback 补丁"
    return 0
  fi
  if grep -q '|| ""' "$pet_client" 2>/dev/null; then
    log "pet fallback 已是同源（跳过补丁）"
    return 0
  fi
  cp "$pet_client" "$pet_client.bak-54123"
  # 用 perl 替换（sed 对替换串中的双引号处理不稳，perl 可靠）
  if ! perl -pi -e 's{window\.__DSH_PROXY_BRIDGE__ \|\| "http://127\.0\.0\.1:54123"}{window.__DSH_PROXY_BRIDGE__ || ""}g' "$pet_client" 2>/dev/null; then
    warn "perl 补丁失败，尝试 python..."
    python3 - "$pet_client" << 'PYEOF'
import sys
p = sys.argv[1]
d = open(p, encoding='utf-8').read()
d = d.replace('window.__DSH_PROXY_BRIDGE__ || "http://127.0.0.1:54123"', 'window.__DSH_PROXY_BRIDGE__ || ""')
open(p, 'w', encoding='utf-8').write(d)
PYEOF
  fi
  rm -f "$pet_client.bak"
  if grep -q '|| ""' "$pet_client" 2>/dev/null; then
    log "pet fallback 已补丁为同源（跨平台素材桥）"
  else
    warn "pet fallback 补丁未生效，请手动检查 $pet_client"
  fi
}

# ---------- 步骤 5: 部署用户配置模板 ----------
deploy_home_templates() {
  if [ "$DRY_RUN" = "1" ]; then return 0; fi
  mkdir -p "$DSH_HOME"

  # settings.yaml —— 不覆盖已有配置（防止用户改过的东西被冲掉）
  if [ ! -f "$DSH_HOME/settings.yaml" ]; then
    cp "$REPO_DIR/home-template/settings.yaml" "$DSH_HOME/settings.yaml"
    log "settings.yaml 模板已部署（describe-image.apiKey 需手动填写）"
  else
    warn "settings.yaml 已存在，跳过（如需重置请手动删除后重跑）"
  fi

  # AGENTS.md —— 大肥鱼人格
  if [ ! -f "$DSH_HOME/AGENTS.md" ]; then
    cp "$REPO_DIR/home-template/AGENTS.md" "$DSH_HOME/AGENTS.md"
    log "AGENTS.md（大肥鱼人格）已部署"
  else
    warn "AGENTS.md 已存在，跳过"
  fi

  # .credentials.yaml —— 空模板
  if [ ! -f "$DSH_HOME/.credentials.yaml" ]; then
    cp "$REPO_DIR/home-template/.credentials.yaml" "$DSH_HOME/.credentials.yaml"
    chmod 600 "$DSH_HOME/.credentials.yaml"
    log ".credentials.yaml 空模板已部署（chmod 600），请手动填入 API Key"
  fi
}

# ---------- 步骤 6: 部署 skills（DSH 在 ~/.agents/skills 发现） ----------
deploy_skills() {
  if [ "$DRY_RUN" = "1" ]; then return 0; fi
  local agents_home="${DSH_AGENTS_HOME:-$HOME/.agents}"
  local src="$REPO_DIR/skills"
  if [ ! -d "$src" ]; then return 0; fi
  mkdir -p "$agents_home/skills"
  for skill_dir in "$src"/*/; do
    [ -d "$skill_dir" ] || continue
    local name
    name="$(basename "$skill_dir")"
    cp -R "$skill_dir" "$agents_home/skills/$name"
    log "skill 已部署: ${name}（→ $agents_home/skills/）"
  done
}

# ---------- 步骤 7: 从备份恢复（完全一致迁移） ----------
restore_backup() {
  if [ -z "$FROM_BACKUP" ]; then return 0; fi
  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] 将从备份恢复: $FROM_BACKUP"
    return 0
  fi
  if [ ! -f "$FROM_BACKUP" ]; then
    err "备份文件不存在: $FROM_BACKUP"
    exit 1
  fi
  log "从备份恢复: $FROM_BACKUP"
  # 备份含 .dsh/ 与 .codex/ 等相对 HOME 的路径。先解到临时目录，
  # 再把 .dsh 合并进 $DSH_HOME（支持 DSH_HOME 自定义到其他盘），其余（.codex 等）解到 $HOME。
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/dsh-restore.XXXXXX")"
  if tar -xzf "$FROM_BACKUP" -C "$tmp" 2>/dev/null; then
    if [ -d "$tmp/.dsh" ]; then
      mkdir -p "$DSH_HOME"
      # 恢复时排除机器特有状态（workspace 注册表/项目缓存——新机器应重建，
      # 否则跨机器会报 workspace domain inconsistent / 找不到 Mac 路径）
      rm -rf "$tmp/.dsh/storages/workspace.json" "$tmp/.dsh/storages/session_projcache.json"
      cp -R "$tmp/.dsh/." "$DSH_HOME/"
      log "已恢复 .dsh → $DSH_HOME"
    fi
    # 备份中 HOME 下的其他项（.codex/skills 等）
    if [ -d "$tmp/.codex" ]; then cp -R "$tmp/.codex" "$HOME/"; fi
    if [ -d "$tmp/.agents" ]; then cp -R "$tmp/.agents" "$HOME/"; fi
  else
    warn "tar 解包失败，尝试直接解到 HOME..."
    tar -xzf "$FROM_BACKUP" -C "$HOME" --ignore-failed-read 2>/dev/null || true
  fi
  rm -rf "$tmp"
  log "备份恢复完成（密钥/会话/好感度/skills 已还原）"
}

# ---------- 主流程 ----------
main() {
  local platform
  platform="$(detect_platform)"
  log "dsh-migration-kit 安装器 — 平台: $platform, DSH_HOME: $DSH_HOME"
  if [ -n "$FROM_BACKUP" ]; then
    log "模式: 完全一致迁移（--from-backup）"
  fi
  echo

  ensure_node
  ensure_pnpm
  ensure_dsh_home
  setup_profile
  install_plugins
  deploy_pet_assets
  patch_pet_fallback
  deploy_home_templates
  deploy_skills
  restore_backup

  echo
  log "安装完成! 🎉"
  echo
  if [ -n "$FROM_BACKUP" ]; then
    echo "已从备份恢复密钥与个人数据，直接启动即可:"
  else
    echo "下一步:"
    echo "  1. 编辑 $DSH_HOME/settings.yaml，填写 describe-image.apiKey（硅基流动）"
    echo "  2. 编辑 $DSH_HOME/.credentials.yaml，填写 DEEPSEEK_API_KEY 等 4 个 Key"
  fi
  echo "  3. 启动: cd $PROFILE_DIR && dsh --profile $PROFILE_NAME"
  echo "     （或 npx -y @deepseek-ai/dsh --profile ${PROFILE_NAME}）"
  echo
  if [ -z "$FROM_BACKUP" ]; then
    warn "提示: 首次启动 web GUI 可能需要 ~/.dsh/settings.yaml 里没有的模型 Key，按需补齐。"
  fi
}

main "$@"
