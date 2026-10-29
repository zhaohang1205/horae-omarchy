#!/usr/bin/env bash
# preflight.sh - Omarchy 系统环境与 Horae 配置只读体检脚本
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC} %s\n" "$*"; }
err()  { printf "  ${RED}✗${NC} %s\n" "$*"; }
info() { printf "  ${BLUE}ℹ${NC} %s\n" "$*"; }

printf "${BOLD}========================================${NC}\n"
printf "${BOLD}   Horae for Omarchy 系统环境体检报告   ${NC}\n"
printf "${BOLD}========================================${NC}\n\n"

# 1. 基础系统与桌面环境
printf "${BOLD}[1/7] 操作系统与 Omarchy 桌面环境${NC}\n"
if [ -f /etc/arch-release ]; then
    ok "检测到 Arch Linux 基础系统"
else
    warn "非标准 Arch Linux 发行版（当前系统: $(uname -s)）"
fi

if command -v omarchy >/dev/null 2>&1; then
    OMARCHY_VER=$(omarchy version 2>/dev/null || echo "已安装")
    ok "Omarchy CLI 就绪 ($OMARCHY_VER)"
else
    err "未检测到 omarchy 命令，可能未在 Omarchy 桌面环境中运行"
fi

if command -v omarchy-shell >/dev/null 2>&1; then
    ok "Omarchy Shell (Quickshell) 就绪"
else
    warn "未检测到 omarchy-shell 命令"
fi

if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    ok "Hyprland 合成器运行中 (实例: $HYPRLAND_INSTANCE_SIGNATURE)"
else
    info "未处于当前活动的 Hyprland 会话中（若在纯终端/SSH下属正常）"
fi

# 2. Horae 二进制状态
printf "\n${BOLD}[2/7] Horae 核心程序${NC}\n"
HORAE_BIN=""
if command -v horae >/dev/null 2>&1; then
    HORAE_BIN=$(command -v horae)
elif [ -x "$HOME/.cargo/bin/horae" ]; then
    HORAE_BIN="$HOME/.cargo/bin/horae"
elif [ -x "$HOME/.local/bin/horae" ]; then
    HORAE_BIN="$HOME/.local/bin/horae"
fi

if [ -n "$HORAE_BIN" ]; then
    VER=$("$HORAE_BIN" --version 2>/dev/null || echo "未知版本")
    ok "Horae 已安装: $HORAE_BIN ($VER)"
else
    err "Horae 尚未安装。支持通过 npm (npm i -g horae-cli) 或 cargo (cargo install horae) 安装"
fi

# 安装工具链检测
if command -v cargo >/dev/null 2>&1; then
    CARGO_VER=$(cargo --version | cut -d' ' -f1,2)
    ok "Rust / Cargo 可用 ($CARGO_VER)"
else
    info "Cargo 未安装（可选用于 `cargo install horae`）"
fi

if command -v npm >/dev/null 2>&1; then
    NPM_VER=$(npm --version)
    ok "Node.js / npm 可用 (v$NPM_VER)"
else
    info "npm 未安装（可选用于 `npm i -g horae-cli`）"
fi

# 3. Omarchy 状态栏插件 (horae_for_omarchy_shell)
printf "\n${BOLD}[3/7] Omarchy 状态栏组件 (Quickshell)${NC}\n"
PLUGIN_ID="io.github.zhaohang1205.horae-tasks"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

if [ -d "$PLUGIN_DIR" ]; then
    ok "插件目录存在: $PLUGIN_DIR"
    if [ -f "$HOME/.config/omarchy/shell.json" ] && grep -q "$PLUGIN_ID" "$HOME/.config/omarchy/shell.json"; then
        ok "插件已在 shell.json 状态栏中配置并启用"
    else
        warn "插件已安装但尚未添加到状态栏布局中 (可用: omarchy bar move $PLUGIN_ID --section center)"
    fi
else
    warn "尚未安装状态栏插件 $PLUGIN_ID"
fi

# 4. Hyprland 快捷键与窗口规则
printf "\n${BOLD}[4/7] Hyprland 快捷键与浮动窗口${NC}\n"
BINDINGS_LUA="$HOME/.config/hypr/bindings.lua"
HYPRLAND_LUA="$HOME/.config/hypr/hyprland.lua"

if [ -f "$BINDINGS_LUA" ]; then
    if grep -q "horae-flash" "$BINDINGS_LUA" || grep -q "horae.*-f" "$BINDINGS_LUA"; then
        ok "已配置快捷键: 闪念录入模式 (Flash capture)"
    else
        warn "未配置快捷键: 闪念录入模式 (推荐绑定至 SUPER + I)"
    fi

    if grep -q "horae-normal" "$BINDINGS_LUA" || grep -q "omarchy-launch-or-focus-tui.*horae" "$BINDINGS_LUA"; then
        ok "已配置快捷键: 应用一般模式 (Normal TUI mode)"
    else
        warn "未配置快捷键: 应用一般模式 (推荐绑定至 SUPER + SHIFT + I)"
    fi

    if grep -q "horae-clip" "$BINDINGS_LUA" || grep -q "capture.*--clip" "$BINDINGS_LUA"; then
        ok "已配置快捷键: 剪贴板录入模式 (Clip capture)"
    else
        warn "未配置快捷键: 剪贴板录入模式 (推荐绑定至 CTRL + 1)"
    fi
else
    warn "未找到 $BINDINGS_LUA"
fi

if [ -f "$HYPRLAND_LUA" ]; then
    if grep -q "horae-flash" "$HYPRLAND_LUA"; then
        ok "已配置闪念录入居中浮动窗口规则 (800x600)"
    else
        info "未检测到 horae-flash 专用浮动窗口规则"
    fi
fi

# 5. Shell 别名 (Alias)
printf "\n${BOLD}[5/7] Shell 别名与快捷指令${NC}\n"
CHECK_FILES=()
[ -f "$HOME/.zshrc" ] && CHECK_FILES+=("$HOME/.zshrc")
[ -f "$HOME/.bashrc" ] && CHECK_FILES+=("$HOME/.bashrc")

FOUND_HC=false
FOUND_HCC=false
for f in "${CHECK_FILES[@]}"; do
    if grep -Eq '^[[:space:]]*alias[[:space:]]+hc=' "$f" 2>/dev/null; then
        FOUND_HC=true
    fi
    if grep -Eq '^[[:space:]]*alias[[:space:]]+hcc=' "$f" 2>/dev/null; then
        FOUND_HCC=true
    fi
done

if [ "$FOUND_HC" = true ]; then
    ok "别名 hc (horae capture) 已配置"
else
    warn "别名 hc 未配置"
fi

if [ "$FOUND_HCC" = true ]; then
    ok "别名 hcc (horae capture --clip) 已配置"
else
    warn "别名 hcc 未配置"
fi

# 6. 辅助工具与通知
printf "\n${BOLD}[6/7] 桌面集成与增强${NC}\n"
if command -v notify-send >/dev/null 2>&1; then
    ok "桌面通知工具 notify-send 就绪"
else
    warn "未找到 notify-send，桌面剪贴板录入提示弹窗将无法显示"
fi

if command -v voxtype >/dev/null 2>&1; then
    ok "Voxtype 离线语音模型已安装（支持语音快速转写录入待办）"
else
    info "Voxtype 未安装（可选：用于语音待办捕获）"
fi

# 7. 语音录入与剪贴板
printf "\n${BOLD}[7/7] 语音录入链路${NC}\n"

if command -v voxtype >/dev/null 2>&1; then
    ok "voxtype 已安装（horae 内置语音与系统级 F9 听写都用它转写）"

    # 终端里 ctrl+v 不是粘贴，而是字面量 v。horae 的输入框靠 bracketed paste
    # 接收文本，粘贴键不对就只会在输入框里看到一个字母 v。
    paste_keys="$(voxtype config get output.paste_keys 2>/dev/null | tr -d '"' | tr -d '\r')"
    if [ "$paste_keys" = "ctrl+shift+v" ] || [ "$paste_keys" = "shift+insert" ]; then
        ok "voxtype 粘贴键: $paste_keys"
    else
        warn "voxtype 粘贴键是 '$paste_keys'，终端里建议改成 ctrl+shift+v"
        warn "  否则语音转写后只会在输入框里看到一个字母 v"
        warn "  修复: voxtype config set output.paste_keys ctrl+shift+v && systemctl --user restart voxtype.service"
    fi

    # voxtype 自带的 evdev 全局热键与合成器绑定同时存在时，一次按键会有
    # 两条触发路径，第二次 start 会被 daemon 以 "daemon is Recording" 挡掉。
    hotkey_enabled="$(voxtype config get hotkey.enabled 2>/dev/null | tr -d '"' | tr -d '\r')"
    hotkey_key="$(voxtype config get hotkey.key 2>/dev/null | tr -d '"' | tr -d '\r')"
    if [ "$hotkey_enabled" = "true" ]; then
        info "voxtype evdev 全局热键已开启（$hotkey_key）—— 若同时用 Hyprland 绑定调用"
        info "  voxtype record，两条触发路径可能互相打架；二者选一即可"
    fi
else
    info "未安装 voxtype（horae 内置语音 Alt+V/F8 需要它，npm i -g horae-cli 不含它）"
fi

# 麦克风静音时录音只会录到静音，ASR 会把它幻听成几句无关的字
if command -v pactl >/dev/null 2>&1; then
    default_source="$(pactl get-default-source 2>/dev/null)"
    if [ -n "$default_source" ]; then
        source_name="${default_source##*.}"
        if pactl get-source-mute "$default_source" 2>/dev/null | grep -qi "yes"; then
            err "默认麦克风 ($source_name) 处于静音状态 —— 语音录入会录到一片静音"
            warn "  解除静音: pactl set-source-mute \"$(pactl get-default-source)\" 0"
            warn "  或点状态栏的麦克风图标 / 按键盘上的麦克风静音键"
        else
            ok "默认麦克风: $source_name（未静音）"
        fi
    fi
elif command -v wpctl >/dev/null 2>&1; then
    if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED; then
        err "默认麦克风处于静音状态 —— 语音录入会录到一片静音"
        warn "  解除静音: wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0"
    else
        ok "默认麦克风未静音"
    fi
fi

if command -v pw-record >/dev/null 2>&1; then
    ok "pw-record 就绪（horae 内置语音 Alt+V/F8 用它录音）"
elif command -v arecord >/dev/null 2>&1; then
    ok "arecord 就绪（horae 内置语音的降级录音工具）"
else
    warn "既无 pw-record 也无 arecord，horae 的 Alt+V/F8 内置语音无法录音"
fi

if command -v wl-copy >/dev/null 2>&1; then
    ok "wl-copy/wl-paste 就绪（Wayland 剪贴板，划选捕获依赖它）"
else
    warn "未找到 wl-copy，划选捕获与剪贴板录入将不可用"
fi

printf "\n${BOLD}========================================${NC}\n"
printf "${BOLD}体检完成。${NC}\n"
