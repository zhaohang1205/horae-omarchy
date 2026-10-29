# horae-omarchy

> 专为 [Omarchy](https://omarchy.org/) 桌面环境（Arch Linux + Hyprland + Quickshell）打造的 [Horae](https://github.com/zhaohang1205/horae) GTD 极致无缝集成 AI 技能包（Skill）与自动化配置套件。

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)
[![Platform: Omarchy / Arch Linux](https://img.shields.io/badge/Platform-Omarchy%20%7C%20Arch%20Linux-brightgreen.svg)](https://omarchy.org/)
[![Horae GTD](https://img.shields.io/badge/GTD-Horae-orange.svg)](https://github.com/zhaohang1205/horae)

---

## 🌟 核心特性与丝滑体验

- ⚡ **闪念录入（Flash Capture）浮窗**：按下 `SUPER + I` 瞬间呼出居中紧凑终端小窗（800×600），支持一句话快速语法补全，回车后毫秒级保存入库并秒级退出，零上下文打扰。
- 🖥️ **一般模式（Normal TUI）呼出与聚焦**：按下 `SUPER + SHIFT + I` 平滑聚焦或启动全功能 GTD 交互视图（占屏幕 75% 居中浮窗），随时进行周回顾、看板或任务整理。
- 📋 **划选/剪贴板一键录入（Clip Capture）**：用鼠标划选目标文本后按下 `CTRL + 1`，自动完成复制并录入收件箱，伴随系统桌面气泡通知（`notify-send`）。
- 🍅 **Quattro 状态栏深度联动**：一键激活 [`horae_for_omarchy_shell`](https://github.com/zhaohang1205/horae_for_omarchy_shell) 顶部状态栏组件，内嵌动态番茄钟圆环（`PomoRing`）、到期任务卡片、隐私防窥模式（`󰈈`/`󰈉`）与悬停跑马灯。
- ⌨️ **零冲突 Shell 别名与补全**：自动配置 `hc`（快速捕获）与 `hcc`（剪贴板捕获），并注入 Bash / Zsh / Fish 全套自动补全。
- 🎙️ **语音直达待办**：horae 输入框内按 `Alt+V` / `F8` 即可说话入库（内部 `pw-record` + `voxtype` 转写）；系统级 `F9` 听写转写后也能直接粘进闪念窗。
- 🎨 **主题自动感应**：自动匹配 Omarchy 23 款官方主题（Catppuccin, Tokyo Night, Gruvbox 等），开箱即契合全局视觉。

---

## 📦 目录结构

```text
.
├── SKILL.md                          # 核心 AI Skill 决策树与执行规范
├── README.md                         # 项目介绍与使用指南
├── LICENSE                           # GPL-3.0 许可证
├── scripts/
│   ├── preflight.sh                  # 只读系统体检脚本（OS、工具链、快捷键、状态栏、语音链路）
│   ├── setup-omarchy.sh              # 幂等一键配置脚本（支持分段参数）
│   ├── test-setup.sh                 # 沙箱回归测试（自带伪 Omarchy 环境，CI 用）
│   ├── horae-flash                   # 闪念录入启动器
│   ├── horae-normal                  # 主应用 TUI 启动器
│   └── horae-clip                    # 剪贴板快速录入 + 桌面通知
└── references/
    ├── hyprland-bindings.md          # Hyprland Lua 快捷键规范与改键指南
    ├── bar-widget.md                 # Quickshell 状态栏组件配置参数指南
    └── troubleshooting.md            # 常见故障排查（字体乱码、通知不弹、PATH 等）
```

---

## 🚀 安装与使用

### 方式 1：作为全局通用 Agent Skill 安装使用（推荐）

本仓库完全遵循开放 **Agent Skills 规范**。放入系统全局 Agent 技能目录后，系统内的**所有 AI 助手**（如 Google Antigravity、Claude Code、Codex、Gemini CLI、Orca、Omarchy 内置 Agent 等）均可**自动原生发现并直接调用**，无需针对某个特定 Agent 单独编写适配脚本或配置。

#### 安装方式（二选一）：

**选项 A：直接安装到系统全局 Agent 技能目录（推荐）**
```bash
# 确保全局 skills 目录存在
mkdir -p ~/.agents/skills

# 克隆至全局目录
git clone https://github.com/zhaohang1205/horae-omarchy.git ~/.agents/skills/horae-omarchy

# （可选）若希望兼顾单数路径习惯，可建立 ~/.agent 别名
ln -sfn ~/.agents ~/.agent
```

**选项 B：克隆至开发目录后软链接（方便参与开发与 git 同步）**
```bash
# 克隆到您的项目目录
git clone https://github.com/zhaohang1205/horae-omarchy.git ~/Projects/horae-omarchy

# 全局软链接到 Agent skills 目录
mkdir -p ~/.agents/skills
ln -sfn ~/Projects/horae-omarchy ~/.agents/skills/horae-omarchy

# （可选）别名软链接
ln -sfn ~/.agents ~/.agent
```

> 💡 **提示**：若您使用了 [skills.sh](https://skills.sh/) 技能包管理器，也可直接执行：
> ```bash
> npx skills add zhaohang1205/horae-omarchy -g
> ```

#### 使用方式：

安装完成后，打开您常用的任意 AI 助手（无论 Antigravity、Claude Code、Codex 还是终端 CLI），无需任何额外配置，直接对话即可：

> **常用指令示例**：
> - *“帮我在 Omarchy 系统上配置 Horae GTD 环境”*
> - *“体检一下当前系统的 Horae 和 Omarchy 快捷键状态”*
> - *“帮我配置 Horae 顶部状态栏番茄钟”*
> - *“开启用鼠标划选文字后按 Ctrl+1 自动复制并捕获待办的功能”*

---

### 方式 2：纯脚本手动一键配置

无需 AI 助手，您也可以直接在终端中一键完成全套配置：

1. **运行系统体检**（只读无副作用）：
   ```bash
   ./scripts/preflight.sh
   ```

2. **执行全套配置**：
   ```bash
   # 若尚未安装 horae，可追加 --install-cargo 或 --install-npm
   ./scripts/setup-omarchy.sh --install-cargo --all
   # 或使用 npm
   ./scripts/setup-omarchy.sh --install-npm --all
   ```

---

## ⚙️ 快捷键速查

| 快捷键 | 动作 | 效果 |
|---|---|---|
| `SUPER + I` | 闪念录入 (Flash) | 居中浮窗，输入回车即保存收件箱并秒级退出 |
| `SUPER + SHIFT + I` | 应用交互 (Normal) | 居中 75% 浮窗，呼出或聚焦 Horae TUI |
| `CTRL + 1` | 划选/剪贴板录入 (Clip) | 划选文本自动复制入库 + 桌面通知提示 |
| `Alt+V` / `F8` | 语音录入（horae 内置） | 在 horae 输入框内按住说话，文本直接落进输入框 |

> [!IMPORTANT]
> **上表是首选键位，不是写死的键位。** Omarchy 默认把 `SUPER + I` 和 `SUPER + SHIFT + I` 绑给了输入法切换（`omarchy-input-method cycle` / `cycle back`），所以在原生 Omarchy 上这两个键通常已被占用。
>
> 配置脚本会在写入前扫描全系统按键（运行时绑定表 + `~/.config/hypr` + Omarchy 默认配置），一旦发现冲突就**自动改用下一个空闲候选键并在结尾报告实际使用的键位**，绝不静默覆盖已有绑定。
>
> 你也可以显式指定：
> ```bash
> HORAE_FLASH_KEY="SUPER + ALT + I" \
> HORAE_NORMAL_KEY="SUPER + ALT + SHIFT + I" \
> HORAE_CLIP_KEY="CTRL + 1" \
> ./scripts/setup-omarchy.sh --shortcuts
> ```
> 显式指定的键若已被占用，脚本会报错并跳过该项，而不是强行占用。

> 快捷键定义于 `~/.config/hypr/bindings.lua`，窗口规则定义于 `~/.config/hypr/hyprland.lua`。详情参见 [references/hyprland-bindings.md](references/hyprland-bindings.md)。

---

## 📄 开源许可

本项目基于 [GPL-3.0 License](LICENSE) 开源。
