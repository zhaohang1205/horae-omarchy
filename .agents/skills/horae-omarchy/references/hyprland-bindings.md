# Hyprland 快捷键与窗口规则指南 (Omarchy)

Omarchy 桌面环境使用 Lua 作为 Hyprland 的配置语言。用户级快捷键位于 `~/.config/hypr/bindings.lua`，窗口行为规则位于 `~/.config/hypr/hyprland.lua`。

## 1. 核心快捷键架构

Horae 与 Omarchy 系统结合时，推荐配置三组核心交互方式：

| 快捷键 | 动作 | 原理与调用目标 | 体验特色 |
|---|---|---|---|
| `F8` | 闪念录入模式 (Flash) | `{ tui = "horae-flash", focus = true }` | 居中浮动小窗，快速输入标题/标签/周期，回车后瞬间保存入库并秒级关闭；打开后再按 `F8` 可开始/结束语音录入 |
| `SUPER + SHIFT + I` | 应用一般模式 (Normal) | `{ tui = "horae-normal", focus = true }` | 呼出或聚焦（已打开时自动切到前台）完整的 GTD 交互视图 |
| `CTRL + 1` | 剪贴板快速捕获 (Clip) | `~/.local/bin/horae-clip` | 自动复制鼠标划选内容（或剪贴板文本）至收件箱，并弹出 `notify-send` 确认提示 |
| `Alt + V` / `F8`（窗口内） | horae 内置语音录入 | horae 输入框获得焦点时 | 闪念窗用 `F8` 打开后，再按 `F8` 开始/结束语音录入；Horae 自带转写，无需额外脚本 |

> 上表为首选键位。闪念录入默认使用 `F8`；若与用户自定义绑定冲突，脚本会依次尝试 `SUPER + ALT + I`、`SUPER + ALT + C`。脚本只在 Horae 闪念窗口聚焦时把 F8 转发给应用，因此在其他应用中 F8 只负责打开浮窗；打开后再按 F8 可启动或结束语音录入。一般模式的 `SUPER + SHIFT + I` 在原生 Omarchy 上默认被输入法切换占用，实际落地键位以脚本运行结束时的报告为准。

## 2. bindings.lua 配置示例

在 `~/.config/hypr/bindings.lua` 中追加：

```lua
-- ============================================================================
-- Horae GTD 快捷键
-- ============================================================================

-- 闪念录入模式：按下立即弹出小型录入框
-- 聚焦 Horae 闪念窗口时，把 F8 继续传入输入框作为语音键
hl.bind("F8", hl.dsp.pass({ window = "class:^org\\.omarchy\\.horae-flash$" }))
o.bind("F8", "Horae (Flash)", { tui = "horae-flash", focus = true })

-- 一般模式：按下平滑呼出或聚焦完整交互视图
o.bind("SUPER + SHIFT + I", "Horae (Normal)", { tui = "horae-normal", focus = true })

-- 剪贴板录入：将系统剪切板内容瞬间录入为任务
o.bind("CTRL + 1", "Horae clip capture", os.getenv("HOME") .. "/.local/bin/horae-clip")
```

### 快捷键冲突排查

在添加快捷键前，可运行以下命令检查是否有按键冲突：
```bash
omarchy menu keybindings --print | grep "F8"
```

> [!IMPORTANT]
> `omarchy menu keybindings --print` 需要运行中的 Hyprland 会话。`setup-omarchy.sh` 不依赖它：会同时扫描 `~/.config/hypr/*.lua` 与 `$OMARCHY_PATH/default/hypr/**/*.lua`（剥离 `--` 注释、排除 `*.bak*`），把 `"SUPER + SHIFT + I"` 与 `"SHIFT SUPER + I"` 这类不同写法归一化后比对。因此即使在没有图形会话的终端里执行，也能发现 Omarchy 默认绑定。
>
> 扫描覆盖 `o.bind` / `o.rebind` / `o.bind_toggle` / `o.bind_hold` / `hl.bind` 五种写法 —— 只认前两种会漏掉 `SUPER + SHIFT + SPACE`（开关顶栏）、`F9`（按住说话）这类绑定。
>
> 若索引为空（既读不到运行时绑定表，也读不到任何 lua 配置），脚本**不会**当作"没有冲突"继续绑定，而是跳过键位配置只写窗口规则 —— 检测不到不等于不存在。

若发现冲突，脚本会按候选链自动降级，无需手工处理：

| 动作 | 候选链 |
|---|---|
| Flash | `F8` → `SUPER + ALT + I` → `SUPER + ALT + C` |
| Normal | `SUPER + SHIFT + I` → `SUPER + ALT + SHIFT + I` → `SUPER + ALT + N` |
| Clip | `CTRL + 1` → `SUPER + ALT + C` → `SUPER + ALT + SHIFT + C` |

想固定某个键位，用环境变量覆盖（冲突时脚本会报错并跳过，不会强行占用）：
```bash
HORAE_FLASH_KEY="F8" ./scripts/setup-omarchy.sh --shortcuts
```

## 3. hyprland.lua 浮动与尺寸规则

为了确保弹窗不会以平铺（Tile）方式破坏当前桌面的窗口排布，在 `~/.config/hypr/hyprland.lua` 中配置窗口规则：

```lua
-- Horae Flash Capture: 紧凑居中浮动小窗 (800x600)
o.window("^org\\.omarchy\\.horae-flash$", {
	float = true,
	center = true,
	size = { 800, 600 },
})

-- Horae TUI: 居中浮动视窗 (占屏幕 75% 宽高，兼顾沉浸感与空间感)
o.window("^(org\\.omarchy\\.horae|org\\.omarchy\\.horae-normal)$", {
	float = true,
	center = true,
	size = { "(monitor_w*0.75)", "(monitor_h*0.75)" },
})
```

## 4. 辅助启动脚本说明

`~/.local/bin/` 目录下的辅助脚本封装了 `HORAE_BIN` 探测与终端隔离启动：
- `horae-flash`：`exec "$HORAE_BIN" -f "$@"`
- `horae-normal`：`exec "$HORAE_BIN" -n "$@"`
- `horae-clip`：优先将鼠标划选的文本（Wayland Primary Selection）复制至主剪贴板，随后执行 `horae capture --clip "$@"` 并通过 `notify-send` 桌面通知显示结果。

## 5. 语音录入的两条路径

horae 的输入框支持 **bracketed paste**，所以语音转写出来的文本可以直接粘进去。

**路径一（系统级，无需进 horae）**

```
F9（按住说话）→ voxtype 转写 → 写入剪贴板并向焦点窗口发粘贴键 → horae 闪念窗收到 → 回车入库
```

这条路有三个必须满足的条件，缺一个就只会在输入框里看到一个字母 `v`、或者录到一片静音：

| 条件 | 不满足时的现象 | 修复 |
|---|---|---|
| voxtype 的 `output.paste_keys` 是 `ctrl+shift+v` | 终端里 `ctrl+v` 不是粘贴，而是字面量 `v` | `voxtype config set output.paste_keys ctrl+shift+v` 后 `systemctl --user restart voxtype.service` |
| 默认麦克风未静音 | 录到静音，ASR 幻听成几句无关的字 | `pactl set-source-mute "$(pactl get-default-source)" 0`，或点状态栏麦克风图标 |
| `horae` 用原生二进制启动 | npm 包装脚本依赖 node，在精简的终端环境里可能 exec 失败 | 用 `~/.local/lib/node_modules/horae-cli/bin/horae` 或 `cargo install` 的版本 |

`setup-omarchy.sh --voxtype` 会把粘贴键改对并重启 voxtype daemon。

**路径二（horae 内置）**

在 horae 的输入框里按 `Alt+V` 或 `F8` 开始录音，再按一次结束。闪念浮窗的全局触发键默认也改为 `F8`：第一次按下打开浮窗；只有闪念窗口聚焦时 Hyprland 才把 F8 继续转发到 Horae，所以第二次按下开始录音，第三次结束。horae 自己调 `pw-record` 录音、调 `voxtype transcribe` 转写，文本直接进输入框。这条路不经过剪贴板，因此不受粘贴键设置影响，但仍受麦克风静音影响。

### voxtype 的两条触发路径只能留一条

voxtype 自带 **evdev 全局热键**（`hotkey.enabled`，默认 `SCROLLLOCK`、`push_to_talk`）；而本方案又用 Hyprland 绑定调用 `voxtype record start/stop`。两者同时开启时，一次按键会产生两条触发路径，第二个 `start` 会被 daemon 挡掉：

```
INFO Ignoring start request: daemon is Recording (0.0s) (stop or cancel it first)
```

voxtype 的 schema 对此有明确说明：*"Turn this off when your compositor calls `voxtype record` instead."*

```bash
# 用合成器绑定时关掉内置热键
voxtype config set hotkey.enabled false
systemctl --user restart voxtype.service
```

反过来，如果只想用 voxtype 自己的热键，就别在 `bindings.lua` 里再绑 `voxtype record`。

> 另注：`o.bind("F9", …)` 与 Omarchy 默认的 `o.bind_hold("F9", …)` 也会同时生效，造成同一按键绑定两次。Omarchy 默认那对自带 held 标志和 `ignore_mods`，直接用默认的、删掉自己加的那两行即可。

## 6. 快捷键冲突与 voxtype 的关系

`SUPER + ALT + V` 与 horae 内置语音的 `Alt+V` 不冲突：前者是组合键，后者只在 horae 的输入框获得焦点时才有意义。
