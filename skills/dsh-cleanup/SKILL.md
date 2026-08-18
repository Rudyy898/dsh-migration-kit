---
name: dsh-cleanup
description: 清理 Windows 电脑 C 盘空间的技能。当用户说"清理 C 盘"、"清理空间"、"磁盘满了"、"清理缓存"、"C 盘满了怎么办"、"跑清理脚本"、"家里电脑清理"时使用。通过 SSH 执行清理脚本或指导用户运行，释放 C 盘空间。
---

# dsh-cleanup — Windows C 盘清理

当用户需要清理 Windows 电脑的 C 盘空间时使用本技能。

## 目标机器

- **家里 Windows**（alias: `home`，frp 穿透）—— 见 `home-ssh-remote` skill 的连接方式
- 其它 Windows 机器 —— 用对应 SSH alias 或指导用户本地运行

## 清理脚本位置

- **迁移包仓库**: `dsh-migration-kit/scripts/cleanup.ps1`（推送到 GitHub，所有机器可同步）
- **家里 Windows 部署位置**: `D:\dsh-migration-kit\scripts\cleanup.ps1`
- **任何机器**: clone 迁移包后 `scripts/cleanup.ps1`

## 使用方式

### 方式 A：SSH 远程执行（家里机器）

```powershell
# 通过 SSH 把清理脚本复制到家里（如果还没有）
# 本地迁移包 → ssh_upload → D:\dsh-migration-kit\scripts\cleanup.ps1

# SSH 执行清理
ssh_exec alias=home command="powershell -ExecutionPolicy Bypass -File D:\dsh-migration-kit\scripts\cleanup.ps1 -Quiet"
```

### 方式 B：用户本地运行

告诉用户：
```powershell
# 下载/同步迁移包后
powershell -ExecutionPolicy Bypass -File cleanup.ps1
# 清理游戏残留加 -CleanGames
powershell -ExecutionPolicy Bypass -File cleanup.ps1 -CleanGames
# 先预览（不实际删）
powershell -ExecutionPolicy Bypass -File cleanup.ps1 -DryRun
```

## 清理内容（脚本自动做）

| 类别 | 内容 |
|---|---|
| 临时文件 | 用户 Temp、系统 Temp |
| 缓存 | npm/pip/pnpm 缓存、通用 .cache |
| 浏览器缓存 | Edge、Chrome 缓存 |
| 崩溃转储 | CrashDumps |
| Windows 更新缓存 | SoftwareDistribution\Download |
| 腾讯缓存 | 微信 XPlugin/update/log、QQ Skins/Temp |
| 游戏残留（-CleanGames） | Epic/Steam/暴雪/EA/Origin/Riot/Sony 等目录 |

## 手动清理补充（脚本之外的）

如果脚本后空间还不够，可以手动做：

1. **WindowsApps 商店游戏卸载**（SSH 权限不足，需用户手动）：
   ```
   设置 → 应用 → 已安装的应用 → 搜索游戏名 → 卸载
   ```
   或管理员 PowerShell：
   ```powershell
   Get-AppxPackage | Where-Object { $_.Name -match '游戏名' } | Remove-AppxPackage
   ```

2. **微信/QQ 存储位置改 D 盘**（应用内设置）：
   - 微信：设置 → 文件管理 → 更改 → D:\Downloads\WeChat
   - QQ：设置 → 文件管理 → 更改 → D:\Downloads\QQ

3. **下载目录迁移**（脚本外，已配置的）：
   - 系统下载文件夹 → D:\Downloads（已改注册表）
   - Edge/Chrome 下载 → D:\Downloads\Browser（已改 Preferences）

## 安全边界（绝不动）

- **CUDA / NVIDIA GPU Computing Toolkit**（AI 开发用）
- **NVIDIA 驱动**（删了显卡坏）
- **Node.js / pnpm / Python / Git / VS Code**（开发环境）
- **DSH 相关**（D:\dsh 一切）
- **WindowsApps 系统组件**（Microsoft.* 前缀）
- **微信/QQ 聊天记录**（xwechat 里的核心数据，只清缓存）
- **Codex/Claude 的 auth.json / sessions**（登录凭据和会话）

## 注意事项

1. **先 DryRun 预览**再实际清理，避免误删
2. **清理后 C 盘 ≥ 20% 空闲**即健康（128GB 盘 ≥ 25GB）
3. 商店游戏卸载 SSH 权限不够，需要用户手动（0x5 拒绝访问）
4. Windows 更新缓存清理需停止 wuauserv 服务（脚本已处理）
5. 清理是幂等的（可重复跑），Temp/缓存会重新生成属正常
