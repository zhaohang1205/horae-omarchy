---
name: horae-omarchy
description: 在 Omarchy（Arch Linux + Hyprland + Quickshell）系统上安装、配置与使用 Horae GTD 任务管理器，为用户提供丝滑的原生桌面集成体验。包含通过 npm (horae-cli) 或 cargo (horae) 安装、配置无冲突的 shell 别名（hc、hcc）、设置 Hyprland 快捷键（闪念录入模式、一般交互模式、系统剪贴板快速录入模式）、启用 Quickshell 状态栏番茄钟组件、自动补全、桌面图标与主题适配。当用户在 Omarchy 系统中需要安装 horae、配置快捷键、在状态栏显示番茄钟/待办、设置别名或遇到 Omarchy 集成问题时使用此技能。
---

# Horae for Omarchy 桌面极致集成指南

本技能旨在为 **Omarchy**（基于 Arch Linux + Hyprland + Quickshell 的美观、智能、无缝桌面环境）用户提供从安装到全套桌面集成的最丝滑方案。

> [!NOTE]
> **全局 Agent 技能规范**：本 Skill 遵循开放 Agent Skills 规范，设计置于系统全局技能目录 `~/.agents/skills/horae-omarchy`（或 `~/.agent/skills/horae-omarchy`）。安装在该目录后，系统内任意支持 Agent 规范的 AI 工具（Antigravity、Claude Code、Codex 等）均可原生自动发现并载入，无需为特定 Agent 编写专属脚本。`<skill-dir>` 路径通常对应 `~/.agents/skills/horae-omarchy`。

通过本方案，用户无需频繁打开终端：
- 按下快捷键即可弹出居中浮动小窗，秒级记录闪念待办（**闪念录入模式**）；
- 按下快捷键随时平滑聚焦或唤起完整的 GTD 终端界面（**一般交互模式**）；
- 鼠标划选内容后按快捷键，自动完成复制并录入收件箱，伴随弹窗提醒（**划选与剪贴板录入模式**）；
- 顶部状态栏常驻番茄钟倒计时环与到期任务卡片，带隐私防窥与悬停跑马灯；
- Shell 中敲击 `hc`（捕获）或 `hcc`（剪贴板捕获）即可极速操作。

---

## 一、标准实施步骤

执行安装与配置时，遵循 **“先体检 -> 确认选项 -> 幂等配置 -> 验证冒烟”** 的流程：

### 1. 运行系统环境体检
首先运行只读体检脚本，探测当前系统的安装工具、配置状态与已存在设置：
```bash
bash <skill-dir>/scripts/preflight.sh
```
体检报告将清晰展示：
- 核心二进制 `horae` 是否已安装，Cargo / npm 工具链就绪情况；
- Omarchy 状态栏插件（`io.github.zhaohang1205.horae-tasks`）安装与启用情况；
- Hyprland 快捷键与窗口规则是否已就绪；
- Shell 别名（`hc`, `hcc`）与补全状态。

### 2. 安装 Horae 核心程序
> [!IMPORTANT]
> AUR 平台目前尚未正式发布 horae。官方推荐通过 **Cargo** 或 **npm** 进行全局安装：

- **通过 Cargo 安装**（推荐 Rust 用户，原生编译）：
  ```bash
  cargo install horae
  ```
- **通过 npm 安装**（推荐 Node.js 用户，开箱即用）：
  ```bash
  npm install -g horae-cli
  ```
- 安装完成后验证版本：
  ```bash
  horae --version
  ```

### 3. 配置 Shell 别名（无冲突时自动注入）
在用户当前的 Shell 配置文件（`~/.zshrc` / `~/.bashrc` / `~/.config/fish/config.fish`）中添加两个高频核心别名：
- `alias hc='horae capture'`：快速捕获一条任务（如 `hc "买牛奶 @home ~今天 !high"`）；
- `alias hcc='horae capture --clip'`：瞬间将系统剪贴板文本保存入库。

脚本已具备自动冲突检测：如果用户已有同名 alias，将保留原有配置，绝不强行覆盖。

### 4. 设置 Hyprland 原生快捷键与浮动窗口
为了保障极致的心流体验，在 `~/.config/hypr/bindings.lua` 与 `~/.config/hypr/hyprland.lua` 中配置三大快捷入口：

> [!IMPORTANT]
> **写入前必须先做按键冲突检测。** `setup-omarchy.sh` 会扫描运行时绑定表与所有 `*.lua` 配置（自动剥离注释），冲突时按候选链自动降级，并在结束时打印实际生效的键位；也可用 `HORAE_FLASH_KEY` / `HORAE_NORMAL_KEY` / `HORAE_CLIP_KEY` 显式指定。

1. **闪念录入模式（Flash Capture）**：
   - 首选快捷键：`F8`（被占用时降级为 `SUPER + ALT + I` → `SUPER + ALT + C`）
   - 触发动作：`{ tui = "horae-flash", focus = true }`
   - 窗口规则：`org.omarchy.horae-flash` 居中浮动（800×600），打完按回车瞬间保存并退出。
2. **应用一般模式（Normal TUI）**：
   - 首选快捷键：`SUPER + SHIFT + I`（被占用时降级为 `SUPER + ALT + SHIFT + I` → `SUPER + ALT + N`）
   - 触发动作：`{ tui = "horae-normal", focus = true }`
   - 窗口规则：`org.omarchy.horae` 居中浮动（占屏幕 75% 面积），提供完整的 GTD 交互、周回顾与看板。
3. **划选与剪贴板录入模式（Clip Capture）**：
   - 首选快捷键：`CTRL + 1`（被占用时降级为 `SUPER + ALT + C` → `SUPER + ALT + SHIFT + C`）
   - 触发动作：执行 `~/.local/bin/horae-clip`，优先自动复制鼠标划选文本（或系统剪贴板内容）并写入收件箱，通过 `notify-send` 弹出桌面气泡确认。

> [!NOTE]
> **语音录入不需要额外脚本。** horae 输入框内按 `Alt+V` / `F8` 即可语音录入（内部走 `pw-record` + `voxtype transcribe`）。系统级的 `F9` 听写转写后也能直接粘进 horae，但依赖两个前提：voxtype 的 `output.paste_keys` 为 `ctrl+shift+v`（终端里 `ctrl+v` 只是字面量 `v`）、默认麦克风未静音。`setup-omarchy.sh --voxtype` 会修正前者，`preflight.sh` 会同时检查这两项。

配置写入后自动调用 `hyprctl reload` 使其立即生效。详细规则与自定义改键参考 [references/hyprland-bindings.md](references/hyprland-bindings.md)。

### 5. 启用 Omarchy 状态栏番茄钟与任务卡片组件
组件 ID：`io.github.zhaohang1205.horae-tasks`
- 若系统尚未安装，可执行：
  ```bash
  omarchy plugin add https://github.com/zhaohang1205/horae_for_omarchy_shell.git --enable
  ```
- 推荐布局参数（居中排布，420px 最大宽度，15秒自动收起）：
  ```bash
  omarchy bar move io.github.zhaohang1205.horae-tasks --section center
  omarchy-shell shell setBarWidget "io.github.zhaohang1205.horae-tasks" "maxWidth" "420" "{}"
  omarchy-shell shell setBarWidget "io.github.zhaohang1205.horae-tasks" "autoDismiss" "15" "{}"
  omarchy-shell shell rescanPlugins
  ```
详细特性与交互参考 [references/bar-widget.md](references/bar-widget.md)。

### 6. 生成自动补全与桌面菜单图标
- 生成 shell completions 至标准 XDG 路径：
  - Bash: `~/.local/share/bash-completion/completions/horae`
  - Zsh: `~/.local/share/zsh/site-functions/_horae`
  - Fish: `~/.config/fish/completions/horae.fish`
- 创建 `~/.local/share/applications/horae.desktop`，使 Horae 能够直接在 Omarchy 应用菜单中检索启动。

---

## 二、一键自动化配置工具

本技能内置了完整幂等的配置脚本，可直接执行：

```bash
# 全套一键丝滑配置（快捷脚本、Hyprland 快捷键、别名、状态栏、补全、桌面图标）
bash <skill-dir>/scripts/setup-omarchy.sh --all

# 若尚未安装核心程序，可追加安装选项：
bash <skill-dir>/scripts/setup-omarchy.sh --install-cargo --all
# 或
bash <skill-dir>/scripts/setup-omarchy.sh --install-npm --all
```

---

## 三、操作与验证指引

配置完成后，按以下步骤进行冒烟验证：
1. **测试闪念录入与语音**：按键盘 `F8` 打开紧凑的 Horae 终端录入框，再按 `F8` 启动/结束语音录入；输入 `体验 Horae 闪念录入 @test` 并回车，窗口应自动关闭；
2. **测试划选/剪贴板录入**：用鼠标划选一段文字（无需手动按 Ctrl+C），按键盘 `CTRL + 1`，观察右上方是否弹出 `Horae 剪贴板捕获` 桌面通知，并检查收件箱；
3. **测试应用交互**：按键盘 `SUPER + SHIFT + I`，观察是否呼出/聚焦到 Horae 主界面，检查刚才捕获的任务是否已在收件箱；
4. **测试状态栏**：查看顶部状态栏居中位置，是否有 Horae 番茄钟环和待办提示，鼠标悬停测试隐私模式与卡片展开。

---

## 四、安全红线

1. **配置备份原则**：在修改 `~/.config/hypr/bindings.lua` 前，必须自动创建时间戳备份文件（`bindings.lua.bak.<timestamp>`）；
2. **键位不覆盖原则**：若用户的按键（如 `F8`）已分配给其他工作流，不得强行静默覆盖，应先提示用户或改用备用键（如 `SUPER + ALT + C`）；
3. **数据隐私原则**：`~/.config/horae` 目录权限必须设置为 `0700`，数据库与配置文件权限设置为 `0600`；
4. **无损卸载原则**：卸载插件或配置时，绝不删除用户已积累的 `horae.db` 任务与时间线数据。

---

## 五、参考文件索引

| 文件 | 描述与使用场景 |
|---|---|
| [references/hyprland-bindings.md](references/hyprland-bindings.md) | Hyprland Lua 快捷键绑定范式、冲突排查与窗口尺寸配置 |
| [references/bar-widget.md](references/bar-widget.md) | Omarchy Quickshell 状态栏组件完整功能与参数调整 |
| [references/troubleshooting.md](references/troubleshooting.md) | 路径缺失、通知不显示、字体乱码等常见问题解答 |
