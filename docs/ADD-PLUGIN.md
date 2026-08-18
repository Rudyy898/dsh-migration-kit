# 在 DSH 新增插件并让另一台电脑也能装上（ADD-PLUGIN）

> 场景：你在当前电脑给 DSH 加了一个新插件，希望**所有电脑**（尤其 Windows）都能装上一模一样的插件。  
> agent 分身操作规范见 `skills/dsh-add-plugin/SKILL.md`；维护总览见 `MAINTENANCE.md`。

---

## 一、先判断插件来源（决定接入方式）

| 类型 | 怎么判断 | 怎么接入 |
|---|---|---|
| **npm 已发布** | `npm view <包名> version` 有输出 | `profile-template/package.json` 写版本范围 |
| **GitHub 仓库** | 有 `github.com/owner/repo` | 写 `github:owner/repo#分支` |
| **本地未发布包** | 只有本地目录 | 拷进 `vendor/` 或 `plugins/`，写 `file:.local/...` |

## 二、检查 GitHub 分支名（高频坑）

```bash
git ls-remote --heads https://github.com/owner/repo.git | grep -E "refs/heads/(main|master)$"
```

> 例：`dsh-client-ui-pet` 的分支是 **master**，写成 `#main` 会直接安装失败。

## 三、修改 profile-template/package.json（两处都要改）

```jsonc
{
  "dependencies": {
    // ① 新增依赖（让 pnpm 能装）
    "my-new-plugin": "github:owner/repo#main"
  },
  "dsh": {
    "profile": {
      "bundles": [
        // ...原有 bundle...
        "my-new-plugin"   // ② 追加到末尾（让 patch 层被应用）
      ]
    }
  }
}
```

**只改 dependencies 不改 bundles** → 插件装了但不会生效，这是最常见的错。

## 四、原生模块需要放行

插件依赖 `node-pty` / `sharp` / `koffi` / `ssh2` 等时，pnpm 11+ 会拦构建脚本（ERR_PNPM_IGNORED_BUILDS）：

```bash
# 看当前机器放行了哪些
cat ~/.dsh/profiles/web/pnpm-workspace.yaml
# 把新包名加进迁移包 profile-template/pnpm-workspace.yaml 的:
#   onlyBuiltDependencies（pnpm 11，优先）
#   allowBuilds（pnpm 10 兼容）
# 预置 onlyBuiltDependencies 可避免新机器首次安装被拦
```

## 五、带素材的插件

- git/npm 依赖的 `files` 字段会过滤文件（pet 的 59MB 素材就装不出来）→ 素材直接拷进迁移包 `assets/`
- 需要 HTTP 服务素材 → 参考 `plugins/dsh-migration-assets`（用 DSH 内置 webServer，跨平台无外部进程）

## 六、验证

```bash
cd /Volumes/Phone SSD/项目/dsh-migration-kit
TESTHOME=$(mktemp -d /tmp/dsh-ap.XXXXXX)
DSH_HOME="$TESTHOME/.dsh" bash scripts/install.sh     # 全新安装必须成功
cd "$TESTHOME/.dsh/profiles/web"
DSH_HOME="$TESTHOME/.dsh" /path/to/runtime/dsh --profile web --dump-config | grep 新插件名  # 层里要有
```

## 七、提交推送

```bash
git add -A
git commit -m "feat: 接入插件 <插件名>"
GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519" git push origin main
```

## 八、新电脑怎么装

什么都不用做——新电脑 `git pull` 最新迁移包后重跑 `install.sh` 即可（或全新机器 clone 后 install）。

---

## 快速检查单

- [ ] 分支名正确（`git ls-remote` 确认）
- [ ] `dependencies` 和 `bundles` 都改了
- [ ] 原生模块加了 allowBuilds
- [ ] 素材已 vendor（如需要）
- [ ] 临时 HOME 全新安装 exit=0
- [ ] dump-config 能看到新插件层
- [ ] commit 无 AI 署名，已推送
