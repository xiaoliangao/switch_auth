#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenClaw Auth Profile Switcher
# 在两个或多个 OpenAI Codex 账号之间快速切换
# ============================================================

# --- 配置 ---
OPENCLAW_DIR="$HOME/.openclaw"
PROFILE_DIR=""  # 自动检测
BACKUP_DIR="$HOME/.openclaw-auth-profiles"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 函数 ---

find_profile_dir() {
    local found
    found=$(find "$OPENCLAW_DIR" -name "auth-profiles.json" -type f 2>/dev/null | head -n1)
    if [[ -n "$found" ]]; then
        PROFILE_DIR="$(dirname "$found")"
        echo -e "${GREEN}✓ 找到 auth profile:${NC} $found"
    else
        local agents_dir="$OPENCLAW_DIR/agents"
        if [[ -d "$agents_dir" ]]; then
            local agent_id
            agent_id=$(ls "$agents_dir" 2>/dev/null | head -n1)
            if [[ -n "$agent_id" ]]; then
                PROFILE_DIR="$agents_dir/$agent_id/agent"
                echo -e "${YELLOW}⚠ 未找到 auth-profiles.json，使用推测路径:${NC} $PROFILE_DIR"
            fi
        fi
    fi

    if [[ -z "$PROFILE_DIR" ]]; then
        echo -e "${RED}✗ 找不到 OpenClaw agents 目录，请确认 OpenClaw 已初始化${NC}"
        exit 1
    fi
}

ensure_backup_dir() {
    mkdir -p "$BACKUP_DIR"
}

auth_file() {
    echo "$PROFILE_DIR/auth-profiles.json"
}

backup_file() {
    echo "$BACKUP_DIR/${1}.json"
}

current_label_file() {
    echo "$BACKUP_DIR/.current"
}

get_current_label() {
    local f
    f="$(current_label_file)"
    if [[ -f "$f" ]]; then
        cat "$f"
    else
        echo "unknown"
    fi
}

set_current_label() {
    echo "$1" > "$(current_label_file)"
}

show_status() {
    local current
    current="$(get_current_label)"
    echo ""
    echo -e "${CYAN}===== OpenClaw Auth 状态 =====${NC}"
    echo -e "  当前账号:  ${GREEN}${current}${NC}"
    echo -e "  Profile:   $(auth_file)"

    # 获取当前 token 状态
    local token_status=""
    local token_expiry=""
    if command -v openclaw &>/dev/null; then
        local oc_output
        oc_output=$(openclaw models status 2>/dev/null || true)
        # 解析 "openai-codex:default ok expires in 10d" 这样的行
        local status_line
        status_line=$(echo "$oc_output" | grep -E 'openai-codex:\S+\s+(ok|expired|error)' | head -n1 || true)
        if [[ -n "$status_line" ]]; then
            if echo "$status_line" | grep -q "ok"; then
                token_expiry=$(echo "$status_line" | grep -oP 'expires in \K\S+' || true)
                if [[ -n "$token_expiry" ]]; then
                    # 提取天数判断是否快过期
                    local days
                    days=$(echo "$token_expiry" | grep -oP '^\d+' || echo "0")
                    if [[ "$days" -le 2 ]]; then
                        token_status="${YELLOW}⚠ 即将过期 (${token_expiry})${NC}"
                    else
                        token_status="${GREEN}✓ 正常，${token_expiry} 后过期${NC}"
                    fi
                else
                    token_status="${GREEN}✓ 正常${NC}"
                fi
            elif echo "$status_line" | grep -q "expired"; then
                token_status="${RED}✗ 已过期，请重新登录: $0 login ${current}${NC}"
            else
                token_status="${YELLOW}⚠ 状态异常${NC}"
            fi
        fi
    fi

    if [[ -n "$token_status" ]]; then
        echo -e "  Token:     ${token_status}"
    fi
    echo ""

    # 列出所有已保存的 label
    if [[ -d "$BACKUP_DIR" ]]; then
        for bf in "$BACKUP_DIR"/*.json; do
            [[ -f "$bf" ]] || continue
            local label
            label="$(basename "$bf" .json)"
            local acct_id
            acct_id=$(grep -o '"accountId"[[:space:]]*:[[:space:]]*"[^"]*"' "$bf" 2>/dev/null | head -n1 | sed 's/.*"accountId"[[:space:]]*:[[:space:]]*"//' | sed 's/"//')
            if [[ "$label" == "$current" ]]; then
                echo -e "  ${label}: ${GREEN}已保存${NC} (当前)  accountId=${acct_id:-N/A}"
            else
                echo -e "  ${label}: ${GREEN}已保存${NC}  accountId=${acct_id:-N/A}"
            fi
        done
    fi

    local count
    count=$(ls "$BACKUP_DIR"/*.json 2>/dev/null | wc -l)
    if [[ "$count" -eq 0 ]]; then
        echo -e "  ${YELLOW}没有已保存的账号${NC}"
        echo ""
        echo "  使用以下命令添加账号:"
        echo "    $0 login <label>"
    fi
    echo ""
}

list_labels() {
    if [[ -d "$BACKUP_DIR" ]]; then
        for bf in "$BACKUP_DIR"/*.json; do
            [[ -f "$bf" ]] || continue
            basename "$bf" .json
        done
    fi
}

cmd_save() {
    local label="$1"
    local src
    src="$(auth_file)"

    if [[ ! -f "$src" ]]; then
        echo -e "${RED}✗ auth-profiles.json 不存在，请先运行:${NC}"
        echo "  openclaw models auth login --provider openai-codex"
        exit 1
    fi

    cp "$src" "$(backup_file "$label")"
    set_current_label "$label"
    echo -e "${GREEN}✓ 已保存当前授权为 [${label}]${NC}"
}

cmd_switch() {
    local label="$1"
    local bf
    bf="$(backup_file "$label")"

    if [[ ! -f "$bf" ]]; then
        echo -e "${RED}✗ [${label}] 没有已保存的授权${NC}"
        echo "  请先登录该账号，然后运行: $0 save ${label}"
        echo ""
        echo "  已有的账号:"
        list_labels | sed 's/^/    /'
        exit 1
    fi

    local current
    current="$(get_current_label)"

    # 先把当前的存回去
    local src
    src="$(auth_file)"
    if [[ "$current" != "unknown" && -f "$src" ]]; then
        cp "$src" "$(backup_file "$current")"
        echo -e "${CYAN}↩ 已自动备份当前 [${current}] 的授权${NC}"
    fi

    # 切换
    cp "$bf" "$src"
    set_current_label "$label"
    echo -e "${GREEN}✓ 已切换到 [${label}]${NC}"
}

cmd_login_and_save() {
    local label="$1"

    # 先备份当前账号，防止 login 覆盖后丢失
    local current
    current="$(get_current_label)"
    local src
    src="$(auth_file)"
    if [[ "$current" != "unknown" && "$current" != "$label" && -f "$src" ]]; then
        cp "$src" "$(backup_file "$current")"
        echo -e "${CYAN}↩ 已自动备份当前 [${current}] 的授权${NC}"
    fi

    echo -e "${CYAN}→ 正在启动 OpenClaw 登录流程...${NC}"
    openclaw models auth login --provider openai-codex
    cmd_save "$label"
}

cmd_remove() {
    local label="$1"
    local bf
    bf="$(backup_file "$label")"

    if [[ ! -f "$bf" ]]; then
        echo -e "${RED}✗ [${label}] 不存在${NC}"
        exit 1
    fi

    local current
    current="$(get_current_label)"
    if [[ "$current" == "$label" ]]; then
        echo -e "${YELLOW}⚠ [${label}] 是当前活跃的账号${NC}"
        read -rp "确定要删除吗? (y/N) " confirm
        [[ "$confirm" =~ ^[yY]$ ]] || { echo "已取消"; exit 0; }
    fi

    rm "$bf"
    echo -e "${GREEN}✓ 已删除 [${label}]${NC}"
}

cmd_rename() {
    local old_label="$1"
    local new_label="$2"
    local old_bf new_bf
    old_bf="$(backup_file "$old_label")"
    new_bf="$(backup_file "$new_label")"

    if [[ ! -f "$old_bf" ]]; then
        echo -e "${RED}✗ [${old_label}] 不存在${NC}"
        exit 1
    fi
    if [[ -f "$new_bf" ]]; then
        echo -e "${RED}✗ [${new_label}] 已存在${NC}"
        exit 1
    fi

    mv "$old_bf" "$new_bf"

    local current
    current="$(get_current_label)"
    if [[ "$current" == "$old_label" ]]; then
        set_current_label "$new_label"
    fi

    echo -e "${GREEN}✓ 已将 [${old_label}] 重命名为 [${new_label}]${NC}"
}

usage() {
    cat <<EOF
OpenClaw Auth Profile Switcher

用法: $(basename "$0") <command> [args]

Commands:
  save   <label>              保存当前已登录的授权为指定标签
  switch <label>              切换到指定标签的授权（自动保存当前）
  login  <label>              登录并保存为指定标签
  status                      查看当前状态和所有已保存的账号
  remove <label>              删除指定标签的授权备份
  rename <old> <new>          重命名标签
  list                        列出所有已保存的标签

典型工作流:
  1. 登录并保存第一个账号:
     $(basename "$0") login personal

  2. 登录并保存第二个账号:
     $(basename "$0") login team

  3. 以后切换:
     $(basename "$0") switch personal
     $(basename "$0") switch team

  4. 查看状态:
     $(basename "$0") status
EOF
}

# --- 主逻辑 ---

find_profile_dir
ensure_backup_dir

case "${1:-}" in
    save)
        [[ -z "${2:-}" ]] && { echo -e "${RED}请指定 label${NC}"; usage; exit 1; }
        cmd_save "$2"
        ;;
    switch|sw)
        [[ -z "${2:-}" ]] && { echo -e "${RED}请指定 label${NC}"; usage; exit 1; }
        cmd_switch "$2"
        ;;
    login)
        [[ -z "${2:-}" ]] && { echo -e "${RED}请指定 label${NC}"; usage; exit 1; }
        cmd_login_and_save "$2"
        ;;
    status|st)
        show_status
        ;;
    remove|rm)
        [[ -z "${2:-}" ]] && { echo -e "${RED}请指定 label${NC}"; usage; exit 1; }
        cmd_remove "$2"
        ;;
    rename|mv)
        [[ -z "${2:-}" || -z "${3:-}" ]] && { echo -e "${RED}请指定 old_label 和 new_label${NC}"; usage; exit 1; }
        cmd_rename "$2" "$3"
        ;;
    list|ls)
        list_labels
        ;;
    *)
        usage
        ;;
esac
