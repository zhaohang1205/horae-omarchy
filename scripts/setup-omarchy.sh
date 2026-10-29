#!/usr/bin/env bash
# setup-omarchy.sh - 一键配置 Horae 在 Omarchy 系统上的最佳原生集成
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

log()   { printf "${BLUE}[Horae-Omarchy]${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}[✓]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
err()   { printf "${RED}[✗]${NC} %s\n" "$*" >&2; }

BINDING_INDEX="$(mktemp)"
SKIPPED=()
trap 'rm -f "$BINDING_INDEX"' EXIT

# 把 "SUPER + SHIFT + I" / "SHIFT ALT + D" 之类的写法归一化成可比较的形式
# （修饰键按字母序排列、键名放最前），这样不同来源的绑定才能正确比对。
normalize_key() {
    printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]' \
        | tr '+' ' ' | tr -s ' ' \
        | awk '{
            n = NF; if (n == 0) exit
            key = $n; m = 0
            for (i = 1; i < n; i++) mods[++m] = $i
            for (i = 1; i <= m; i++)
                for (j = i + 1; j <= m; j++)
                    if (mods[i] > mods[j]) { t = mods[i]; mods[i] = mods[j]; mods[j] = t }
            out = key
            for (i = 1; i <= m; i++) out = out "+" mods[i]
            print out
        }'
}

# 汇总当前系统所有按键绑定：运行时绑定表（需 Hyprland 会话）+ 用户配置 + Omarchy 默认配置。
# 注释行会被剥离，避免把文档里的示例当成真实绑定。
build_binding_index() {
    local omarchy_path="${OMARCHY_PATH:-/usr/share/omarchy}"
    local dir file key

    if command -v omarchy >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1; then
        omarchy menu keybindings --print 2>/dev/null \
            | sed -nE 's/^(.+[^ ]) +→ +(.+)$/\1\t\2/p' \
            | while IFS=$'\t' read -r key _; do
                [ -n "$key" ] && printf '%s\t%s\n' "$(normalize_key "$key")" "$key (运行时)"
              done
    fi

    for dir in "$HOME/.config/hypr" "$omarchy_path/default/hypr"; do
        [ -d "$dir" ] || continue
        while IFS= read -r file; do
            sed -E 's/--.*$//' "$file" 2>/dev/null \
                | grep -hoE '(o\.(re)?bind(_toggle|_hold)?|hl\.bind)\([[:space:]]*"[^"]+"' 2>/dev/null \
                | sed -E 's/^[a-z_.]+\([[:space:]]*"//; s/"$//' \
                | while IFS= read -r key; do
                    [ -n "$key" ] && printf '%s\t%s\n' "$(normalize_key "$key")" "$key ($file)"
                  done
        done < <(find "$dir" -name '*.lua' -type f ! -name '*.bak*' 2>/dev/null)
    done
}

# 某个按键若已被占用，打印占用着它的原始写法；未占用则返回非零。
key_owner() {
    local want
    want="$(normalize_key "${1:-}")"
    [ -n "$want" ] || return 1
    awk -F'\t' -v w="$want" '$1 == w { print $2; found = 1; exit } END { exit !found }' "$BINDING_INDEX"
}

# 为一个动作挑选空闲按键。用户显式指定（HORAE_*_KEY）时绝不覆盖冲突；
# 否则按候选顺序挑第一个没被占用的。全部被占用则返回非零。
pick_free_key() {
    local label="$1" env_name="$2" candidate owner
    shift 2

    local explicit="${!env_name:-}"
    if [ -n "$explicit" ]; then
        if owner="$(key_owner "$explicit")"; then
            err "$label：指定的 $explicit 已被占用（$owner）"
            warn "请改用其他按键，或先解除该绑定再重跑。" >&2
            return 1
        fi
        printf '%s\n' "$explicit"
        return 0
    fi

    for candidate in "$@"; do
        if ! owner="$(key_owner "$candidate")"; then
            printf '%s\n' "$candidate"
            return 0
        fi
        # 本函数用 $( ) 取键名，诊断信息必须走 stderr，否则会被当成键名捕获
        warn "$label：$candidate 已被占用（$owner），改用下一个候选键" >&2
    done

    err "$label：候选键全部被占用"
    return 1
}

backup_file() {
    local target="$1"
    [ -f "$target" ] || return 0
    local stamp backup
    stamp="$(date +%s)"
    backup="$target.bak.$stamp"
    cp -p "$target" "$backup"
    ok "已备份 $(basename "$target") → $(basename "$backup")"
}

# 解析命令行参数
DO_INSTALL_CARGO=false
DO_INSTALL_NPM=false
DO_ALIASES=false
DO_SHORTCUTS=false
DO_BAR=false
DO_COMPLETIONS=false
DO_DESKTOP=false
DO_VOXTYPE=false

if [ $# -eq 0 ]; then
    DO_ALIASES=true
    DO_SHORTCUTS=true
    DO_BAR=true
    DO_COMPLETIONS=true
    DO_DESKTOP=true
    DO_VOXTYPE=true
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --all)
            DO_ALIASES=true
            DO_SHORTCUTS=true
            DO_BAR=true
            DO_COMPLETIONS=true
            DO_DESKTOP=true
            DO_VOXTYPE=true
            ;;
        --install-cargo)
            DO_INSTALL_CARGO=true
            ;;
        --install-npm)
            DO_INSTALL_NPM=true
            ;;
        --aliases)
            DO_ALIASES=true
            ;;
        --shortcuts)
            DO_SHORTCUTS=true
            ;;
        --bar)
            DO_BAR=true
            ;;
        --completions)
            DO_COMPLETIONS=true
            ;;
        --desktop)
            DO_DESKTOP=true
            ;;
        --voxtype)
            DO_VOXTYPE=true
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  --all             配置除安装之外的所有项目 (别名、快捷键、状态栏、补全、桌面图标)"
            echo "  --install-cargo   使用 cargo install horae 安装/更新"
            echo "  --install-npm     使用 npm i -g horae-cli 安装/更新"
            echo "  --aliases         配置 hc / hcc shell 别名"
            echo "  --shortcuts       安装快捷启动脚本并配置 Hyprland 快捷键与浮动窗口"
            echo "  --bar             安装并启用 Omarchy 状态栏组件 (io.github.zhaohang1205.horae-tasks)"
            echo "  --completions     安装 shell 自动补全 (bash, zsh, fish)"
            echo "  --desktop         安装 desktop 应用菜单图标"
            echo "  --voxtype         把 voxtype 粘贴键设为 ctrl+shift+v（终端粘贴语音文本）"
            exit 0
            ;;
        *)
            err "未知选项: $1"
            exit 1
            ;;
    esac
    shift
done

# 0. 权限与私有配置目录保障
mkdir -p "$HOME/.config/horae" && chmod 700 "$HOME/.config/horae"
mkdir -p "$HOME/.local/bin"

find_horae() {
    if command -v horae >/dev/null 2>&1; then
        command -v horae
    elif [ -x "$HOME/.cargo/bin/horae" ]; then
        echo "$HOME/.cargo/bin/horae"
    elif [ -x "$HOME/.local/bin/horae" ]; then
        echo "$HOME/.local/bin/horae"
    else
        echo ""
    fi
}

# 1. 安装/更新 Horae
# 工具链缺失时只跳过安装这一步，不让 set -e 把后面的配置全部带走。
if [ "$DO_INSTALL_CARGO" = true ]; then
    if command -v cargo >/dev/null 2>&1; then
        log "正在使用 Cargo 安装 horae..."
        if cargo install horae; then
            ok "Cargo 安装完成: $(find_horae)"
        else
            err "cargo install horae 失败，跳过安装"
        fi
    else
        err "未找到 cargo，无法使用 --install-cargo（可改用 --install-npm）"
    fi
fi

if [ "$DO_INSTALL_NPM" = true ]; then
    if command -v npm >/dev/null 2>&1; then
        log "正在使用 npm 安装 horae-cli..."
        if npm install -g horae-cli; then
            ok "npm 安装完成: $(find_horae)"
        else
            err "npm install -g horae-cli 失败，跳过安装"
        fi
    else
        err "未找到 npm，无法使用 --install-npm（可改用 --install-cargo）"
    fi
fi

HORAE_BIN=$(find_horae)
if [ -z "$HORAE_BIN" ]; then
    warn "未检测到已安装的 horae 二进制文件。"
    warn "您可以稍后运行: cargo install horae 或 npm i -g horae-cli"
fi

# 2. 安装辅助快捷脚本 (horae-flash, horae-normal, horae-clip)
install_helper_scripts() {
    log "正在安装快捷脚本至 ~/.local/bin/ ..."
    cp "$SCRIPT_DIR/horae-flash" "$HOME/.local/bin/horae-flash"
    cp "$SCRIPT_DIR/horae-normal" "$HOME/.local/bin/horae-normal"
    cp "$SCRIPT_DIR/horae-clip" "$HOME/.local/bin/horae-clip"
    chmod +x "$HOME/.local/bin/horae-flash" "$HOME/.local/bin/horae-normal" "$HOME/.local/bin/horae-clip"
    ok "快捷脚本安装完成 (~/.local/bin/horae-{flash,normal,clip})"
}

# 3. 配置 Hyprland 快捷键与窗口规则
setup_hyprland() {
    install_helper_scripts

    local BINDINGS_LUA="$HOME/.config/hypr/bindings.lua"
    local HYPRLAND_LUA="$HOME/.config/hypr/hyprland.lua"
    local NEED_RELOAD=false
    declare -A BACKED_UP_FILES=()

    if [ ! -f "$BINDINGS_LUA" ] && [ ! -f "$HYPRLAND_LUA" ]; then
        warn "未找到 $BINDINGS_LUA 或 $HYPRLAND_LUA，跳过 Hyprland 集成"
        return 0
    fi

    # 建立全系统按键索引（含 Omarchy 默认绑定），用于冲突检测
    log "正在扫描现有按键绑定，检查冲突..."
    build_binding_index > "$BINDING_INDEX" 2>/dev/null || true

    # 索引空说明既没读到运行时绑定表，也没读到任何 lua 配置。
    # 这种情况下"检测不到冲突"并不等于"没有冲突"，继续绑定就有抢占风险，
    # 所以宁可只配窗口规则，也不动用户现有键位。
    local INDEX_OK=true
    if [ ! -s "$BINDING_INDEX" ]; then
        INDEX_OK=false
        warn "未能读取任何现有按键绑定（请检查 OMARCHY_PATH 与 ~/.config/hypr）"
        warn "冲突检测不可用，为避免抢占现有快捷键，本次跳过键位绑定"
        SKIPPED+=("Hyprland 快捷键（冲突检测不可用）")
    fi

    # 改动任何 hypr 配置前先留一份时间戳备份（SKILL.md 安全红线一）。
    # 按文件去重：bindings.lua 与 hyprland.lua 各自都要有一份。
    ensure_backup() {
        local target="$1"
        [ -n "${BACKED_UP_FILES[$target]:-}" ] && return 0
        backup_file "$target"
        BACKED_UP_FILES[$target]=1
    }

    # 追加一条快捷键。键位被占用时不再静默覆盖（SKILL.md 安全红线二），
    # 而是按候选顺序换用下一个空闲键；用户显式指定的键冲突则直接跳过。
    add_binding() {
        local lua_file="$1" marker="$2" label="$3" env_name="$4" dispatcher="$5"
        shift 5
        local key

        if grep -q "$marker" "$lua_file"; then
            ok "${label}快捷键已有配置，跳过重复写入"
            return 0
        fi

        if ! key="$(pick_free_key "$label" "$env_name" "$@")"; then
            warn "${label}快捷键未配置（键位冲突），跳过"
            SKIPPED+=("$label 快捷键")
            return 0
        fi

        ensure_backup "$lua_file"
        {
            printf '\n-- Horae: %s\n' "$label"
            printf 'o.bind("%s", "Horae (%s)", %s)\n' "$key" "$label" "$dispatcher"
        } >> "$lua_file"

        # 把刚占用的键写回索引，避免同一次运行里后一个动作又选中同一个键
        printf '%s\t%s\n' "$(normalize_key "$key")" "$key (本次新增)" >> "$BINDING_INDEX"

        ok "${label}快捷键已绑定到 $key"
        printf -v "${env_name}_USED" '%s' "$key"
        NEED_RELOAD=true
    }

    if [ -f "$BINDINGS_LUA" ] && [ "$INDEX_OK" = true ]; then
        log "正在检查 Hyprland 快捷键配置 ($BINDINGS_LUA)..."

        add_binding "$BINDINGS_LUA" "horae-flash" "Flash" "HORAE_FLASH_KEY" \
            '{ tui = "horae-flash", focus = true }' \
            "SUPER + I" "SUPER + ALT + I" "SUPER + ALT + C"

        add_binding "$BINDINGS_LUA" "horae-normal" "Normal" "HORAE_NORMAL_KEY" \
            '{ tui = "horae-normal", focus = true }' \
            "SUPER + SHIFT + I" "SUPER + ALT + SHIFT + I" "SUPER + ALT + N"

        add_binding "$BINDINGS_LUA" "horae-clip" "Clip" "HORAE_CLIP_KEY" \
            'os.getenv("HOME") .. "/.local/bin/horae-clip"' \
            "CTRL + 1" "SUPER + ALT + C" "SUPER + ALT + SHIFT + C"
    fi

    if [ -f "$HYPRLAND_LUA" ]; then
        log "正在检查 Hyprland 浮动窗口规则 ($HYPRLAND_LUA)..."
        # 用注释标记判断，避免正则转义层数导致 check 永远不命中、每次重复注入
        if ! grep -qF "Horae Flash Capture" "$HYPRLAND_LUA"; then
            ensure_backup "$HYPRLAND_LUA"
            cat >> "$HYPRLAND_LUA" << 'EOF'

-- Horae Flash Capture (居中浮动小窗)
o.window("^org\\.omarchy\\.horae-flash$", {
	float = true,
	center = true,
	size = { 800, 600 },
})

-- Horae TUI (居中浮动 3/4 屏幕)
o.window("^(org\\.omarchy\\.horae|org\\.omarchy\\.horae-normal)$", {
	float = true,
	center = true,
	size = { "(monitor_w*0.75)", "(monitor_h*0.75)" },
})
EOF
            ok "已注入 Horae 浮动窗口规则"
            NEED_RELOAD=true
        else
            ok "Horae 浮动窗口规则已有配置，跳过重复写入"
        fi
    fi

    if [ "$NEED_RELOAD" = true ] && command -v hyprctl >/dev/null 2>&1; then
        if hyprctl reload >/dev/null 2>&1; then
            ok "Hyprland 配置已即时重载"
        else
            warn "hyprctl reload 失败，请手动检查配置：hyprctl configerrors"
        fi
    fi
}

# 4. 配置 Shell 别名 (hc, hcc)
setup_aliases() {
    log "正在检查并添加 Shell 别名 (hc, hcc)..."
    
    local TARGET_RCS=()
    [ -f "$HOME/.zshrc" ] && TARGET_RCS+=("$HOME/.zshrc")
    [ -f "$HOME/.bashrc" ] && TARGET_RCS+=("$HOME/.bashrc")

    for rc in "${TARGET_RCS[@]}"; do
        if ! grep -Eq '^[[:space:]]*alias[[:space:]]+hc=' "$rc" 2>/dev/null; then
            echo "alias hc='horae capture'                 # 快速捕获任务" >> "$rc"
            ok "已在 $rc 中添加 alias hc='horae capture'"
        else
            ok "$rc 中已存在 alias hc，保留用户配置"
        fi

        if ! grep -Eq '^[[:space:]]*alias[[:space:]]+hcc=' "$rc" 2>/dev/null; then
            echo "alias hcc='horae capture --clip'         # 快速捕获剪贴板内容" >> "$rc"
            ok "已在 $rc 中添加 alias hcc='horae capture --clip'"
        else
            ok "$rc 中已存在 alias hcc，保留用户配置"
        fi
    done

    # fish shell 支持
    local FISH_CONFIG="$HOME/.config/fish/config.fish"
    if [ -f "$FISH_CONFIG" ]; then
        if ! grep -Eq '^[[:space:]]*alias[[:space:]]+hc=' "$FISH_CONFIG" 2>/dev/null; then
            echo "alias hc='horae capture'" >> "$FISH_CONFIG"
            ok "已在 $FISH_CONFIG 中添加 alias hc"
        fi
        if ! grep -Eq '^[[:space:]]*alias[[:space:]]+hcc=' "$FISH_CONFIG" 2>/dev/null; then
            echo "alias hcc='horae capture --clip'" >> "$FISH_CONFIG"
            ok "已在 $FISH_CONFIG 中添加 alias hcc"
        fi
    fi
}

# 5. 安装 Shell 自动补全
setup_completions() {
    if [ -z "$HORAE_BIN" ]; then
        warn "未找到 horae 命令，跳过自动补全生成"
        return
    fi
    log "正在生成 Shell 自动补全脚本..."

    # 生成失败时不要把空文件留在补全目录里，否则 shell 启动会读到空脚本。
    gen_completion() {
        local shell_name="$1" target="$2"
        local tmp
        tmp="$(mktemp)"
        if "$HORAE_BIN" completions "$shell_name" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
            mkdir -p "$(dirname "$target")"
            mv "$tmp" "$target"
            ok "${shell_name} 补全已写入 $target"
        else
            rm -f "$tmp"
            warn "${shell_name} 补全生成失败，已跳过（未写入空文件）"
            SKIPPED+=("$shell_name 补全")
        fi
    }

    gen_completion bash "$HOME/.local/share/bash-completion/completions/horae"
    gen_completion zsh  "$HOME/.local/share/zsh/site-functions/_horae"
    gen_completion fish "$HOME/.config/fish/completions/horae.fish"
}

# 6. 配置 Omarchy 状态栏插件
setup_bar_widget() {
    local PLUGIN_ID="io.github.zhaohang1205.horae-tasks"
    local TARGET_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
    # 仅在参与开发时通过环境变量指向本地 clone，默认走 git 安装
    local LOCAL_REPO="${HORAE_OMARCHY_SHELL_REPO:-}"

    log "正在配置 Omarchy 状态栏组件 ($PLUGIN_ID)..."
    mkdir -p "$HOME/.config/omarchy/plugins"

    if [ -n "$LOCAL_REPO" ]; then
        if [ ! -d "$LOCAL_REPO" ]; then
            err "HORAE_OMARCHY_SHELL_REPO 指向的目录不存在: $LOCAL_REPO"
            SKIPPED+=("状态栏组件")
            return 0
        fi
        if [ "$LOCAL_REPO" != "$TARGET_DIR" ]; then
            rm -rf "$TARGET_DIR"
            ln -s "$LOCAL_REPO" "$TARGET_DIR"
            ok "已软链接本地组件仓库至: $TARGET_DIR"
        fi
    elif [ ! -d "$TARGET_DIR" ]; then
        if command -v omarchy >/dev/null 2>&1; then
            omarchy plugin add https://github.com/zhaohang1205/horae_for_omarchy_shell.git --enable 2>/dev/null || true
            ok "通过 omarchy plugin add 安装完成"
        fi
    fi

    # 启用并在状态栏中配置位置
    if command -v omarchy >/dev/null 2>&1; then
        omarchy plugin enable "$PLUGIN_ID" --section center 2>/dev/null || true
    fi

    if command -v omarchy-shell >/dev/null 2>&1; then
        omarchy-shell shell setBarWidget "$PLUGIN_ID" "maxWidth" "420" "{}" >/dev/null 2>&1 || true
        omarchy-shell shell setBarWidget "$PLUGIN_ID" "autoDismiss" "15" "{}" >/dev/null 2>&1 || true
        omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
        ok "已应用推荐状态栏参数 (maxWidth: 420, autoDismiss: 15s) 并热重载"
    fi
}

# 8. 配置 voxtype 的粘贴键
# 终端里 ctrl+v 不是粘贴（那是字面量 v），foot/ghostty 用的是 ctrl+shift+v。
# horae 的输入框靠 bracketed paste 接收文本，粘贴键不对就录不进待办。
setup_voxtype() {
    if ! command -v voxtype >/dev/null 2>&1; then
        info "未安装 voxtype，跳过语音粘贴键配置"
        return 0
    fi

    # voxtype 用 getpwuid 拿真实家目录，不认被覆盖的 $HOME，所以备份也要跟着走。
    local voxtype_home voxtype_config
    voxtype_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)"
    voxtype_home="${voxtype_home:-$HOME}"
    voxtype_config="${XDG_CONFIG_HOME:-$voxtype_home/.config}/voxtype/config.toml"

    local current
    current="$(voxtype config get output.paste_keys 2>/dev/null | tr -d '"' | tr -d '\r')"
    if [ "$current" = "ctrl+shift+v" ] || [ "$current" = "shift+insert" ]; then
        ok "voxtype 粘贴键已是 $current"
    else
        if [ -f "$voxtype_config" ]; then
            backup_file "$voxtype_config"
        fi

        log "正在把 voxtype 粘贴键设为 ctrl+shift+v（终端里 ctrl+v 只是字面量 v）..."
        if voxtype config set output.paste_keys ctrl+shift+v >/dev/null 2>&1; then
            ok "voxtype 粘贴键已设为 ctrl+shift+v"
        else
            err "设置 voxtype 粘贴键失败"
            SKIPPED+=("voxtype 粘贴键")
        fi
    fi

    # voxtype 自带 evdev 全局热键（默认 ScrollLock）。若同时用合成器绑定调用
    # `voxtype record start/stop`，一次按键会有两条触发路径，第二次 start 会被
    # daemon 以 "daemon is Recording" 挡掉，录音时长也会对不上。
    local hotkey_enabled
    hotkey_enabled="$(voxtype config get hotkey.enabled 2>/dev/null | tr -d '"' | tr -d '\r')"
    if [ "$hotkey_enabled" = "true" ]; then
        local hotkey_key
        hotkey_key="$(voxtype config get hotkey.key 2>/dev/null | tr -d '"' | tr -d '\r')"
        warn "voxtype 自带的 evdev 全局热键仍开启（$hotkey_key）"
        warn "  若你用合成器快捷键调用 voxtype record，请关闭它以免两条触发路径打架："
        warn "    voxtype config set hotkey.enabled false && systemctl --user restart voxtype.service"
    fi

    # output.* 与 hotkey.* 都是 daemon 启动时读取的项，改完必须重启才生效
    if systemctl --user is-active --quiet voxtype.service 2>/dev/null; then
        if systemctl --user restart voxtype.service >/dev/null 2>&1; then
            ok "voxtype daemon 已重启以应用新配置"
        else
            warn "voxtype daemon 重启失败，请手动执行：systemctl --user restart voxtype.service"
        fi
    fi
}

# 7. 安装 Desktop 菜单图标
setup_desktop_entry() {
    log "正在生成桌面应用启动器 (Desktop Entry)..."
    local APPS_DIR="$HOME/.local/share/applications"
    mkdir -p "$APPS_DIR"
    cat > "$APPS_DIR/horae.desktop" << 'EOF'
[Desktop Entry]
Name=Horae
GenericName=GTD Task Manager
Comment=Capture and manage GTD tasks with Pomodoro in terminal
Exec=omarchy-launch-or-focus-tui horae
Icon=task-due-symbolic
Terminal=false
Type=Application
Categories=Office;ProjectManagement;Utility;
Keywords=gtd;todo;task;pomodoro;horae;
StartupWMClass=org.omarchy.horae
EOF
    chmod 644 "$APPS_DIR/horae.desktop"
    ok "Desktop 文件已创建: $APPS_DIR/horae.desktop"
}

# 执行选中的模块
[ "$DO_SHORTCUTS" = true ] && setup_hyprland
[ "$DO_ALIASES" = true ] && setup_aliases
[ "$DO_COMPLETIONS" = true ] && setup_completions
[ "$DO_BAR" = true ] && setup_bar_widget
[ "$DO_DESKTOP" = true ] && setup_desktop_entry
[ "$DO_VOXTYPE" = true ] && setup_voxtype

printf "\n${BOLD}${GREEN}========================================${NC}\n"
printf "${BOLD}${GREEN}   Horae for Omarchy 配置完成！        ${NC}\n"
printf "${BOLD}${GREEN}========================================${NC}\n"
printf "体验指南:\n"
if [ -n "${HORAE_FLASH_KEY_USED:-}" ]; then
    printf "  • 按 ${BOLD}%s${NC} 呼出闪念录入浮窗（打完回车秒级退出并保存入收件箱）\n" "$HORAE_FLASH_KEY_USED"
fi
if [ -n "${HORAE_NORMAL_KEY_USED:-}" ]; then
    printf "  • 按 ${BOLD}%s${NC} 呼出/聚焦 Horae 全功能 GTD 终端界面\n" "$HORAE_NORMAL_KEY_USED"
fi
if [ -n "${HORAE_CLIP_KEY_USED:-}" ]; then
    printf "  • 鼠标划选文本后按 ${BOLD}%s${NC} 自动复制并写入待办（伴随桌面提示）\n" "$HORAE_CLIP_KEY_USED"
fi
printf "  • 终端中使用 ${BOLD}hc \"任务内容 @tag ~时间\"${NC} 极速录入\n"
printf "  • 状态栏已展示 Horae 番茄钟环与到期任务卡片（点击可开番茄/选任务）\n"

if [ "${#SKIPPED[@]}" -gt 0 ]; then
    printf "\n${YELLOW}以下项目因按键冲突或环境缺失未配置：${NC}\n"
    for item in "${SKIPPED[@]}"; do
        printf "  • %s\n" "$item"
    done
    printf "可用环境变量指定按键后重跑，例如：\n"
    printf "  ${BOLD}HORAE_FLASH_KEY=\"SUPER + ALT + I\" %s --shortcuts${NC}\n" "$0"
fi
printf "\n"
