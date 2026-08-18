---
name: dsh-migration-maintain
description: 维护 dsh-migration-kit 迁移包（本仓库 /Volumes/Phone SSD/项目/dsh-migration-kit 或 GitHub Rudyy898/dsh-migration-kit）。当用户要求"更新迁移包"、"让迁移包跟上当前环境"、"把新装的插件加进迁移包"、"重新打包迁移"、"维护 dsh-migration-kit"时使用。内含完整的更新流程、文件清单、验证步骤，保证迁移到另一台电脑后插件与当前环境完全一致。
---

# 维护 dsh-migration-kit（迁移包）

本 skill 指导如何把**当前这台电脑的 DSH 环境变化**同步进 `dsh-migration-kit`，使迁移包始终保持"克隆安装后 = 当前环境"。

## 适用场景

- 用户在这台电脑上装了新插件 / 改了配置 / 更新了宠物素材
- 用户说"把迁移包更新一下"、"重新打包"、"迁移包要跟上现在"
- 用户说"我新装的 XX 插件，怎么让另一台电脑也装上"（详见 ADD-PLUGIN.md 与 add-plugin skill）

## 仓库位置

- 本地: `/Volumes/Phone SSD/项目/dsh-migration-kit`
- 远程: `git@github.com:Rudyy898/dsh-migration-kit.git`（SSH key: `~/.ssh/id_ed25519`，账号 Rudyy898）
- 推送: `GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519" git push origin main`

## 目录结构（维护时要知道每处对应什么）

```
dsh-migration-kit/
├── scripts/
│   ├── install.sh / install.ps1      # 双平台一键安装（新机器还原）
│   └── export.sh / export.ps1        # 从当前机器导出"完全一致"备份（密钥/会话/好感度/skills）
├── profile-template/
│   ├── package.json                  # ★ 插件清单（新增插件主要改这里）
│   ├── pnpm-workspace.yaml           # nodeLinker/allowBuilds（原生模块构建审批）
│   └── cordis.patch.yml              # profile 用户层
├── home-template/
│   ├── settings.yaml                 # 脱敏配置模板（真实 Key 用 YOUR_XXX 占位）
│   ├── AGENTS.md                     # 大肥鱼人格 + 全局规则
│   └── .credentials.yaml             # 空 Key 模板
├── vendor/dsh-bridge-browser/        # 未发布 npm 的桥接子包
├── plugins/dsh-migration-assets/     # 跨平台宠物素材桥插件
├── assets/pet/                       # 宠物序列帧素材（59MB，1006 文件）
├── skills/                           # ★ DSH skills（部署到 ~/.agents/skills/）
│   ├── dsh-migration-maintain/SKILL.md
│   └── dsh-add-plugin/SKILL.md
└── docs/
    ├── MAINTENANCE.md                # 后续更新方式手册
    └── ADD-PLUGIN.md                 # 新增插件同步手册
```

## 更新流程（核心步骤）

### 1. 更新插件清单（最常见）

用户装新插件后，把插件加进 `profile-template/package.json`：

```bash
# 先看当前 profile 实际装了哪些插件（bundle 层）
cd ~/.dsh/profiles/web && /path/to/dsh --profile web --dump-config 2>&1 | grep -E "^# == "

# 对比 profile-template/package.json 的 dependencies，把缺的补上：
#   - npm 已发布包 → 写版本范围如 "^1.2.3"
#   - GitHub 包 → 写 "github:owner/repo#branch"（先查分支名！pet 是 master 不是 main）
#   - 未发布 npm 的本地包 → vendor 进 vendor/ 或 plugins/，写 "file:.local/..."
```

**检查每个 git 依赖的分支名**（最常见的坑）：
```bash
git ls-remote --heads https://github.com/owner/repo.git | grep -E "refs/heads/(main|master)$"
```

**同时更新 bundle 列表**：`dsh.profile.bundles` 数组要包含新插件名（patch 才能被应用）。

### 2. 更新 pnpm-workspace.yaml

新插件若带原生模块（node-pty/sharp/koffi 等），pnpm 11+ 会拦构建脚本。看原机 profile 的 `~/.dsh/profiles/web/pnpm-workspace.yaml` 是否有新增的 `onlyBuiltDependencies`（pnpm 11 写入）或 `allowBuilds`（pnpm 10），同步到模板。**预置 onlyBuiltDependencies 可避免全新机器首次安装被 ERR_PNPM_IGNORED_BUILDS 拦截**。

### 3. 更新宠物素材（宠物动作帧变化时）

```bash
rsync -a --delete ~/.dsh/dsh-client-ui-pet/assets/ assets/
```

### 4. 更新 vendor（bridge-browser 上游更新时）

```bash
rsync -a --delete ~/.dsh/dsh-browser/packages/browser/bridge-browser/ vendor/dsh-bridge-browser/
```

### 5. 更新配置模板

- `settings.yaml`：结构变化时同步（**Key 必须脱敏**为 `YOUR_XXX_API_KEY`）
- `AGENTS.md`：人格/规则变化时同步（**去掉绝对路径**，用 `<你的项目目录>` 占位）

### 6. 更新素材桥（宠物素材服务，跨平台）

`plugins/dsh-migration-assets/lib/index.js` 若素材路径/MIME 变化需同步。素材文件本身放 `assets/`，安装脚本部署到 `$DSH_HOME/data/pet-assets/`。

## 验证（每次更新后必须做）

```bash
# 1. 语法检查
bash -n scripts/install.sh

# 2. 模拟全新机器完整安装（临时 HOME，最关键）
TESTHOME=$(mktemp -d /tmp/dsh-verify.XXXXXX)
DSH_HOME="$TESTHOME/.dsh" bash scripts/install.sh
# 确认: exit=0、插件装完、素材部署、模板就位

# 3. 验证 bundle 层与期望一致
cd "$TESTHOME/.dsh/profiles/web"
DSH_HOME="$TESTHOME/.dsh" /path/to/runtime/dsh --profile web --dump-config 2>&1 | grep -E "^# == "

# 4. 密钥扫描（必须零泄漏）
grep -rE "sk-[a-zA-Z0-9]{20}" --include="*.yaml" --include="*.json" . | grep -v "YOUR_" | head

# 5. 素材桥单测（路由 200/403/404）
```

## 推送

```bash
cd /Volumes/Phone SSD/项目/dsh-migration-kit
git add -A && git commit -m "chore: 更新迁移包（简述本次变更）"
GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519" git push origin main
```

**commit message 规则**：只写功能描述，严禁加任何 AI 署名（Co-Authored-By 等）。

## 常见坑（血泪教训）

1. **pet 分支是 master**，写 `github:Rudyy898/dsh-client-ui-pet#master`（用户 fork，含跨平台 fallback 修复），写 main 会解析失败
2. **必须用官方 registry**：`pnpm install --registry=https://registry.npmjs.org`（npmmirror 不同步 DSH 0.1.0-rc.x）
3. **pnpm-workspace.yaml 不能少**：`nodeLinker: hoisted` + `autoInstallPeers: false` 缺失会导致全新安装解析失败
4. **git 依赖的 files 字段会过滤文件**：pet 的 assets 靠 git 依赖装不出来，必须直接 vendor 进 `assets/`
5. **.gitignore 的 `/.credentials.yaml` 必须带前导斜杠**：否则把 `home-template/.credentials.yaml` 空模板也排除
6. **bash 里 `$VAR` 后紧跟全角括号**（如 `$DSH_HOME（中文`）会被当变量名 → 用 `${VAR}`
7. **PowerShell 5.1 读无 BOM UTF-8 中文会乱码/报语法错** → ps1 必须 UTF-8 BOM + CRLF
8. **PowerShell 5.1 的 `& pnpm`/`& npx` 退出码不可靠**（stderr 触发 NativeCommandError）→ 用 `cmd /c` 包裹
9. **web-ui-all 新版（0.2.0+）内置 better-sidebar** → 不能同时独立装 better-sidebar（双挂载 /sidebar/api duplicate）；模板已统一由全家桶提供
10. **`--from-backup` 恢复必须排除机器特有状态**：`storages/workspace.json`（工作区注册表）和 `storages/session_projcache.json`（项目路径缓存）——跨机器恢复会报 `workspace domain is inconsistent` / `fatal: cannot change to '/Volumes/...'`，新机器应重建。export.sh 已自动排除，install restore 也有兜底删除
11. **Node 版本**：DSH 全家桶 + pnpm 11 要求 Node ≥ 22（推荐 24 LTS）；install 脚本已加版本检查
12. **pet 素材 fallback 写死 54123**（mac 专用 launchd 端口）：非 mac 平台宠物破碎。install 脚本的 patch_pet_fallback（install.sh）/ Patch-PetFallback（install.ps1）会自动把 `window.__DSH_PROXY_BRIDGE__ || "http://127.0.0.1:54123"` 补丁为 `|| ""`（同源，素材桥提供 /media/*）。注意：素材桥注入 __DSH_PROXY_BRIDGE__ 的时机晚于 pet factory 执行，不能依赖注入，必须改 fallback 本身

## 完全一致迁移（含密钥/会话/好感度）

普通 install 只还原"插件+配置模板"（Key 手动填）。若用户要**连密钥、会话历史、宠物好感度、codex skills 一起搬**：

```bash
# 旧机器：导出备份
bash scripts/export.sh          # 生成 dsh-full-backup-<日期>.tar.gz（含 .credentials.yaml、settings.yaml 真实值、sessions/、storages/、pet.json、~/.codex/skills/）

# 新机器：安装后从备份恢复
bash scripts/install.sh --from-backup /path/to/dsh-full-backup-<日期>.tar.gz
```

详见 docs/MAINTENANCE.md 的"完全一致迁移"章节。
