#!/usr/bin/env bash
# 沙箱回归测试：在临时 HOME / 伪 Omarchy 目录里跑 setup-omarchy.sh 与 preflight.sh。
# 不需要真实的 Hyprland、Omarchy 或 voxtype —— 所有外部命令都用桩替掉。
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$REPO_ROOT/scripts/setup-omarchy.sh"
PREFLIGHT="$REPO_ROOT/scripts/preflight.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  \033[0;32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[0;31m✗\033[0m %s (期望 %s，实际 %s)\n' "$1" "$3" "$2"; }
is() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

# 造一个假环境：伪 Omarchy 默认绑定 + 伪用户配置 + 只含桩的 PATH 前缀
make_fixture() {
    local root="$1" with_user_binds="${2:-yes}"

    rm -rf "$root"
    mkdir -p "$root/home/.config/hypr" \
             "$root/omarchy/default/hypr/bindings" \
             "$root/stub"

    # 真实 Omarchy 上这两个键就是输入法切换，必须被识别为已占用
    printf '%s\n' \
        'o.bind("SUPER + I", "Switch input language", "omarchy-input-method cycle")' \
        'o.bind("SUPER + SHIFT + I", "Switch input language back", "omarchy-input-method cycle back")' \
        >"$root/omarchy/default/hypr/bindings/input-method.lua"

    # o.bind_toggle 也必须能识别；注释里的示例不算真实绑定
    printf '%s\n' \
        '-- o.bind("SUPER + SHIFT + R", "SSH (example)", "true")' \
        'o.bind_toggle("SUPER + SHIFT + SPACE", "Toggle top bar", "bar")' \
        >"$root/omarchy/default/hypr/bindings/utilities.lua"

    if [ "$with_user_binds" = yes ]; then
        printf '%s\n' 'o.bind("F9", "VoxType start", "voxtype record start")' \
            >"$root/home/.config/hypr/bindings.lua"
    else
        printf '%s\n' '-- 只有注释，没有任何真实绑定' \
            >"$root/home/.config/hypr/bindings.lua"
    fi
    printf '%s\n' 'require("default.hypr.omarchy")' \
        >"$root/home/.config/hypr/hyprland.lua"

    # 桩：运行时绑定表拿不到任何东西
    printf '#!/bin/sh\nexit 1\n' >"$root/stub/omarchy"
    printf '#!/bin/sh\nexit 1\n' >"$root/stub/hyprctl"
    chmod +x "$root/stub/omarchy" "$root/stub/hyprctl"
}

env_for() { printf 'HOME=%s OMARCHY_PATH=%s PATH=%s/stub:/usr/local/bin:/usr/bin:/bin' \
    "$1/home" "$1/omarchy" "$1"; }

run_setup() {
    local root="$1"
    shift
    # shellcheck disable=SC2046
    env $(env_for "$root") bash "$SETUP" "$@"
}

printf '\033[1m沙箱回归测试\033[0m\n\n'

printf '\033[1m[1] 幂等性\033[0m\n'
make_fixture "$WORK/t1"
run_setup "$WORK/t1" --shortcuts >/dev/null 2>&1
B1=$(wc -l <"$WORK/t1/home/.config/hypr/bindings.lua")
H1=$(wc -l <"$WORK/t1/home/.config/hypr/hyprland.lua")
run_setup "$WORK/t1" --shortcuts >/dev/null 2>&1
run_setup "$WORK/t1" --shortcuts >/dev/null 2>&1
is "bindings.lua 不重复注入" "$(wc -l <"$WORK/t1/home/.config/hypr/bindings.lua")" "$B1"
is "hyprland.lua 不重复注入" "$(wc -l <"$WORK/t1/home/.config/hypr/hyprland.lua")" "$H1"
is "窗口规则只写一次" "$(grep -c 'Horae Flash Capture' "$WORK/t1/home/.config/hypr/hyprland.lua")" 1
is "两个文件各有一份备份" "$(find "$WORK/t1/home/.config/hypr" -maxdepth 1 -name '*.bak.*' | wc -l)" 2

printf '\n\033[1m[2] 键位冲突规避\033[0m\n'
is "未占用输入法的 SUPER + I" "$(grep -c 'o.bind("SUPER + I"' "$WORK/t1/home/.config/hypr/bindings.lua")" 0
is "闪念绑定落在 F8" "$(grep -c 'o.bind("F8", "Horae (Flash)"' "$WORK/t1/home/.config/hypr/bindings.lua")" 1
is "旧的 F9 仍留在用户配置里" "$(grep -c 'F9' "$WORK/t1/home/.config/hypr/bindings.lua")" 1

printf '\n\033[1m[2b] 闪念绑定只用一条，按焦点分流\033[0m\n'
B="$WORK/t1/home/.config/hypr/bindings.lua"
is "只写了一条 F8 绑定" "$(grep -c 'o\.bind("F8"' "$B")" 1
is "不再使用有缺陷的 hl.dsp.pass" "$(grep -c 'hl\.dsp\.pass(' "$B")" 0
is "用官方 send_key_state 把按键送回闪念窗" "$(grep -c 'send_key_state' "$B")" 2
is "转发前先判断焦点窗口" "$(grep -c 'get_active_window' "$B")" 1
is "键位菜单能还原成可执行命令" "$(grep -c 'o\.bind_commands\[horae_flash_bind\]' "$B")" 1

printf '\n\033[1m[3] 注释里的示例不算占用\033[0m\n'
make_fixture "$WORK/t3"
# shellcheck disable=SC2046
env $(env_for "$WORK/t3") HORAE_FLASH_KEY="SUPER + SHIFT + R" \
    bash "$SETUP" --shortcuts >/dev/null 2>&1
is "SUPER + SHIFT + R（仅出现在注释）可采用" \
    "$(grep -c 'SUPER + SHIFT + R' "$WORK/t3/home/.config/hypr/bindings.lua")" 1

printf '\n\033[1m[4] o.bind_toggle 的键必须被识别\033[0m\n'
make_fixture "$WORK/t4"
# shellcheck disable=SC2046
env $(env_for "$WORK/t4") HORAE_FLASH_KEY="SUPER + SHIFT + SPACE" \
    bash "$SETUP" --shortcuts >/dev/null 2>&1
is "toggle 绑定的键被拒绝" "$(grep -c 'horae-flash' "$WORK/t4/home/.config/hypr/bindings.lua")" 0

printf '\n\033[1m[5] 显式指定冲突键要报错而不是强占\033[0m\n'
make_fixture "$WORK/t5"
out=$(env HOME="$WORK/t5/home" OMARCHY_PATH="$WORK/t5/omarchy" \
    PATH="$WORK/t5/stub:/usr/local/bin:/usr/bin:/bin" HORAE_FLASH_KEY="SUPER + I" \
    bash "$SETUP" --shortcuts 2>&1)
is "未写入冲突键" "$(grep -c 'horae-flash' "$WORK/t5/home/.config/hypr/bindings.lua")" 0
case "$out" in
*"已被占用"*) pass "给出了占用提示" ;;
*) fail "给出了占用提示" "无提示" "含「已被占用」" ;;
esac

printf '\n\033[1m[6] 索引为空时不冒进绑定\033[0m\n'
make_fixture "$WORK/t6" no
# 连伪 Omarchy 默认配置也清掉，制造"什么都读不到"的场景
rm -rf "$WORK/t6/omarchy"
run_setup "$WORK/t6" --shortcuts >/dev/null 2>&1
is "没有写入任何快捷键" \
    "$(grep -vE '^[[:space:]]*--' "$WORK/t6/home/.config/hypr/bindings.lua" | grep -c 'o.bind' || true)" 0
is "窗口规则照常写入" "$(grep -c 'Horae' "$WORK/t6/home/.config/hypr/hyprland.lua")" 2

printf '\n\033[1m[7] 工具链缺失不中止整个脚本\033[0m\n'
make_fixture "$WORK/t7"
mkdir -p "$WORK/t7/no-cargo-bin"
for b in bash sh env mkdir chmod cp rm mv sed grep awk mktemp cat date cut dirname basename head wc cmp find sort tr; do
    p=$(type -P "$b" 2>/dev/null)
    [ -n "$p" ] && ln -sf "$p" "$WORK/t7/no-cargo-bin/$b"
done
env HOME="$WORK/t7/home" OMARCHY_PATH="$WORK/t7/omarchy" \
    PATH="$WORK/t7/stub:$WORK/t7/no-cargo-bin" \
    bash "$SETUP" --install-cargo --completions >/dev/null 2>&1
is "--install-cargo 在无 cargo 时退出码为 0" "$?" 0

printf '\n\033[1m[8] 补全生成失败不留空文件\033[0m\n'
make_fixture "$WORK/t8"
printf '#!/bin/sh\n[ "$1" = completions ] && exit 1\nexit 0\n' >"$WORK/t8/stub/horae"
chmod +x "$WORK/t8/stub/horae"
run_setup "$WORK/t8" --completions >/dev/null 2>&1
is "没有残留的空补全文件" \
    "$(find "$WORK/t8" \( -name '_horae' -o -name 'horae.fish' \) | wc -l)" 0

printf '\n\033[1m[9] 备份内容等于改动前\033[0m\n'
make_fixture "$WORK/t9"
cp "$WORK/t9/home/.config/hypr/bindings.lua" "$WORK/t9/orig-bindings.lua"
cp "$WORK/t9/home/.config/hypr/hyprland.lua" "$WORK/t9/orig-hyprland.lua"
run_setup "$WORK/t9" --shortcuts >/dev/null 2>&1
bk=$(find "$WORK/t9/home/.config/hypr" -name 'bindings.lua.bak.*' | head -1)
hk=$(find "$WORK/t9/home/.config/hypr" -name 'hyprland.lua.bak.*' | head -1)
if cmp -s "$bk" "$WORK/t9/orig-bindings.lua"; then pass "bindings.lua 备份与原始一致"; else fail "bindings.lua 备份与原始一致" "不一致" "一致"; fi
if cmp -s "$hk" "$WORK/t9/orig-hyprland.lua"; then pass "hyprland.lua 备份与原始一致"; else fail "hyprland.lua 备份与原始一致" "不一致" "一致"; fi

printf '\n\033[1m[10] .agents 副本与根目录保持一致\033[0m\n'
drift=""
for f in SKILL.md README.md references/hyprland-bindings.md references/bar-widget.md \
    references/troubleshooting.md scripts/setup-omarchy.sh scripts/preflight.sh \
    scripts/horae-clip scripts/horae-flash scripts/horae-normal; do
    src="$REPO_ROOT/$f"
    dst="$REPO_ROOT/.agents/skills/horae-omarchy/$f"
    if [ -f "$src" ] && ! cmp -s "$src" "$dst"; then
        drift="$drift $f"
    fi
done
is "没有漂移的文件" "$drift" ""

printf '\n\033[1m[11] preflight 能在无图形环境下跑完\033[0m\n'
make_fixture "$WORK/t11"
# shellcheck disable=SC2046
env $(env_for "$WORK/t11") bash "$PREFLIGHT" >/dev/null 2>&1
is "preflight 退出码为 0" "$?" 0
# shellcheck disable=SC2046
pf_out=$(env $(env_for "$WORK/t11") bash "$PREFLIGHT" 2>&1)
case "$pf_out" in
*"[7/7] 语音录入链路"*) pass "输出包含语音链路检查" ;;
*) fail "输出包含语音链路检查" "缺失" "含 [7/7]" ;;
esac

printf '\n\033[1m[12] 旧版透传绑定会被迁移掉\033[0m\n'
make_fixture "$WORK/t12"
cat >>"$WORK/t12/home/.config/hypr/bindings.lua" << 'EOF'
hl.bind("F8", hl.dsp.pass({ window = "class:^org\\.omarchy\\.horae-flash$" }))
o.bind("F8", "Horae (Flash)", { tui = "horae-flash", focus = true })
EOF
run_setup "$WORK/t12" --shortcuts >/dev/null 2>&1
T12="$WORK/t12/home/.config/hypr/bindings.lua"
is "旧的透传绑定被清掉" "$(grep -c 'hl\.dsp\.pass(' "$T12")" 0
is "旧的表格式绑定被替换" "$(grep -c 'Horae (Flash)", {' "$T12")" 0
is "换成新版单条绑定" "$(grep -c 'o\.bind("F8", "Horae (Flash)", horae_flash_bind)' "$T12")" 1
is "沿用原来的键位" "$(grep -c 'o\.bind("F8"' "$T12")" 1

printf '\n\033[1m[13] 冲突检测不可用时也清掉旧透传绑定\033[0m\n'
make_fixture "$WORK/t13" no
rm -rf "$WORK/t13/omarchy"
cat >>"$WORK/t13/home/.config/hypr/bindings.lua" << 'EOF'
hl.bind("F8", hl.dsp.pass({ window = "class:^org\\.omarchy\\.horae-flash$" }))
o.bind("F8", "Horae (Flash)", { tui = "horae-flash", focus = true })
EOF
run_setup "$WORK/t13" --shortcuts >/dev/null 2>&1
T13="$WORK/t13/home/.config/hypr/bindings.lua"
is "索引为空时旧透传绑定仍被清掉" "$(grep -c 'hl\.dsp\.pass(' "$T13")" 0
is "索引为空时不新增绑定" "$(grep -c 'horae_flash_bind' "$T13")" 0

printf '\n\033[1m[14] bindings.lua 是软链接时不被替换成普通文件\033[0m\n'
make_fixture "$WORK/t14"
mkdir -p "$WORK/t14/dotfiles"
mv "$WORK/t14/home/.config/hypr/bindings.lua" "$WORK/t14/dotfiles/bindings.lua"
ln -s "$WORK/t14/dotfiles/bindings.lua" "$WORK/t14/home/.config/hypr/bindings.lua"
cat >>"$WORK/t14/dotfiles/bindings.lua" << 'EOF'
hl.bind("F8", hl.dsp.pass({ window = "class:^org\\.omarchy\\.horae-flash$" }))
o.bind("F8", "Horae (Flash)", { tui = "horae-flash", focus = true })
EOF
run_setup "$WORK/t14" --shortcuts >/dev/null 2>&1
if [ -L "$WORK/t14/home/.config/hypr/bindings.lua" ]; then pass "仍然是软链接"; else fail "仍然是软链接" "被换成了普通文件" "软链接"; fi
is "改动写进了链接目标" "$(grep -c 'horae_flash_bind' "$WORK/t14/dotfiles/bindings.lua")" "$(grep -c 'horae_flash_bind' "$WORK/t14/dotfiles/bindings.lua")"
is "链接目标里的旧透传已清掉" "$(grep -c 'hl\.dsp\.pass(' "$WORK/t14/dotfiles/bindings.lua")" 0

printf '\n\033[1m[15] 多行写法的旧绑定整条删除，不留下半截字段\033[0m\n'
make_fixture "$WORK/t15"
cat >>"$WORK/t15/home/.config/hypr/bindings.lua" << 'EOF'
hl.bind("F8", hl.dsp.pass({
  window = "class:^org\\.omarchy\\.horae-flash$"
}))
o.bind("F8", "Horae (Flash)", {
  tui = "horae-flash",
  focus = true,
})
EOF
run_setup "$WORK/t15" --shortcuts >/dev/null 2>&1
T15="$WORK/t15/home/.config/hypr/bindings.lua"
is "跨行的透传绑定整条删掉" "$(grep -c 'hl\.dsp\.pass(' "$T15")" 0
is "没有遗留 window 字段" "$(grep -c 'window = "class:' "$T15")" 0
is "没有遗留 tui 字段" "$(grep -c 'tui = "horae-flash"' "$T15")" 0
is "换成新版绑定" "$(grep -c 'o\.bind("F8", "Horae (Flash)", horae_flash_bind)' "$T15")" 1

printf '\n\033[1m[16] 重跑时显式 HORAE_FLASH_KEY 会生效\033[0m\n'
make_fixture "$WORK/t16"
run_setup "$WORK/t16" --shortcuts >/dev/null 2>&1
# shellcheck disable=SC2046
env $(env_for "$WORK/t16") HORAE_FLASH_KEY="SUPER + ALT + I" bash "$SETUP" --shortcuts >/dev/null 2>&1
T16="$WORK/t16/home/.config/hypr/bindings.lua"
is "改绑到显式指定的键" "$(grep -c 'o\.bind("SUPER + ALT + I", "Horae (Flash)"' "$T16")" 1
is "旧的 F8 绑定已移除" "$(grep -c 'o\.bind("F8", "Horae (Flash)"' "$T16")" 0

printf '\n\033[1m[17] 保留的 Flash 键会占位，Clip 不会撞上\033[0m\n'
make_fixture "$WORK/t17"
cat >>"$WORK/t17/home/.config/hypr/bindings.lua" << 'EOF'
o.bind("CTRL + 1", "Terminal", "foot")
o.bind("SUPER + ALT + C", "Horae (Flash)", horae_flash_bind)
EOF
run_setup "$WORK/t17" --shortcuts >/dev/null 2>&1
T17="$WORK/t17/home/.config/hypr/bindings.lua"
is "Clip 没有占用 Flash 的键" "$(grep -c 'o\.bind("SUPER + ALT + C", "Horae (Clip)"' "$T17")" 0
is "Clip 改用下一个候选" "$(grep -c 'o\.bind("SUPER + ALT + SHIFT + C", "Horae (Clip)"' "$T17")" 1

printf '\n\033[1m[18] 候选键全冲突时仍清掉旧透传绑定\033[0m\n'
make_fixture "$WORK/t18"
cat >>"$WORK/t18/home/.config/hypr/bindings.lua" << 'EOF'
o.bind("F8", "Something else", "true")
o.bind("SUPER + ALT + I", "Another thing", "true")
o.bind("SUPER + ALT + C", "Yet another", "true")
hl.bind("F8", hl.dsp.pass({ window = "class:^org\\.omarchy\\.horae-flash$" }))
o.bind("F8", "Horae (Flash)", { tui = "horae-flash", focus = true })
EOF
run_setup "$WORK/t18" --shortcuts >/dev/null 2>&1
T18="$WORK/t18/home/.config/hypr/bindings.lua"
is "旧透传绑定被清掉" "$(grep -c 'hl\.dsp\.pass(' "$T18")" 0
is "旧的开窗绑定保留（浮窗仍能唤起）" "$(grep -c 'Horae (Flash)", {' "$T18")" 1
is "没有新增新版绑定" "$(grep -c 'horae_flash_bind' "$T18")" 0

printf '\n\033[1m[19] preflight 不把 Flash 当成 Normal 已配置\033[0m\n'
make_fixture "$WORK/t19"
cat >>"$WORK/t19/home/.config/hypr/bindings.lua" << 'EOF'
o.bind("F8", "Horae (Flash)", horae_flash_bind)
EOF
# shellcheck disable=SC2046
pf19=$(env $(env_for "$WORK/t19") bash "$PREFLIGHT" 2>&1)
case "$pf19" in
*"未配置快捷键: 应用一般模式"*) pass "Normal 未被误判为已配置" ;;
*) fail "Normal 未被误判为已配置" "被误判" "含「未配置快捷键: 应用一般模式」" ;;
esac

printf '\n\033[1m[20] 小写 f8 也走转发分支\033[0m\n'
make_fixture "$WORK/t20"
# shellcheck disable=SC2046
env $(env_for "$WORK/t20") HORAE_FLASH_KEY="f8" bash "$SETUP" --shortcuts >/dev/null 2>&1
T20="$WORK/t20/home/.config/hypr/bindings.lua"
is "小写 f8 仍生成转发逻辑" "$(grep -c 'send_key_state' "$T20")" 2

printf '\n\033[1m========================================\033[0m\n'
if [ "$FAIL" -eq 0 ]; then
    printf '\033[0;32m全部通过：%d 项\033[0m\n' "$PASS"
    exit 0
fi
printf '\033[0;31m失败 %d 项，通过 %d 项\033[0m\n' "$FAIL" "$PASS"
exit 1
