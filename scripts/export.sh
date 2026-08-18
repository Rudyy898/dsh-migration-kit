#!/usr/bin/env bash
# ============================================================================
# dsh-migration-kit export.sh — 从当前机器导出"完全一致"备份
# 生成 dsh-full-backup-<日期>.tar.gz，包含密钥、会话、好感度、skills 等
# 所有个人数据，供新机器 install.sh --from-backup 恢复。
#
# 用法:
#   bash export.sh                    # 导出到当前目录
#   bash export.sh -o /path/to/out/   # 导出到指定目录
#   bash export.sh --dry-run          # 只列出将打包的内容
#
# ⚠️ 备份包含真实 API Key 与个人数据，请加密/私有传输，勿公开。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
OUT_DIR="."
DRY_RUN=0

# 解析参数（支持 -o <dir>、--out <dir>、--dry-run）
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -o|--out) OUT_DIR="$2"; shift 2 ;;
    --out=*) OUT_DIR="${1#--out=}"; shift ;;
    *) warn "忽略未知参数: $1"; shift ;;
  esac
done

log()  { printf '\033[32m[export]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[31m[error]\033[0m %s\n' "$*" >&2; }

# 要打包的目录/文件（存在才打包）
ITEMS=(
  "$DSH_HOME/.credentials.yaml"        # 真实 API Key
  "$DSH_HOME/settings.yaml"            # 真实配置（含 describe-image.apiKey）
  "$DSH_HOME/AGENTS.md"                # 人格
  "$DSH_HOME/pet.json"                 # 鲸鱼娘好感度/互动
  "$DSH_HOME/pet.json.bak"             # 好感度备份（如有）
  "$DSH_HOME/sessions"                 # 会话历史
  "$DSH_HOME/storages"                 # 插件状态（whale-girl 账本等）
  "$DSH_HOME/browser-sessions"         # 浏览器会话
  "$DSH_HOME/attachments"              # 附件
  "$HOME/.codex/skills"                # 本机全部 skills（git-upload 等 30 个）
  "$HOME/.agents/skills"               # agents skills（find-skills 等）
)

# 组装 tar 参数（转成相对 $HOME 路径，恢复时解到新机器 $HOME，不受用户名差异影响）
declare -a TAR_ARGS=()
EXISTS=0
for item in "${ITEMS[@]}"; do
  if [ -e "$item" ]; then
    case "$item" in
      "$HOME"/*) TAR_ARGS+=("${item#$HOME/}") ;;
      *)         TAR_ARGS+=("$item") ;;  # HOME 外的不转（如 /Volumes 等）
    esac
    EXISTS=1
  fi
done

if [ "$EXISTS" = "0" ]; then
  warn "没有找到任何可导出的内容（DSH_HOME=${DSH_HOME}）"
  exit 1
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "将打包以下内容:"
  printf '  %s\n' "${TAR_ARGS[@]}"
  exit 0
fi

DATE="$(date +%Y%m%d-%H%M%S)"
# OUTFILE 必须是绝对路径：子 shell 会 cd 到 $HOME 再执行 tar，
# 相对路径会落在 $HOME 下（macOS 主目录通常不可写 → Failed to open）。
if [[ "$OUT_DIR" != /* ]]; then
  OUT_DIR="$(cd "$(pwd)" && pwd)/$OUT_DIR"
  mkdir -p "$OUT_DIR"
fi
# 规范化路径（去掉 ./ 等）
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
OUTFILE="$OUT_DIR/dsh-full-backup-$DATE.tar.gz"

log "打包 $((${#TAR_ARGS[@]})) 项 → $OUTFILE"
# 以 $HOME 为根打包相对路径（恢复时解到新机器 $HOME，不受用户名差异影响）。
# macOS 是 BSD tar：先单次打包，失败则逐个添加（跳过不可读项）。
(
  cd "$HOME" || exit 1
  if ! tar -czf "$OUTFILE" "${TAR_ARGS[@]}" 2>/dev/null; then
    warn "tar 首次打包失败（文件可能被占用/无权限），改为逐个添加..."
    rm -f "$OUTFILE"
    added=0
    for rel in "${TAR_ARGS[@]}"; do
      if [ ! -r "$rel" ] && [ ! -d "$rel" ]; then
        warn "跳过不可读: $rel"
        continue
      fi
      if [ "$added" = "0" ]; then
        tar -czf "$OUTFILE" "$rel" 2>/dev/null && added=1
      else
        tar -czf "$OUTFILE" --append "$rel" 2>/dev/null || true
      fi
    done
    if [ "$added" = "0" ] || [ ! -s "$OUTFILE" ]; then
      err "导出失败：无法创建备份（OUTFILE=$OUTFILE）"
      err "提示: 请用 -o 指定一个可写目录，例如: bash scripts/export.sh -o ~/Desktop"
      exit 1
    fi
  fi
)

SIZE="$(du -sh "$OUTFILE" 2>/dev/null | cut -f1)"
log "备份完成: $OUTFILE ($SIZE)"

echo
echo "下一步（新机器）:"
echo "  bash scripts/install.sh --from-backup $OUTFILE"
warn "备份含敏感信息，请用加密/私有方式传输。"
