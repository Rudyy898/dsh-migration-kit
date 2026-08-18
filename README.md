# 🐋 dsh-migration-kit — DeepSeek Harness 跨平台迁移包

把一台电脑上**已经调好的 DSH 环境**（Web GUI + 全部插件 + 大肥鱼人格 + 配置模板 + skills）一键还原到另一台电脑——**Windows / macOS 都支持**。

> 一句话：`git clone` 下来，跑一条命令，插件、宠物、人格全部就位。普通模式只需手动填 API Key；`--from-backup` 模式连密钥/会话/好感度一起搬，完全一致。

---

## ✨ 迁移后会得到什么（与原机一致）

| 组件 | 说明 |
|---|---|
| DSH runtime | `npx @deepseek-ai/dsh` 官方运行时（各平台自动下载对应二进制） |
| Web profile `web` | 与原机相同的 bundle 层序（见下方清单） |
| 全部插件 | 宠物（鲸鱼娘桌宠）、梁神模式、whale-girl、全家桶、SSH、任务看板等 **14 个 bundle 层** |
| 大肥鱼人格 | `AGENTS.md`（含人格设定、全局规则） |
| 宠物素材 | 59MB 序列帧素材（部署到 `$DSH_HOME/data/pet-assets/`，**无需外部进程**） |
| 配置模板 | `settings.yaml`（脱敏）、`.credentials.yaml`（空 Key 占位） |
| 素材桥插件 | `@dsh-migration/assets` —— 取代 macOS 专用 54123 launchd 进程，**跨平台静态服务** |
| **skills** | 迁移包 `skills/` 部署到 `~/.agents/skills/`（DSH 自动发现），含维护 skill 与新增插件 skill |

### 随包分发的 skills 与文档

| 文件 | 用途 | 谁能用 |
|---|---|---|
| `skills/dsh-migration-maintain/SKILL.md` | 维护迁移包的完整流程（更新插件/素材/配置、验证、推送） | DSH agent 自动发现（下次换会话的分身直接可用） |
| `skills/dsh-add-plugin/SKILL.md` | 给 DSH 加新插件后如何同步到迁移包、保证跨电脑可装 | DSH agent 自动发现 |
| `docs/MAINTENANCE.md` | 后续更新方式手册（人类可读） | 你 |
| `docs/ADD-PLUGIN.md` | 新增插件同步说明（人类可读，含检查单） | 你 |

### 插件清单（bundle 层，与原机逐层一致）
```
@deepseek-ai/dsh-base → @deepseek-ai/dsh-web-app → dshmarket →
@linxin666/dsh-web-ui-all（全家桶）→ @liustack/modlens → dsh-better-sidebar →
dsh-at-file → @deepseek-ai/dsh-bridge-browser → @vectorize-io/hindsight-coding-agents →
dsh-web-restart → @dsh-external/dsh-agent-rp → @dsh-external/dsh-visualize →
@dsh-external/dsh-client-ui-pet（鲸鱼娘桌宠）→ whale-girl → @dsh-migration/assets（素材桥）
```

---

## 🚀 快速开始

> **网络慢 / 克隆卡住？** 本仓库含 59MB 素材，GitHub 直连可能很慢。国内网络建议先配好代理：
> ```bash
> # 以 Clash 等 7899 端口为例（按你的实际代理端口改）
> export https_proxy=http://127.0.0.1:7899 http_proxy=http://127.0.0.1:7899
> # 或只给 GitHub 配（git 会走该代理）
> git config --global http.https://github.com.proxy http://127.0.0.1:7899
> ```
> 安装脚本内部的 pnpm 已固定使用官方 registry（`--registry=https://registry.npmjs.org`），同样会跟随系统代理。

### Windows（PowerShell）

```powershell
# 1. 安装 Node.js LTS（如未装）: https://nodejs.org/
# 2. 下载/克隆本仓库后，在仓库目录打开 PowerShell：

git clone https://github.com/Rudyy898/dsh-migration-kit.git
cd dsh-migration-kit

powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

### macOS / Linux

```bash
# 1. 安装 Node.js ≥ 18（如未装）: https://nodejs.org/
# 2. 克隆并运行：

git clone https://github.com/Rudyy898/dsh-migration-kit.git
cd dsh-migration-kit
bash scripts/install.sh
```

### 安装脚本会自动做

1. 检测平台（win32 → install.ps1 逻辑 / darwin → install.sh）
2. 检查 Node.js / pnpm（缺则提示安装）
3. 初始化 `$DSH_HOME`（默认 `~/.dsh`）
4. 搭建 `web` profile（复制模板 + vendor + 本地插件）
5. `pnpm install` 全部插件（官方 registry，git 依赖自动拉取，**原生模块自动编译**）
6. 部署宠物素材到 `$DSH_HOME/data/pet-assets/`
7. 部署 `settings.yaml` / `AGENTS.md` / `.credentials.yaml` 模板

### 安装后首次启动

```bash
cd ~/.dsh/profiles/web
dsh --profile web
# 或 npx -y @deepseek-ai/dsh --profile web
```

启动后：
- 打开 **设置 → 模型**，填入你的 API Key（DeepSeek / OpenAI / 硅基流动）
- 或直接编辑 `~/.dsh/settings.yaml` 填 `describe-image.apiKey`
- 编辑 `~/.dsh/.credentials.yaml` 填 4 个环境变量 Key

---

## 🗂️ 完全一致迁移（连密钥/会话/好感度一起搬）

普通安装只还原"插件 + 配置模板"，API Key 需手动填。如果你要**跟当前机器完全一样**（密钥、会话历史、宠物好感度、codex skills 全搬）：

### 旧机器：导出备份

```bash
cd dsh-migration-kit
bash scripts/export.sh          # macOS/Linux
# Windows: powershell -ExecutionPolicy Bypass -File scripts\export.ps1
# 生成 dsh-full-backup-<日期>.tar.gz（含密钥、sessions/、storages/、pet.json、~/.codex/skills/）
```

⚠️ 备份含敏感信息，用加密/私有方式传输（不要放公开网盘）。

### 新机器：安装 + 恢复

```bash
bash scripts/install.sh                                # 先正常安装
bash scripts/install.sh --from-backup /path/to/dsh-full-backup-<日期>.tar.gz   # 恢复个人数据
# Windows: powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -FromBackup D:\xxx.tar.gz
```

恢复后直接启动即可，无需再填 Key。详见 `docs/MAINTENANCE.md`。

---

## 🔐 安全说明（重要）

- **本仓库不包含任何真实 API Key**。`settings.yaml` 模板中 `describe-image.apiKey` 为占位符，`.credentials.yaml` 为空值。
- 原机的 `.credentials.yaml`、`settings.yaml` 中的真实密钥、`ext-bridge-token`、会话记录（`sessions/`、`storages/`）**均未打包**。
- 仓库可安全设为 **public**；但建议至少启用 GitHub 的 secret scanning 以便未来误提交时告警。

---

## 🧩 目录结构

```
dsh-migration-kit/
├── scripts/
│   ├── install.sh / install.ps1  # macOS/Linux + Windows 一键安装
│   └── export.sh / export.ps1    # 导出"完全一致"备份（密钥/会话/好感度/skills）
├── profile-template/
│   ├── package.json        # web profile 依赖（git/vendor 依赖，无本地 link 路径）
│   ├── cordis.patch.yml    # profile 用户层（空 patch）
│   └── pnpm-workspace.yaml # nodeLinker/allowBuilds（与原机一致）
├── home-template/
│   ├── settings.yaml       # 脱敏后的配置模板
│   ├── AGENTS.md           # 大肥鱼人格 + 全局规则
│   └── .credentials.yaml   # 空 Key 模板
├── vendor/
│   └── dsh-bridge-browser/ # 未发布 npm 的桥接子包（从官方仓库 vendor）
├── plugins/
│   └── dsh-migration-assets/  # 跨平台宠物素材桥插件
├── assets/
│   ├── pet/                # 宠物序列帧素材（59MB，1006 文件）
│   └── whale-pet.png       # 鲸鱼娘立绘
├── skills/                 # DSH skills（部署到 ~/.agents/skills/，agent 自动发现）
│   ├── dsh-migration-maintain/SKILL.md   # 维护迁移包
│   └── dsh-add-plugin/SKILL.md           # 新增插件同步
├── docs/
│   ├── MAINTENANCE.md      # 后续更新方式手册
│   └── ADD-PLUGIN.md       # 新增插件同步手册
└── README.md
```

---

## 🛠️ 从这台机器重新打包（更新迁移包）

如果这台机器的 DSH 环境更新了（装了新插件、改了配置），重新生成迁移包：

```bash
# 1. 更新 profile 依赖清单（把新插件加进 profile-template/package.json）
# 2. 更新素材（宠物动作帧变化时）
rsync -a --delete ~/.dsh/dsh-client-ui-pet/assets/ assets/
# 3. 更新 vendor（bridge-browser 上游更新时）
rsync -a --delete ~/.dsh/dsh-browser/packages/browser/bridge-browser/ vendor/dsh-bridge-browser/
# 4. 更新配置模板（settings 有结构变化时，注意脱敏）
# 5. 提交推送
git add -A && git commit -m "chore: refresh migration kit" && git push
```

---

## ❓ 常见问题

### Q: pnpm install 报 `No matching version found for @deepseek-ai/...`
用官方 registry（脚本已内置）：`pnpm install --registry=https://registry.npmjs.org`。
npmmirror 不同步 DSH 的 `0.1.0-rc.x` 版本，**不要用 npmmirror 源**。

### Q: 原生模块（node-pty/sharp/koffi）被 pnpm 拦截
`pnpm-workspace.yaml` 已内置 `allowBuilds` 放行清单（与原机一致）。若提示新包，按 pnpm 提示追加。

### Q: 宠物不显示 / 素材 404
检查 `$DSH_HOME/data/pet-assets/` 是否存在 `pet/` 与 `whale-pet.png`。
素材桥插件在 bundle 层末尾（`@dsh-migration/assets`），`dsh --profile web --dump-config` 应能看到该层。

### Q: 迁移后模型不可用
`settings.yaml` 模板是脱敏的，需在新机器填入真实 API Key（DeepSeek / OpenAI / 硅基流动等）。

### Q: 能跟原机保持"完全一样"吗？
配置和插件**逐层一致**（bundle 清单、workspace 配置、人格文件）。差异仅在：
- API Key（安全考虑，手动填）
- 会话历史 / 宠物好感度（个人数据，未迁移）
- 原生模块二进制（各平台自动编译，行为一致）

---

## 📜 License

MIT（素材版权归原插件作者 `xituisuany-max`，大肥鱼人格归本机用户所有）。
