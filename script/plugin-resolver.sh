#!/bin/bash
#========================================================================================================================
# OpenWrt 插件解析器 - 重构版
# 功能: 插件验证、冲突检测、依赖解析、feeds配置生成
# 版本: 2.0.0
#========================================================================================================================

set -euo pipefail

# 脚本版本和路径
readonly RESOLVER_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PLUGIN_CONFIG_DIR="$PROJECT_ROOT/config/plugin-mappings"

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
log_info() { echo -e "${BLUE}[PLUGIN-RESOLVER]${NC} $1"; }
log_success() { echo -e "${GREEN}[PLUGIN-RESOLVER]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[PLUGIN-RESOLVER]${NC} $1"; }
log_error() { echo -e "${RED}[PLUGIN-RESOLVER]${NC} $1" >&2; }
log_debug() { [ "$VERBOSE" = true ] && echo -e "${CYAN}[PLUGIN-RESOLVER-DEBUG]${NC} $1"; }

#========================================================================================================================
# 插件数据库 - 完整的插件信息
#========================================================================================================================

# 插件信息数据库
declare -A PLUGIN_INFO

# 初始化插件数据库
init_plugin_database() {
    log_debug "初始化插件数据库..."
    
    # 代理类插件
    PLUGIN_INFO["luci-app-ssr-plus,name"]="ShadowSocksR Plus+"
    PLUGIN_INFO["luci-app-ssr-plus,category"]="proxy"
    PLUGIN_INFO["luci-app-ssr-plus,feeds"]="src-git helloworld https://github.com/fw876/helloworld"
    PLUGIN_INFO["luci-app-ssr-plus,dependencies"]="shadowsocksr-libev-ssr-local,shadowsocksr-libev-ssr-redir,v2ray-core,trojan"
    PLUGIN_INFO["luci-app-ssr-plus,conflicts"]="luci-app-passwall,luci-app-openclash"
    PLUGIN_INFO["luci-app-ssr-plus,arch_support"]="x86_64,mipsel,aarch64"
    PLUGIN_INFO["luci-app-ssr-plus,resource_usage"]="medium"
    
    PLUGIN_INFO["luci-app-passwall,name"]="PassWall"
    PLUGIN_INFO["luci-app-passwall,category"]="proxy"
    PLUGIN_INFO["luci-app-passwall,feeds"]="src-git passwall https://github.com/xiaorouji/openwrt-passwall"
    PLUGIN_INFO["luci-app-passwall,dependencies"]="v2ray-core,xray-core,trojan-plus,brook"
    PLUGIN_INFO["luci-app-passwall,conflicts"]="luci-app-ssr-plus,luci-app-passwall2"
    PLUGIN_INFO["luci-app-passwall,arch_support"]="x86_64,mipsel,aarch64"
    PLUGIN_INFO["luci-app-passwall,resource_usage"]="high"
    
    PLUGIN_INFO["luci-app-passwall2,name"]="PassWall 2"
    PLUGIN_INFO["luci-app-passwall2,category"]="proxy"
    PLUGIN_INFO["luci-app-passwall2,feeds"]="src-git passwall2 https://github.com/xiaorouji/openwrt-passwall2"
    PLUGIN_INFO["luci-app-passwall2,dependencies"]="v2ray-core,xray-core,sing-box,hysteria"
    PLUGIN_INFO["luci-app-passwall2,conflicts"]="luci-app-passwall"
    PLUGIN_INFO["luci-app-passwall2,arch_support"]="x86_64,mipsel,aarch64"
    PLUGIN_INFO["luci-app-passwall2,resource_usage"]="high"
    
    PLUGIN_INFO["luci-app-openclash,name"]="OpenClash"
    PLUGIN_INFO["luci-app-openclash,category"]="proxy"
    PLUGIN_INFO["luci-app-openclash,feeds"]="src-git openclash https://github.com/vernesong/OpenClash"
    PLUGIN_INFO["luci-app-openclash,dependencies"]="clash,iptables-mod-tproxy,kmod-tun"
    PLUGIN_INFO["luci-app-openclash,conflicts"]="luci-app-ssr-plus"
    PLUGIN_INFO["luci-app-openclash,arch_support"]="x86_64,aarch64"
    PLUGIN_INFO["luci-app-openclash,resource_usage"]="high"
    
    # 系统管理插件
    PLUGIN_INFO["luci-app-dockerman,name"]="Docker管理器"
    PLUGIN_INFO["luci-app-dockerman,category"]="system"
    PLUGIN_INFO["luci-app-dockerman,feeds"]="default"
    PLUGIN_INFO["luci-app-dockerman,dependencies"]="docker,dockerd,docker-compose,cgroupfs-mount"
    PLUGIN_INFO["luci-app-dockerman,conflicts"]=""
    PLUGIN_INFO["luci-app-dockerman,arch_support"]="x86_64,aarch64"
    PLUGIN_INFO["luci-app-dockerman,resource_usage"]="very_high"
    
    PLUGIN_INFO["luci-app-aria2,name"]="Aria2下载器"
    PLUGIN_INFO["luci-app-aria2,category"]="download"
    PLUGIN_INFO["luci-app-aria2,feeds"]="default"
    PLUGIN_INFO["luci-app-aria2,dependencies"]="aria2,ariang"
    PLUGIN_INFO["luci-app-aria2,conflicts"]=""
    PLUGIN_INFO["luci-app-aria2,arch_support"]="x86_64,mipsel,aarch64"
    PLUGIN_INFO["luci-app-aria2,resource_usage"]="low"
    
    PLUGIN_INFO["luci-app-qbittorrent,name"]="qBittorrent"
    PLUGIN_INFO["luci-app-qbittorrent,category"]="download"
    PLUGIN_INFO["luci-app-qbittorrent,feeds"]="default"
    PLUGIN_INFO["luci-app-qbittorrent,dependencies"]="qBittorrent-Enhanced-Edition,qt5-core,qt5-network"
    PLUGIN_INFO["luci-app-qbittorrent,conflicts"]=""
    PLUGIN_INFO["luci-app-qbittorrent,arch_support"]="x86_64,aarch64"
    PLUGIN_INFO["luci-app-qbittorrent,resource_usage"]="high"
    
    # 网络工具插件
    PLUGIN_INFO["luci-app-adguardhome,name"]="AdGuard Home"
    PLUGIN_INFO["luci-app-adguardhome,category"]="network"
    PLUGIN_INFO["luci-app-adguardhome,feeds"]="default"
    PLUGIN_INFO["luci-app-adguardhome,dependencies"]="adguardhome"
    PLUGIN_INFO["luci-app-adguardhome,conflicts"]="luci-app-adblock"
    PLUGIN_INFO["luci-app-adguardhome,arch_support"]="x86_64,mipsel,aarch64"
    PLUGIN_INFO["luci-app-adguardhome,resource_usage"]="medium"
    
    PLUGIN_INFO["luci-app-smartdns,name"]="SmartDNS"
    PLUGIN_INFO["luci-app-smartdns,category"]="network"
    PLUGIN_INFO["luci-app-smartdns,feeds"]="default"
    PLUGIN_INFO["luci-app-smartdns,dependencies"]="smartdns"
    PLUGIN_INFO["luci-app-smartdns,conflicts"]=""
    PLUGIN_INFO["luci-app-smartdns,arch_support"]="x86_64,mipsel,aarch64"
    PLUGIN_INFO["luci-app-smartdns,resource_usage"]="low"
    
    # 主题插件
    PLUGIN_INFO["luci-theme-argon,name"]="Argon主题"
    PLUGIN_INFO["luci-theme-argon,category"]="theme"
    PLUGIN_INFO["luci-theme-argon,feeds"]="src-git argon https://github.com/jerrykuku/luci-theme-argon"
    PLUGIN_INFO["luci-theme-argon,dependencies"]=""
    PLUGIN_INFO["luci-theme-argon,conflicts"]=""
    PLUGIN_INFO["luci-theme-argon,arch_support"]="x86_64,mipsel,aarch64"
    PLUGIN_INFO["luci-theme-argon,resource_usage"]="very_low"
    
    PLUGIN_INFO["luci-theme-material,name"]="Material主题"
    PLUGIN_INFO["luci-theme-material,category"]="theme"
    PLUGIN_INFO["luci-theme-material,feeds"]="default"
    PLUGIN_INFO["luci-theme-material,dependencies"]=""
    PLUGIN_INFO["luci-theme-material,conflicts"]=""
    PLUGIN_INFO["luci-theme-material,arch_support"]="x86_64,mipsel,aarch64"
    PLUGIN_INFO["luci-theme-material,resource_usage"]="very_low"
    
    log_debug "插件数据库初始化完成"
}

# 获取插件信息
get_plugin_info() {
    local plugin="$1"
    local info_type="$2"
    
    local key="${plugin},${info_type}"
    echo "${PLUGIN_INFO[$key]:-}"
}

# 检查插件是否存在
is_plugin_known() {
    local plugin="$1"
    
    local plugin_name=$(get_plugin_info "$plugin" "name")
    if [ -n "$plugin_name" ]; then
        return 0
    else
        return 1
    fi
}

#========================================================================================================================
# 插件验证功能
#========================================================================================================================

# 验证插件列表
operation_validate() {
    local plugins=""
    local device=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --plugins)
                plugins="$2"
                shift 2
                ;;
            --device)
                device="$2"
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
    
    log_info "🔍 验证插件列表..."
    
    # 初始化插件数据库
    init_plugin_database
    
    # 解析插件列表
    IFS=',' read -ra plugin_array <<< "$plugins"
    
    local valid_plugins=()
    local invalid_plugins=()
    local warnings=()
    
    # 验证每个插件
    for plugin in "${plugin_array[@]}"; do
        plugin=$(echo "$plugin" | xargs)  # 去除空白字符
        
        if [ -n "$plugin" ]; then
            if is_plugin_known "$plugin"; then
                valid_plugins+=("$plugin")
                log_debug "✅ 插件有效: $plugin"
                
                # 检查架构支持
                if [ -n "$device" ]; then
                    check_plugin_arch_support "$plugin" "$device" warnings
                fi
            else
                invalid_plugins+=("$plugin")
                log_warning "❓ 未知插件: $plugin"
            fi
        fi
    done
    
    # 检查插件冲突
    local conflicts=$(check_plugin_conflicts "${valid_plugins[@]}")
    
    # 显示验证结果
    show_validation_results "${valid_plugins[@]}" "${invalid_plugins[@]}" "$conflicts" "${warnings[@]}"
    
    # 返回结果
    if [ ${#invalid_plugins[@]} -eq 0 ] && [ -z "$conflicts" ]; then
        log_success "插件验证通过"
        return 0
    else
        log_warning "插件验证发现问题"
        return 1
    fi
}

# 检查插件架构支持
check_plugin_arch_support() {
    local plugin="$1"
    local device="$2"
    local -n warnings_ref="$3"
    
    # 获取设备架构
    local device_arch=""
    if command -v "$SCRIPT_DIR/device-adapter.sh" &> /dev/null; then
        device_arch=$("$SCRIPT_DIR/device-adapter.sh" get-arch --device "$device" 2>/dev/null || echo "")
    fi
    
    if [ -n "$device_arch" ]; then
        local arch_support=$(get_plugin_info "$plugin" "arch_support")
        
        if [ -n "$arch_support" ] && [[ "$arch_support" != *"$device_arch"* ]]; then
            warnings_ref+=("插件 $plugin 可能不支持 $device_arch 架构")
        fi
    fi
}

# 检查插件冲突
check_plugin_conflicts() {
    local plugins=("$@")
    local conflicts=""
    
    log_debug "检查插件冲突..."
    
    for i in "${!plugins[@]}"; do
        local plugin1="${plugins[$i]}"
        local plugin1_conflicts=$(get_plugin_info "$plugin1" "conflicts")
        
        if [ -n "$plugin1_conflicts" ]; then
            for j in "${!plugins[@]}"; do
                if [ "$i" -ne "$j" ]; then
                    local plugin2="${plugins[$j]}"
                    
                    if [[ "$plugin1_conflicts" == *"$plugin2"* ]]; then
                        conflicts+="$plugin1 与 $plugin2 冲突; "
                    fi
                fi
            done
        fi
    done
    
    echo "$conflicts"
}

# 显示验证结果
show_validation_results() {
    local valid_plugins=("${@:1:$((($#-3)))}")
    local invalid_plugins_start=$(($#-2))
    local invalid_plugins=("${@:$invalid_plugins_start:1}")
    local conflicts="${@:$#-1:1}"
    local warnings=("${@:$#}")
    
    echo ""
    log_info "📋 插件验证结果:"
    
    # 有效插件
    if [ ${#valid_plugins[@]} -gt 0 ]; then
        echo "  ✅ 有效插件 (${#valid_plugins[@]}个):"
        for plugin in "${valid_plugins[@]}"; do
            local plugin_name=$(get_plugin_info "$plugin" "name")
            local plugin_category=$(get_plugin_info "$plugin" "category")
            echo "    - $plugin (${plugin_name:-未知} / $plugin_category)"
        done
    fi
    
    # 无效插件
    if [ ${#invalid_plugins[@]} -gt 0 ]; then
        echo "  ❓ 未知插件 (${#invalid_plugins[@]}个):"
        for plugin in "${invalid_plugins[@]}"; do
            echo "    - $plugin"
        done
    fi
    
    # 冲突检测
    if [ -n "$conflicts" ]; then
        echo "  ⚠️ 检测到冲突:"
        echo "    $conflicts"
    fi
    
    # 警告信息
    if [ ${#warnings[@]} -gt 0 ]; then
        echo "  ⚠️ 警告信息:"
        for warning in "${warnings[@]}"; do
            echo "    - $warning"
        done
    fi
    
    echo ""
}

#========================================================================================================================
# feeds.conf.default 生成功能
#========================================================================================================================

# 生成feeds配置
operation_generate_feeds() {
    local plugins=""
    local source_branch=""
    local output_file="feeds.conf.default"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --plugins)
                plugins="$2"
                shift 2
                ;;
            --source)
                source_branch="$2"
                shift 2
                ;;
            --output)
                output_file="$2"
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
    
    log_info "🔧 生成feeds配置文件..."
    
    # 初始化插件数据库
    init_plugin_database
    
    # 生成feeds配置
    generate_feeds_config "$plugins" "$source_branch" "$output_file"
    
    log_success "feeds配置生成完成: $output_file"
    return 0
}

# 生成feeds配置文件
generate_feeds_config() {
    local plugins="$1"
    local source_branch="$2"
    local output_file="$3"
    
    log_debug "生成feeds配置: 源码=$source_branch"
    
    # 获取基础feeds配置
    local base_feeds=$(get_base_feeds_config "$source_branch")
    
    # 收集插件特定的feeds
    local plugin_feeds=""
    if [ -n "$plugins" ]; then
        plugin_feeds=$(collect_plugin_feeds "$plugins")
    fi
    
    # 生成最终配置
    {
        echo "# ========================================================"
        echo "# OpenWrt feeds.conf.default"
        echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# 源码分支: ${source_branch:-默认}"
        echo "# 插件数量: $(echo "$plugins" | tr ',' '\n' | wc -l)"
        echo "# ========================================================"
        echo ""
        
        echo "# 基础 feeds 源"
        echo "$base_feeds"
        
        if [ -n "$plugin_feeds" ]; then
            echo ""
            echo "# 插件特定 feeds 源"
            echo "$plugin_feeds"
        fi
        
        echo ""
        echo "# feeds 配置生成完成"
        echo "# ========================================================"
        
    } > "$output_file"
    
    log_debug "feeds配置已写入: $output_file"
}

# 获取基础feeds配置
get_base_feeds_config() {
    local source_branch="$1"
    
    case "$source_branch" in
        "lede-master")
            cat << 'EOF'
src-git packages https://github.com/coolsnowwolf/packages
src-git luci https://github.com/coolsnowwolf/luci
src-git routing https://git.openwrt.org/feed/routing.git
src-git telephony https://git.openwrt.org/feed/telephony.git
EOF
            ;;
        "openwrt-main")
            cat << 'EOF'
src-git packages https://git.openwrt.org/feed/packages.git
src-git luci https://git.openwrt.org/project/luci.git
src-git routing https://git.openwrt.org/feed/routing.git
src-git telephony https://git.openwrt.org/feed/telephony.git
EOF
            ;;
        "immortalwrt-master")
            cat << 'EOF'
src-git packages https://github.com/immortalwrt/packages
src-git luci https://github.com/immortalwrt/luci
src-git routing https://git.openwrt.org/feed/routing.git
src-git telephony https://git.openwrt.org/feed/telephony.git
EOF
            ;;
        *)
            # 默认使用OpenWrt官方源
            cat << 'EOF'
src-git packages https://git.openwrt.org/feed/packages.git
src-git luci https://git.openwrt.org/project/luci.git
src-git routing https://git.openwrt.org/feed/routing.git
src-git telephony https://git.openwrt.org/feed/telephony.git
EOF
            ;;
    esac
}

# 收集插件feeds
collect_plugin_feeds() {
    local plugins="$1"
    local feeds_set=""
    
    log_debug "收集插件feeds: $plugins"
    
    # 解析插件列表
    IFS=',' read -ra plugin_array <<< "$plugins"
    
    for plugin in "${plugin_array[@]}"; do
        plugin=$(echo "$plugin" | xargs)
        
        if [ -n "$plugin" ] && is_plugin_known "$plugin"; then
            local plugin_feeds=$(get_plugin_info "$plugin" "feeds")
            
            if [ -n "$plugin_feeds" ] && [ "$plugin_feeds" != "default" ]; then
                # 检查是否已经添加过这个feeds
                if [[ "$feeds_set" != *"$plugin_feeds"* ]]; then
                    feeds_set+="$plugin_feeds"$'\n'
                    log_debug "添加feeds: $plugin_feeds"
                fi
            fi
        fi
    done
    
    echo "$feeds_set"
}

#========================================================================================================================
# 插件信息查询功能
#========================================================================================================================

# 显示插件信息
operation_info() {
    local plugin=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --plugin)
                plugin="$2"
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
    
    if [ -z "$plugin" ]; then
        log_error "请指定插件名称"
        return 1
    fi
    
    # 初始化插件数据库
    init_plugin_database
    
    # 显示插件详细信息
    show_plugin_details "$plugin"
    
    return 0
}

# 显示插件详细信息
show_plugin_details() {
    local plugin="$1"
    
    if ! is_plugin_known "$plugin"; then
        log_error "未知插件: $plugin"
        return 1
    fi
    
    log_info "📱 插件详细信息: $plugin"
    echo ""
    echo "  名称: $(get_plugin_info "$plugin" "name")"
    echo "  分类: $(get_plugin_info "$plugin" "category")"
    echo "  feeds源: $(get_plugin_info "$plugin" "feeds")"
    echo "  依赖包: $(get_plugin_info "$plugin" "dependencies")"
    echo "  冲突插件: $(get_plugin_info "$plugin" "conflicts")"
    echo "  架构支持: $(get_plugin_info "$plugin" "arch_support")"
    echo "  资源消耗: $(get_plugin_info "$plugin" "resource_usage")"
    echo ""
}

# 列出插件
operation_list() {
    local category=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --category)
                category="$2"
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
    
    # 初始化插件数据库
    init_plugin_database
    
    log_info "📋 可用插件列表:"
    
    # 列出插件
    list_plugins_by_category "$category"
    
    return 0
}

# 按分类列出插件
list_plugins_by_category() {
    local filter_category="$1"
    
    echo ""
    
    # 定义分类
    local categories=("proxy" "system" "download" "network" "theme")
    local category_names=("代理工具" "系统管理" "下载工具" "网络工具" "主题美化")
    
    for i in "${!categories[@]}"; do
        local cat="${categories[$i]}"
        local cat_name="${category_names[$i]}"
        
        # 如果指定了分类过滤器，只显示匹配的分类
        if [ -n "$filter_category" ] && [ "$filter_category" != "$cat" ]; then
            continue
        fi
        
        echo "🔷 $cat_name ($cat):"
        
        # 遍历所有插件，找到属于当前分类的
        for key in "${!PLUGIN_INFO[@]}"; do
            if [[ "$key" == *",category" ]]; then
                local plugin_id="${key%,category}"
                local plugin_category="${PLUGIN_INFO[$key]}"
                
                if [ "$plugin_category" = "$cat" ]; then
                    local plugin_name=$(get_plugin_info "$plugin_id" "name")
                    local resource_usage=$(get_plugin_info "$plugin_id" "resource_usage")
                    
                    echo "  $plugin_id - $plugin_name (资源: $resource_usage)"
                fi
            fi
        done
        
        echo ""
    done
}

#========================================================================================================================
# 帮助信息和主函数
#========================================================================================================================

show_help() {
    cat << EOF
${CYAN}OpenWrt 插件解析器 v${RESOLVER_VERSION}${NC}

${CYAN}使用方法:${NC}
  $0 <操作> [选项...]

${CYAN}操作:${NC}
  validate              验证插件列表
  generate-feeds        生成feeds.conf.default文件
  info                  显示插件详细信息
  list                  列出可用插件

${CYAN}选项:${NC}
  --plugins <插件列表>  插件列表（逗号分隔）
  --device <设备>       目标设备型号
  --source <分支>       源码分支
  --output <文件>       输出文件路径
  --plugin <插件名>     单个插件名称
  --category <分类>     插件分类过滤
  --verbose             详细输出
  -h, --help            显示帮助信息
  --version             显示版本信息

${CYAN}示例:${NC}
  # 验证插件列表
  $0 validate --plugins "luci-app-ssr-plus,luci-theme-argon" --device x86_64 --verbose
  
  # 生成feeds配置
  $0 generate-feeds --plugins "luci-app-passwall,luci-app-adguardhome" --source lede-master --output feeds.conf.default
  
  # 查看插件信息
  $0 info --plugin luci-app-ssr-plus
  
  # 列出代理类插件
  $0 list --category proxy
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
        validate|generate-feeds|info|list)
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
    
    # 创建插件配置目录
    mkdir -p "$PLUGIN_CONFIG_DIR"
    
    # 执行操作
    case "$operation" in
        "validate")
            operation_validate "$@"
            ;;
        "generate-feeds")
            operation_generate_feeds "$@"
            ;;
        "info")
            operation_info "$@"
            ;;
        "list")
            operation_list "$@"
            ;;
    esac
}

# 检查脚本是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi