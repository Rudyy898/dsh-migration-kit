---
name: dsh-add-plugin
description: 当用户在 DSH（DeepSeek Harness）里新增了一个插件，并要求"另一台电脑也能用上/装上一模一样的插件"、"同步插件到迁移包"时使用。内含把新插件接入 dsh-migration-kit 迁移包的完整步骤，保证跨电脑（Windows/macOS）可安装且行为一致。
---

# 在 DSH 新增插件并同步到迁移包（跨电脑可用）

用户在任意一台电脑上给 DSH 装了新插件后，想让**所有电脑都能用上同一插件**，走这条流程。

## 一、先确定插件的"来源类型"（决定接入方式）

| 类型 | 判断方法 | 接入方式 |
|---|---|---|
| A. npm 已发布 | `npm view <包名> version` 有结果 | 直接写版本范围进 profile-template/package.json |
| B. GitHub 仓库 | 有 `github.com/owner/repo` | 写 `github:owner/repo#分支`（**先查分支名**） |
| C. 未发布 npm 的本地包 | 只有本地目录 | vendor 进迁移包的 `vendor/` 或 `plugins/`，写 `file:.local/...` |
| D. 纯 client 插件（浏览器端） | 无 Node half | 同 A/B/C + 确认 `dsh.client` manifest 正确 |

## 二、检查分支名（B 类必做）

```bash
# 分支名写错是最高频的失败点（pet 插件就是 master 不是 main）
git ls-remote --heads https://github.com/owner/repo.git | grep -E "refs/heads/(main|master)$"
```

## 三、更新 profile-template/package.json

```jsonc
{
  "dependencies": {
    // 新增:
    "新插件名": "版本范围 或 github:owner/repo#分支 或 file:.local/...",
  },
  "dsh": {
    "profile": {
      "bundles": [ /* 把新插件名追加到数组末尾 */ ]
    }
  }
}
```

**两个地方都要改**：`dependencies`（让 pnpm 装得上）+ `bundles`（让 patch 层被应用）。bundle 顺序决定加载顺序，追加到末尾即可。

## 四、处理原生模块（如有）

新插件依赖 node-pty / sharp / koffi / ssh2 等原生模块时，pnpm 11+ 默认拦截构建脚本（ERR_PNPM_IGNORED_BUILDS）：

```bash
# 看原机 profile 的放行清单
cat ~/.dsh/profiles/web/pnpm-workspace.yaml
# 把新增包名加进模板的 onlyBuiltDependencies（pnpm 11）和 allowBuilds（pnpm 10 兼容），值 true
```

## 五、验证（必须在临时 HOME 完整安装）

```bash
cd /Volumes/Phone SSD/项目/dsh-migration-kit
TESTHOME=$(mktemp -d /tmp/dsh-addplug.XXXXXX)
DSH_HOME="$TESTHOME/.dsh" bash scripts/install.sh
# 确认 exit=0，且 dump-config 里有新插件层
cd "$TESTHOME/.dsh/profiles/web"
DSH_HOME="$TESTHOME/.dsh" /path/to/runtime/dsh --profile web --dump-config 2>&1 | grep -E "^# == " | grep 新插件名
```

## 六、提交推送

```bash
git add -A && git commit -m "feat: 接入插件 <插件名> 到迁移包"
GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519" git push origin main
```

**严禁**在 commit message 加 AI 署名。

## 七、如果插件带素材/资源

- 走 npm/git 依赖装不出来 → 直接拷进迁移包 `assets/`（或插件自己的目录），install 脚本负责部署
- 素材桥服务 → 参考 `plugins/dsh-migration-assets`（DSH 内置 webServer 提供静态路由，跨平台无需外部进程）

## 八、用户只问"怎么加"时给的手册

指向 `docs/ADD-PLUGIN.md`（人类可读的完整手册），本 skill 是给 agent 分身的操作规范。

## 常见坑

1. 分支名写错（pet 是 master！）
2. 只改了 dependencies 没改 bundles → 插件装了但没生效
3. 原生模块没加 allowBuilds → pnpm 拦构建
4. 用了 npmmirror 源 → 必须 `--registry=https://registry.npmjs.org`
5. 本地插件没 vendor 就写 file: 路径 → 新机器路径不存在
