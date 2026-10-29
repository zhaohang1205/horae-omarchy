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
is "改用空闲的 SUPER + ALT + I" "$(grep -c 'SUPER + ALT + I' "$WORK/t1/home/.config/hypr/bindings.lua")" 1
is "旧的 SUPER + I 仍留在用户配置里" "$(grep -c 'F9' "$WORK/t1/home/.config/hypr/bindings.lua")" 1

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
run_setup "$WORK/t7" --install-cargo --completions >/dev/null 2>&1
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

printf '\n\033[1m========================================\033[0m\n'
if [ "$FAIL" -eq 0 ]; then
    printf '\033[0;32m全部通过：%d 项\033[0m\n' "$PASS"
    exit 0
fi
printf '\033[0;31m失败 %d 项，通过 %d 项\033[0m\n' "$FAIL" "$PASS"
exit 1
