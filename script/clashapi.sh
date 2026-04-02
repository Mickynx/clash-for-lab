#!/usr/bin/env bash
# shellcheck disable=SC2034
# Mihomo RESTful API 命令行工具
# 通过 API 管理代理节点、流量、连接、规则等

# ====== 配置 ======

_api_init() {
    # 从项目配置中读取端口和密钥
    local port_state="${MIHOMO_BASE_DIR:-$HOME/tools/mihomo}/config/ports.conf"
    local runtime_config="${MIHOMO_BASE_DIR:-$HOME/tools/mihomo}/runtime.yaml"
    local yq="${MIHOMO_BASE_DIR:-$HOME/tools/mihomo}/bin/yq"

    # 读取 UI 端口
    if [ -f "$port_state" ]; then
        CLASH_API_PORT=$(grep "^UI_PORT=" "$port_state" 2>/dev/null | cut -d'=' -f2)
    fi
    CLASH_API_PORT=${CLASH_API_PORT:-9090}
    CLASH_API_BASE="http://127.0.0.1:${CLASH_API_PORT}"

    # 读取 secret
    CLASH_API_SECRET=""
    if [ -x "$yq" ] && [ -f "$runtime_config" ]; then
        CLASH_API_SECRET=$("$yq" '.secret // ""' "$runtime_config" 2>/dev/null)
    fi
}

_api_curl() {
    local method=$1
    local path=$2
    shift 2
    local url="${CLASH_API_BASE}${path}"

    local -a headers=(-H 'Content-Type: application/json')
    [ -n "$CLASH_API_SECRET" ] && headers+=(-H "Authorization: Bearer ${CLASH_API_SECRET}")

    curl -s -X "$method" "${headers[@]}" "$@" "$url"
}

_api_check() {
    if ! _api_curl GET /version >/dev/null 2>&1; then
        echo "错误: 无法连接到 Mihomo API (${CLASH_API_BASE})" >&2
        echo "请确认 mihomo 正在运行: clash status" >&2
        return 1
    fi
}

_require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "错误: 需要安装 jq (JSON 解析工具)" >&2
        echo "安装: apt install jq / yum install jq / brew install jq" >&2
        return 1
    fi
}

# ====== 代理节点管理 ======

# 列出所有代理组
clashapi_groups() {
    _api_check || return 1
    _require_jq || return 1
    _api_curl GET /proxies | jq -r '
        .proxies | to_entries[]
        | select(.value.type == "Selector")
        | "\(.key)  →  \(.value.now // "N/A")"
    '
}

# 查看某个代理组的可用节点
clashapi_nodes() {
    local group=${1:-Proxies}
    _api_check || return 1
    _require_jq || return 1

    local encoded_group
    encoded_group=$(printf '%s' "$group" | jq -sRr @uri)
    _api_curl GET "/proxies/${encoded_group}" | jq -r '
        if .all then
            .all[]
        else
            "错误: 代理组 \"" + (.name // "unknown") + "\" 不存在或无可用节点"
        end
    '
}

# 查看当前选中的节点
clashapi_now() {
    local group=$1
    _api_check || return 1
    _require_jq || return 1

    if [ -n "$group" ]; then
        local encoded_group
        encoded_group=$(printf '%s' "$group" | jq -sRr @uri)
        _api_curl GET "/proxies/${encoded_group}" | jq '{group: .name, now: .now}'
    else
        _api_curl GET /proxies | jq -r '
            .proxies | to_entries[]
            | select(.value.type == "Selector")
            | {group: .key, now: .value.now}
        '
    fi
}

# 切换节点
clashapi_select() {
    local group=${1:?用法: clashapi select <代理组> <节点名>}
    local node=${2:?用法: clashapi select <代理组> <节点名>}
    _api_check || return 1

    local encoded_group
    encoded_group=$(printf '%s' "$group" | jq -sRr @uri)
    local response
    response=$(_api_curl PUT "/proxies/${encoded_group}" -d "{\"name\": \"${node}\"}" -w '\n%{http_code}')
    local http_code
    http_code=$(echo "$response" | tail -1)

    if [ "$http_code" = "204" ]; then
        echo "已切换: ${group} → ${node}"
    else
        echo "切换失败 (HTTP ${http_code}): 请检查代理组和节点名称是否正确" >&2
        return 1
    fi
}

# 测试单个节点延迟
clashapi_delay() {
    local node=${1:?用法: clashapi delay <节点名> [超时ms]}
    local timeout=${2:-5000}
    _api_check || return 1
    _require_jq || return 1

    local encoded_node
    encoded_node=$(printf '%s' "$node" | jq -sRr @uri)
    local url="http://www.gstatic.com/generate_204"
    _api_curl GET "/proxies/${encoded_node}/delay?timeout=${timeout}&url=${url}" | jq .
}

# 批量测速代理组
clashapi_benchmark() {
    local group=${1:-Proxies}
    local timeout=${2:-5000}
    _api_check || return 1
    _require_jq || return 1

    local encoded_group
    encoded_group=$(printf '%s' "$group" | jq -sRr @uri)
    local url="http://www.gstatic.com/generate_204"
    echo "正在测速代理组: ${group} ..."
    _api_curl GET "/group/${encoded_group}/delay?url=${url}&timeout=${timeout}" | jq -r '
        to_entries | sort_by(.value) | .[]
        | "\(.value)ms\t\(.key)"
    '
}

# 自动选择延迟最低的节点
clashapi_fastest() {
    local group=${1:-Proxies}
    local timeout=${2:-5000}
    _api_check || return 1
    _require_jq || return 1

    local encoded_group
    encoded_group=$(printf '%s' "$group" | jq -sRr @uri)
    local url="http://www.gstatic.com/generate_204"
    echo "正在测速代理组: ${group} ..."
    local result
    result=$(_api_curl GET "/group/${encoded_group}/delay?url=${url}&timeout=${timeout}")

    local best
    best=$(echo "$result" | jq -r 'to_entries | sort_by(.value) | .[0].key')
    local best_delay
    best_delay=$(echo "$result" | jq -r 'to_entries | sort_by(.value) | .[0].value')

    if [ -z "$best" ] || [ "$best" = "null" ]; then
        echo "测速失败: 没有可用节点" >&2
        return 1
    fi

    echo "最低延迟: ${best} (${best_delay}ms)"
    clashapi_select "$group" "$best"
}

# ====== 流量与连接 ======

# 查看活跃连接
clashapi_connections() {
    _api_check || return 1
    _require_jq || return 1
    _api_curl GET /connections | jq -r '
        "活跃连接数: \(.connections | length)\n",
        (.connections[]
         | "\(.metadata.host // .metadata.destinationIP):\(.metadata.destinationPort)\t\(.chains | join(" → "))\t\(.rule)")
    '
}

# 关闭所有连接
clashapi_flush() {
    _api_check || return 1
    _api_curl DELETE /connections
    echo "已关闭所有连接"
}

# ====== 配置管理 ======

# 查看运行配置
clashapi_config() {
    _api_check || return 1
    _require_jq || return 1
    _api_curl GET /configs | jq .
}

# 切换运行模式
clashapi_mode() {
    local mode=${1:?用法: clashapi mode <rule|global|direct>}
    _api_check || return 1

    case "$mode" in
    rule | global | direct) ;;
    *)
        echo "错误: 模式必须是 rule / global / direct" >&2
        return 1
        ;;
    esac

    _api_curl PATCH /configs -d "{\"mode\": \"${mode}\"}"
    echo "已切换模式: ${mode}"
}

# 重载配置
clashapi_reload() {
    local config_path="${MIHOMO_CONFIG_RUNTIME:-$HOME/tools/mihomo/runtime.yaml}"
    _api_check || return 1
    _api_curl PUT /configs -d "{\"path\": \"${config_path}\"}"
    echo "配置已重载"
}

# ====== 规则查询 ======

clashapi_rules() {
    _api_check || return 1
    _require_jq || return 1

    local keyword=$1
    if [ -n "$keyword" ]; then
        _api_curl GET /rules | jq -r --arg kw "$keyword" '
            .rules[] | select(.payload | test($kw; "i"))
            | "\(.type)\t\(.payload)\t→ \(.proxy)"
        '
    else
        local result
        result=$(_api_curl GET /rules)
        local count
        count=$(echo "$result" | jq '.rules | length')
        echo "规则总数: ${count}"
        echo "$result" | jq -r '.rules[:20][] | "\(.type)\t\(.payload)\t→ \(.proxy)"'
        [ "$count" -gt 20 ] && echo "... (仅显示前 20 条，使用 clashapi rules <关键词> 过滤)"
    fi
}

# ====== DNS ======

clashapi_dns() {
    local domain=${1:?用法: clashapi dns <域名>}
    local type=${2:-A}
    _api_check || return 1
    _require_jq || return 1
    _api_curl GET "/dns/query?name=${domain}&type=${type}" | jq .
}

# ====== 日志 ======

clashapi_log() {
    local level=${1:-info}
    _api_check || return 1
    echo "实时日志 (${level})，按 Ctrl+C 退出..."
    _api_curl GET "/logs?level=${level}"
}

# ====== 版本信息 ======

clashapi_version() {
    _api_check || return 1
    _require_jq || return 1
    _api_curl GET /version | jq .
}

# ====== 主入口 ======

clashapi() {
    _api_init

    local cmd=${1:-help}
    shift 2>/dev/null || true

    case "$cmd" in
    groups)     clashapi_groups "$@" ;;
    nodes)      clashapi_nodes "$@" ;;
    now)        clashapi_now "$@" ;;
    select)     clashapi_select "$@" ;;
    delay)      clashapi_delay "$@" ;;
    benchmark)  clashapi_benchmark "$@" ;;
    fastest)    clashapi_fastest "$@" ;;
    connections) clashapi_connections "$@" ;;
    flush)      clashapi_flush "$@" ;;
    config)     clashapi_config "$@" ;;
    mode)       clashapi_mode "$@" ;;
    reload)     clashapi_reload "$@" ;;
    rules)      clashapi_rules "$@" ;;
    dns)        clashapi_dns "$@" ;;
    log)        clashapi_log "$@" ;;
    version)    clashapi_version "$@" ;;
    help | *)
        cat <<'EOF'
用法: clashapi <命令> [参数]

代理节点:
    groups                      查看所有代理组及当前节点
    nodes   [组名]              查看代理组的可用节点 (默认: Proxies)
    now     [组名]              查看当前选中的节点
    select  <组名> <节点名>     切换节点
    delay   <节点名> [超时ms]   测试节点延迟
    benchmark [组名] [超时ms]   批量测速代理组 (默认: Proxies)
    fastest [组名] [超时ms]     自动选择延迟最低的节点

流量连接:
    connections                 查看活跃连接
    flush                       关闭所有连接

配置管理:
    config                      查看运行配置
    mode    <rule|global|direct> 切换运行模式
    reload                      重载配置文件

规则查询:
    rules   [关键词]            查看规则 (可按关键词过滤)

其他:
    dns     <域名> [类型]       DNS 查询 (类型默认: A)
    log     [级别]              实时日志 (级别: debug/info/warning/error)
    version                     查看内核版本

示例:
    clashapi groups                     # 查看所有代理组
    clashapi select Proxies 香港-01     # 切换 Proxies 组到香港-01
    clashapi fastest YouTube            # YouTube 组自动选最快节点
    clashapi rules google               # 查找包含 google 的规则
    clashapi mode global                # 切换为全局代理模式
EOF
        ;;
    esac
}
