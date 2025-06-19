#!/bin/bash
#========================================================================================================================
# OpenWrt 插件解析器 - 简化版本
# 功能: 插件验证、解析、冲突检测
# 版本: 2.0.1 (简化版本)
#========================================================================================================================

set -eo pipefail

# 脚本版本和路径
readonly RESOLVER_VERSION="2.0.1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# 全局变量
VERBOSE=false

#========================================================================================================================
# 基础工具函数
#========================================================================================================================

# 日志函数
log_info() { echo -e "${BLUE}[PLUGIN-RESOLVER]${NC} $1" || true; }
log_success() { echo -e "${GREEN}[PLUGIN-RESOLVER]${NC} $1" || true; }
log_warning() { echo -e "${YELLOW}[PLUGIN-RESOLVER]${NC} $1" || true; }
log_error() { echo -e "${RED}[PLUGIN-RESOLVER]${NC} $1" >&2 || true; }
log_debug() { [ "$VERBOSE" = true ] && echo -e "${CYAN}[PLUGIN-RESOLVER-DEBUG]${NC} $1" || true; }

#========================================================================================================================
# 插件信息数据库 - 简化版本
#========================================================================================================================

# 常见插件列表 - 使用简单字符串匹配
KNOWN_PLUGINS="
luci-app-ssr-plus
luci-app-passwall
luci-app-openclash
luci-app-bypass
luci-app-vssr
luci-app-shadowsocksr
luci-app-v2ray-server
luci-app-trojan-server
luci-app-adbyby-plus
luci-app-adguardhome
luci-app-smartdns
luci-app-mosdns
luci-app-ddns
luci-app-upnp
luci-app-wol
luci-app-nlbwmon
luci-app-netdata
luci-app-aria2
luci-app-transmission
luci-app-qbittorrent
luci-app-dockerman
luci-app-docker
luci-app-frpc
luci-app-frps
luci-app-nps
luci-app-zerotier
luci-app-wireguard
luci-app-softethervpn
luci-app-openvpn-server
luci-app-ipsec-server
luci-app-pptp-server
luci-app-webadmin
luci-app-ttyd
luci-app-filetransfer
luci-app-samba4
luci-app-minidlna
luci-app-hd-idle
luci-app-wifischedule
luci-app-guest-wifi
luci-app-accesscontrol
luci-app-advanced-reboot
luci-app-autoreboot
luci-app-ramfree
luci-app-cpufreq
luci-app-turboacc
luci-theme-argon
luci-theme-netgear
luci-theme-bootstrap
luci-theme-material
luci-theme-openwrt-2020
luci-i18n-base-zh-cn
luci-i18n-firewall-zh-cn
luci-i18n-opkg-zh-cn
"

# 检查插件是否已知
is_plugin_known() {
    local plugin="$1"
    
    if [ -z "$plugin" ]; then
        return 1
    fi
    
    # 简单的字符串匹配
    if echo "$KNOWN_PLUGINS" | grep -q "^$plugin$"; then
        return 0
    else
        return 1
    fi
}

#========================================================================================================================
# 插件验证功能
#========================================================================================================================

# 验证插件列表 - 主要验证函数
operation_validate() {
    local plugins=""
    local device=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --plugins)
                plugins="${2:-}"
                shift 2
                ;;
            --device)
                device="${2:-}"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            *)
                log_error "未知参数: $1"
                return 1
                ;;
        esac
    done
    
    # 参数检查
    if [ -z "$plugins" ]; then
        log_error "请指定插件列表"
        return 1
    fi
    
    log_info "🔍 验证插件列表..."
    log_debug "插件列表: $plugins"
    log_debug "目标设备: ${device:-未指定}"
    
    # 解析插件列表
    local plugin_count=0
    local valid_plugins=()
    local unknown_plugins=()
    local warnings=()
    
    # 使用逗号分割插件列表
    IFS=',' read -ra plugin_array <<< "$plugins"
    
    for plugin in "${plugin_array[@]}"; do
        # 去除前后空白字符
        plugin=$(echo "$plugin" | xargs 2>/dev/null || echo "$plugin")
        
        if [ -n "$plugin" ]; then
            plugin_count=$((plugin_count + 1))
            
            if is_plugin_known "$plugin"; then
                valid_plugins+=("$plugin")
                log_debug "✅ 插件有效: $plugin"
            else
                unknown_plugins+=("$plugin")
                log_debug "❓ 未知插件: $plugin"
            fi
        fi
    done
    
    # 基本架构兼容性检查
    if [ -n "$device" ]; then
        check_basic_compatibility "$device" "${valid_plugins[@]}" warnings
    fi
    
    # 显示验证结果
    show_validation_results "$plugin_count" "${valid_plugins[@]}" "${unknown_plugins[@]}" "${warnings[@]}"
    
    # 返回结果
    if [ ${#unknown_plugins[@]} -eq 0 ]; then
        log_success "插件验证完成，所有插件都已识别"
        return 0
    else
        log_warning "插件验证完成，发现 ${#unknown_plugins[@]} 个未知插件"
        return 0  # 仍然返回成功，允许继续构建
    fi
}

# 基本兼容性检查
check_basic_compatibility() {
    local device="$1"
    shift
    local plugins=("$@")
    local -n warnings_array=$1  # 最后一个参数是warnings数组的引用
    
    # 移除warnings数组引用，获取实际插件列表
    unset 'plugins[-1]'
    
    log_debug "检查基本兼容性: 设备=$device, 插件数=${#plugins[@]}"
    
    # 简单的架构兼容性检查
    case "$device" in
        "xiaomi_4a_gigabit"|"newifi_d2")
            # MIPS设备资源有限
            if [ ${#plugins[@]} -gt 15 ]; then
                warnings_array+=("MIPS设备插件数量较多(${#plugins[@]})，可能影响性能")
            fi
            
            # 检查资源密集型插件
            for plugin in "${plugins[@]}"; do
                case "$plugin" in
                    "luci-app-dockerman"|"luci-app-docker")
                        warnings_array+=("Docker在MIPS架构上支持有限")
                        ;;
                    "luci-app-netdata")
                        warnings_array+=("Netdata在低内存设备上可能占用过多资源")
                        ;;
                esac
            done
            ;;
        "x86_64")
            # x86_64设备兼容性好
            log_debug "x86_64设备兼容性良好"
            ;;
        *)
            log_debug "未知设备类型，跳过特定兼容性检查"
            ;;
    esac
}

# 显示验证结果
show_validation_results() {
    local plugin_count="$1"
    shift
    local valid_plugins=("$@")
    
    # 找到unknown_plugins的开始位置
    local unknown_start=-1
    local warnings_start=-1
    
    for i in "${!valid_plugins[@]}"; do
        if [ "${valid_plugins[$i]}" = "---UNKNOWN---" ]; then
            unknown_start=$((i + 1))
            break
        fi
    done
    
    for i in "${!valid_plugins[@]}"; do
        if [ "${valid_plugins[$i]}" = "---WARNINGS---" ]; then
            warnings_start=$((i + 1))
            break
        fi
    done
    
    # 提取实际的valid_plugins
    local actual_valid=()
    local unknown_plugins=()
    local warnings=()
    
    if [ $unknown_start -gt 0 ]; then
        actual_valid=("${valid_plugins[@]:0:$((unknown_start-1))}")
        if [ $warnings_start -gt 0 ]; then
            unknown_plugins=("${valid_plugins[@]:$unknown_start:$((warnings_start-unknown_start-1))}")
            warnings=("${valid_plugins[@]:$warnings_start}")
        else
            unknown_plugins=("${valid_plugins[@]:$unknown_start}")
        fi
    else
        actual_valid=("${valid_plugins[@]}")
    fi
    
    # 由于参数传递的复杂性，使用简化的显示方式
    log_info "插件验证结果:"
    echo "  总插件数: $plugin_count"
    echo "  已识别插件: ${#actual_valid[@]}"
    
    if [ ${#actual_valid[@]} -gt 0 ]; then
        echo "  有效插件列表:"
        for plugin in "${actual_valid[@]}"; do
            [ "$plugin" != "---UNKNOWN---" ] && [ "$plugin" != "---WARNINGS---" ] && echo "    - $plugin"
        done
    fi
    
    if [ ${#warnings[@]} -gt 0 ]; then
        echo "  ⚠️  兼容性警告:"
        for warning in "${warnings[@]}"; do
            [ "$warning" != "---UNKNOWN---" ] && [ "$warning" != "---WARNINGS---" ] && echo "    - $warning"
        done
    fi
}

#========================================================================================================================
# 其他操作函数
#========================================================================================================================

# 解析插件配置
operation_resolve() {
    local plugins=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --plugins)
                plugins="${2:-}"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            *)
                log_error "未知参数: $1"
                return 1
                ;;
        esac
    done
    
    if [ -z "$plugins" ]; then
        log_error "请指定插件列表"
        return 1
    fi
    
    log_info "🔄 解析插件配置..."
    
    # 简单的插件解析，输出格式化的插件列表
    IFS=',' read -ra plugin_array <<< "$plugins"
    
    echo "# OpenWrt 插件配置"
    echo "# 生成时间: $(date)"
    echo ""
    
    for plugin in "${plugin_array[@]}"; do
        plugin=$(echo "$plugin" | xargs 2>/dev/null || echo "$plugin")
        if [ -n "$plugin" ]; then
            echo "CONFIG_PACKAGE_$plugin=y"
        fi
    done
    
    log_success "插件配置解析完成"
    return 0
}

# 列出已知插件
operation_list() {
    log_info "📦 已知插件列表:"
    
    echo ""
    echo "🔐 代理翻墙类:"
    echo "$KNOWN_PLUGINS" | grep -E "(ssr|passwall|openclash|bypass|v2ray|trojan|shadowsock)" | sed 's/^/  - /'
    
    echo ""
    echo "🛡️ 广告屏蔽类:"
    echo "$KNOWN_PLUGINS" | grep -E "(adbyby|adguard|smartdns|mosdns)" | sed 's/^/  - /'
    
    echo ""
    echo "📡 网络工具类:"
    echo "$KNOWN_PLUGINS" | grep -E "(ddns|upnp|wol|nlbwmon|netdata)" | sed 's/^/  - /'
    
    echo ""
    echo "📥 下载工具类:"
    echo "$KNOWN_PLUGINS" | grep -E "(aria2|transmission|qbittorrent)" | sed 's/^/  - /'
    
    echo ""
    echo "🐳 容器虚拟化:"
    echo "$KNOWN_PLUGINS" | grep -E "(docker)" | sed 's/^/  - /'
    
    echo ""
    echo "🔗 内网穿透类:"
    echo "$KNOWN_PLUGINS" | grep -E "(frp|nps|zerotier)" | sed 's/^/  - /'
    
    echo ""
    echo "🔒 VPN服务类:"
    echo "$KNOWN_PLUGINS" | grep -E "(wireguard|openvpn|ipsec|pptp|softether)" | sed 's/^/  - /'
    
    echo ""
    echo "🎨 主题界面类:"
    echo "$KNOWN_PLUGINS" | grep -E "(theme|i18n)" | sed 's/^/  - /'
    
    echo ""
    echo "⚙️ 系统工具类:"
    echo "$KNOWN_PLUGINS" | grep -E "(webadmin|ttyd|samba|reboot|ramfree|cpufreq|turboacc)" | sed 's/^/  - /'
    
    return 0
}

#========================================================================================================================
# 帮助信息和主函数
#========================================================================================================================

# 显示帮助信息
show_help() {
    cat << EOF
${CYAN}OpenWrt 插件解析器 v${RESOLVER_VERSION}${NC}

${CYAN}使用方法:${NC}
  $0 <操作> [选项...]

${CYAN}操作:${NC}
  validate              验证插件列表
  resolve               解析插件配置
  list                  列出已知插件

${CYAN}选项:${NC}
  --plugins <插件>      插件列表（逗号分隔）
  --device <设备>       目标设备
  --verbose             详细输出
  -h, --help            显示帮助信息
  --version             显示版本信息

${CYAN}示例:${NC}
  # 验证插件
  $0 validate --plugins "luci-app-ssr-plus,luci-theme-argon" --device x86_64
  
  # 解析插件配置
  $0 resolve --plugins "luci-app-ssr-plus,luci-app-adbyby-plus"
  
  # 列出已知插件
  $0 list

${CYAN}简化版本说明:${NC}
  - 提供基本的插件验证功能
  - 支持常见插件的识别和兼容性检查
  - 可扩展的插件数据库
EOF
}

# 主函数
main() {
    local operation=""
    
    # 检查参数
    if [ $# -eq 0 ]; then
        show_help
        exit 1
    fi
    
    # 解析操作
    case $1 in
        validate|resolve|list)
            operation="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --version)
            echo "OpenWrt 插件解析器 版本 $RESOLVER_VERSION"
            exit 0
            ;;
        *)
            log_error "未知操作: $1"
            show_help
            exit 1
            ;;
    esac
    
    # 执行操作
    case "$operation" in
        "validate")
            operation_validate "$@"
            ;;
        "resolve")
            operation_resolve "$@"
            ;;
        "list")
            operation_list "$@"
            ;;
        *)
            log_error "未实现的操作: $operation"
            exit 1
            ;;
    esac
}

# 检查脚本是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi