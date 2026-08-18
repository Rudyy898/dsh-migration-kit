# dsh-migration-kit 维护手册（MAINTENANCE）

本手册说明如何**更新迁移包**，让它始终跟当前电脑的 DSH 环境保持一致。
给 agent 分身的操作规范见 `skills/dsh-migration-maintain/SKILL.md`（已随包分发，新电脑安装后即被 DSH 识别）。

---

## 1. 迁移包是什么

`dsh-migration-kit` 是 DSH 环境的"快照 + 还原器"：

- **快照**：`profile-template/`（插件清单）、`home-template/`（配置模板）、`assets/`（宠物素材）、`vendor/`、`plugins/`、`skills/`、`docs/`
- **还原器**：`scripts/install.sh`（macOS/Linux）+ `scripts/install.ps1`（Windows）——在新机器上一键重建

**核心原则**：`git clone → install → 填 Key` 之后，插件、宠物、人格、skills 全部与原机器一致。

---

## 2. 日常更新场景

### 2.1 装了新插件 → 见 `ADD-PLUGIN.md`（或 agent 用 `dsh-add-plugin` skill）

### 2.2 改了配置（settings.yaml / AGENTS.md）

```bash
# settings.yaml：结构变化时同步到 home-template/，真实 Key 换成 YOUR_XXX_API_KEY
# AGENTS.md：人格/规则变化时同步，绝对路径换成 <你的项目目录>
```

### 2.3 宠物素材更新（动作帧变化）

```bash
rsync -a --delete ~/.dsh/dsh-client-ui-pet/assets/ assets/
```

### 2.4 DSH 上游升级（runtime 版本变化）

DSH 本体是 `npx @deepseek-ai/dsh` 动态安装，不用打包。但若插件依赖的版本范围不再兼容新 runtime，需在 `profile-template/package.json` 调整版本。

---

## 3. 完全一致迁移（连密钥/会话/好感度一起搬）

默认 install 只还原"插件 + 配置模板"，API Key 需手动填（安全考虑）。  
若要求**跟当前机器完全一样**（密钥、会话历史、宠物好感度、codex skills 全搬）：

### 旧机器导出备份

```bash
cd dsh-migration-kit
bash scripts/export.sh
# 生成 dsh-full-backup-<日期>.tar.gz，包含:
#   - .credentials.yaml（真实 Key）
#   - settings.yaml（真实值，含 describe-image.apiKey）
#   - sessions/ 会话历史
#   - storages/（含 whale-girl 好感度等插件状态）
#   - pet.json（鲸鱼娘好感度/互动）
#   - ~/.codex/skills/（本机所有 skills）
#   - browser-sessions/ 等个人数据目录
```

⚠️ **备份包含敏感信息**：用加密通道传输（网盘私有目录/加密压缩/U盘），不要放公开位置。

### 新机器恢复

```bash
bash scripts/install.sh                     # 先正常安装（插件+模板）
bash scripts/install.sh --from-backup /path/to/dsh-full-backup-<日期>.tar.gz
# 恢复密钥、会话、好感度、skills，然后直接启动即可
```

`--from-backup` 会覆盖同名文件（settings.yaml、.credentials.yaml 等），**确保备份来自你信任的机器**。

---

## 4. 验证清单（每次更新后）

| 项 | 命令 | 期望 |
|---|---|---|
| 脚本语法 | `bash -n scripts/install.sh` | 无输出 |
| 全新安装 | 临时 HOME 跑 install.sh | exit=0 |
| 插件层 | dump-config | 包含期望 bundle |
| 密钥泄漏 | `grep -rE "sk-[a-zA-Z0-9]{20}" .` | 仅 YOUR_ 占位 |
| 素材桥 | 单测 200/403/404 | 全部通过 |

---

## 5. 推送

```bash
cd /Volumes/Phone SSD/项目/dsh-migration-kit
git add -A
git commit -m "chore: 更新迁移包（简述变更）"
GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519" git push origin main
```

仓库: `git@github.com:Rudyy898/dsh-migration-kit.git`（SSH key `~/.ssh/id_ed25519`，账号 Rudyy898）

**commit message 只写功能描述，严禁 AI 署名。**

---

## 6. 常见问题

- **pnpm install 报 No matching version** → 用官方 registry（脚本已内置），别用 npmmirror
- **原生模块被拦** → `pnpm-workspace.yaml` 的 allowBuilds 加包名
- **pet 素材 404** → 确认 `$DSH_HOME/data/pet-assets/` 存在 pet/ 与 whale-pet.png
- **git 依赖解析失败** → 分支名写错（pet 是 master 不是 main）
