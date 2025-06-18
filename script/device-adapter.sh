#!/bin/bash
#========================================================================================================================
# OpenWrt 设备适配器
# 功能: 设备验证、架构适配、硬件特性检测
# 版本: 2.0.0
#========================================================================================================================

set -euo pipefail

# 脚本版本和路径
readonly ADAPTER_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly DEVICE_PROFILES_DIR="$PROJECT_ROOT/config/device-profiles"

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
log_info() { echo -e "${BLUE}[DEVICE-ADAPTER]${NC} $1"; }
log_success() { echo -e "${GREEN}[DEVICE-ADAPTER]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[DEVICE-ADAPTER]${NC} $1"; }
log_error() { echo -e "${RED}[DEVICE-ADAPTER]${NC} $1" >&2; }
log_debug() { [ "$VERBOSE" = true ] && echo -e "${CYAN}[DEVICE-ADAPTER-DEBUG]${NC} $1"; }

#========================================================================================================================
# 设备信息数据库
#========================================================================================================================

# 设备信息定义
declare -A DEVICE_INFO

# 初始化设备信息数据库
init_device_database() {
    log_debug "初始化设备数据库..."
    
    # X86_64 设备
    DEVICE_INFO["x86_64,name"]="X86 64位通用设备"
    DEVICE_INFO["x86_64,arch"]="x86_64"
    DEVICE_INFO["x86_64,target"]="x86/64"
    DEVICE_INFO["x86_64,cpu"]="Intel/AMD x86_64"
    DEVICE_INFO["x86_64,ram"]="512MB+"
    DEVICE_INFO["x86_64,flash"]="8GB+"
    DEVICE_INFO["x86_64,features"]="UEFI,KVM,Docker,USB3.0"
    DEVICE_INFO["x86_64,firmware_format"]="IMG,VMDK,EFI"
    DEVICE_INFO["x86_64,max_plugins"]="100"
    DEVICE_INFO["x86_64,performance"]="high"
    
    # 小米路由器4A千兆版
    DEVICE_INFO["xiaomi_4a_gigabit,name"]="小米路由器4A千兆版"
    DEVICE_INFO["xiaomi_4a_gigabit,arch"]="mipsel"
    DEVICE_INFO["xiaomi_4a_gigabit,target"]="ramips/mt7621"
    DEVICE_INFO["xiaomi_4a_gigabit,cpu"]="MediaTek MT7621AT"
    DEVICE_INFO["xiaomi_4a_gigabit,ram"]="128MB"
    DEVICE_INFO["xiaomi_4a_gigabit,flash"]="16MB"
    DEVICE_INFO["xiaomi_4a_gigabit,features"]="WiFi,Gigabit,USB2.0"
    DEVICE_INFO["xiaomi_4a_gigabit,firmware_format"]="BIN"
    DEVICE_INFO["xiaomi_4a_gigabit,max_plugins"]="20"
    DEVICE_INFO["xiaomi_4a_gigabit,performance"]="medium"
    
    # 新路由3 (Newifi D2)
    DEVICE_INFO["newifi_d2,name"]="新路由3 (Newifi D2)"
    DEVICE_INFO["newifi_d2,arch"]="mipsel"
    DEVICE_INFO["newifi_d2,target"]="ramips/mt7621"
    DEVICE_INFO["newifi_d2,cpu"]="MediaTek MT7621AT"
    DEVICE_INFO["newifi_d2,ram"]="512MB"
    DEVICE_INFO["newifi_d2,flash"]="32MB"
    DEVICE_INFO["newifi_d2,features"]="WiFi,Gigabit,USB3.0,SATA"
    DEVICE_INFO["newifi_d2,firmware_format"]="BIN"
    DEVICE_INFO["newifi_d2,max_plugins"]="40"
    DEVICE_INFO["newifi_d2,performance"]="medium-high"
    
    # 树莓派4B
    DEVICE_INFO["rpi_4b,name"]="树莓派4B"
    DEVICE_INFO["rpi_4b,arch"]="aarch64"
    DEVICE_INFO["rpi_4b,target"]="bcm27xx/bcm2711"
    DEVICE_INFO["rpi_4b,cpu"]="Broadcom BCM2711"
    DEVICE_INFO["rpi_4b,ram"]="1GB-8GB"
    DEVICE_INFO["rpi_4b,flash"]="MicroSD"
    DEVICE_INFO["rpi_4b,features"]="GPIO,CSI,DSI,USB3.0,Gigabit,WiFi,Bluetooth"
    DEVICE_INFO["rpi_4b,firmware_format"]="IMG"
    DEVICE_INFO["rpi_4b,max_plugins"]="60"
    DEVICE_INFO["rpi_4b,performance"]="high"
    
    # NanoPi R2S
    DEVICE_INFO["nanopi_r2s,name"]="NanoPi R2S"
    DEVICE_INFO["nanopi_r2s,arch"]="aarch64"
    DEVICE_INFO["nanopi_r2s,target"]="rockchip/armv8"
    DEVICE_INFO["nanopi_r2s,cpu"]="Rockchip RK3328"
    DEVICE_INFO["nanopi_r2s,ram"]="1GB"
    DEVICE_INFO["nanopi_r2s,flash"]="MicroSD"
    DEVICE_INFO["nanopi_r2s,features"]="Gigabit,USB2.0,GPIO"
    DEVICE_INFO["nanopi_r2s,firmware_format"]="IMG"
    DEVICE_INFO["nanopi_r2s,max_plugins"]="35"
    DEVICE_INFO["nanopi_r2s,performance"]="medium-high"
    
    log_debug "设备数据库初始化完成"
}

# 获取设备信息
get_device_info() {
    local device="$1"
    local info_type="$2"
    
    local key="${device},${info_type}"
    echo "${DEVICE_INFO[$key]:-未知}"
}

# 检查设备是否受支持
is_device_supported() {
    local device="$1"
    
    local device_name=$(get_device_info "$device" "name")
    if [ "$device_name" = "未知" ]; then
        return 1
    else
        return 0
    fi
}

#========================================================================================================================
# 设备验证功能
#========================================================================================================================

# 验证设备
operation_validate() {
    local device=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
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
    
    if [ -z "$device" ]; then
        log_error "请指定设备型号"
        return 1
    fi
    
    log_info "🔍 验证设备: $device"
    
    # 初始化设备数据库
    init_device_database
    
    # 检查设备支持
    if ! is_device_supported "$device"; then
        log_error "不支持的设备型号: $device"
        log_info "支持的设备列表:"
        list_supported_devices
        return 1
    fi
    
    # 显示设备信息
    show_device_details "$device"
    
    # 验证设备特定要求
    validate_device_requirements "$device"
    
    log_success "设备验证通过: $device"
    return 0
}

# 显示设备详细信息
show_device_details() {
    local device="$1"
    
    log_info "设备详细信息:"
    echo "  名称: $(get_device_info "$device" "name")"
    echo "  架构: $(get_device_info "$device" "arch")"
    echo "  目标: $(get_device_info "$device" "target")"
    echo "  CPU: $(get_device_info "$device" "cpu")"
    echo "  内存: $(get_device_info "$device" "ram")"
    echo "  存储: $(get_device_info "$device" "flash")"
    echo "  特性: $(get_device_info "$device" "features")"
    echo "  固件格式: $(get_device_info "$device" "firmware_format")"
    echo "  推荐最大插件数: $(get_device_info "$device" "max_plugins")"
    echo "  性能等级: $(get_device_info "$device" "performance")"
}

# 验证设备特定要求
validate_device_requirements() {
    local device="$1"
    
    log_debug "验证设备特定要求: $device"
    
    case "$device" in
        "x86_64")
            validate_x86_requirements
            ;;
        "xiaomi_4a_gigabit"|"newifi_d2")
            validate_mips_requirements
            ;;
        "rpi_4b")
            validate_rpi_requirements
            ;;
        "nanopi_r2s")
            validate_rockchip_requirements
            ;;
    esac
}

# 验证x86设备要求
validate_x86_requirements() {
    log_debug "验证x86设备要求..."
    
    # 检查是否为虚拟机环境或物理机
    if [ -d "/sys/firmware/efi" ]; then
        log_debug "检测到UEFI环境"
    fi
    
    # 检查CPU特性（在实际环境中）
    if [ -f "/proc/cpuinfo" ]; then
        if grep -q "vmx\|svm" /proc/cpuinfo 2>/dev/null; then
            log_debug "支持硬件虚拟化"
        fi
    fi
    
    return 0
}

# 验证MIPS设备要求
validate_mips_requirements() {
    log_debug "验证MIPS设备要求..."
    
    # MIPS设备通常内存和存储有限
    log_warning "MIPS设备资源有限，建议限制插件数量"
    
    return 0
}

# 验证树莓派要求
validate_rpi_requirements() {
    log_debug "验证树莓派要求..."
    
    # 检查是否在树莓派上运行
    if [ -f "/proc/device-tree/model" ]; then
        local model=$(cat /proc/device-tree/model 2>/dev/null || echo "")
        if [[ "$model" == *"Raspberry Pi"* ]]; then
            log_debug "检测到树莓派环境: $model"
        fi
    fi
    
    return 0
}

# 验证Rockchip设备要求
validate_rockchip_requirements() {
    log_debug "验证Rockchip设备要求..."
    
    # NanoPi R2S等设备特定检查
    return 0
}

#========================================================================================================================
# 设备信息获取功能
#========================================================================================================================

# 获取设备名称
operation_get_name() {
    local device=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --device)
                device="$2"
                shift 2
                ;;
            *)
                log_error "未知参数: $1"
                return 1
                ;;
        esac
    done
    
    if [ -z "$device" ]; then
        log_error "请指定设备型号"
        return 1
    fi
    
    # 初始化设备数据库
    init_device_database
    
    # 获取设备名称
    local device_name=$(get_device_info "$device" "name")
    echo "$device_name"
    
    if [ "$device_name" = "未知" ]; then
        return 1
    else
        return 0
    fi
}

# 获取设备架构
operation_get_arch() {
    local device=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --device)
                device="$2"
                shift 2
                ;;
            *)
                log_error "未知参数: $1"
                return 1
                ;;
        esac
    done
    
    if [ -z "$device" ]; then
        log_error "请指定设备型号"
        return 1
    fi
    
    # 初始化设备数据库
    init_device_database
    
    # 获取设备架构
    local device_arch=$(get_device_info "$device" "arch")
    echo "$device_arch"
    
    if [ "$device_arch" = "未知" ]; then
        return 1
    else
        return 0
    fi
}

# 列出支持的设备
operation_list() {
    log_info "📱 支持的设备列表:"
    
    # 初始化设备数据库
    init_device_database
    
    list_supported_devices
    return 0
}

# 列出支持的设备（内部函数）
list_supported_devices() {
    echo ""
    echo "🔷 X86/AMD64 设备:"
    echo "  x86_64                 - X86 64位通用设备 (高性能)"
    echo ""
    echo "🔷 MIPS 路由器设备:"
    echo "  xiaomi_4a_gigabit      - 小米路由器4A千兆版 (入门级)"
    echo "  newifi_d2              - 新路由3 Newifi D2 (中等性能)"
    echo ""
    echo "🔷 ARM64 开发板设备:"
    echo "  rpi_4b                 - 树莓派4B (高性能开发板)"
    echo "  nanopi_r2s             - NanoPi R2S (网络专用)"
    echo ""
    echo "💡 性能等级说明:"
    echo "  入门级   - 适合基础功能，建议插件数 < 20"
    echo "  中等性能 - 适合常用功能，建议插件数 < 40"
    echo "  高性能   - 适合全功能，建议插件数 < 100"
}

# 检查设备兼容性
operation_check_compatibility() {
    local device=""
    local plugins=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --device)
                device="$2"
                shift 2
                ;;
            --plugins)
                plugins="$2"
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
    
    if [ -z "$device" ]; then
        log_error "请指定设备型号"
        return 1
    fi
    
    log_info "🔍 检查设备兼容性..."
    
    # 初始化设备数据库
    init_device_database
    
    # 验证设备
    if ! is_device_supported "$device"; then
        log_error "不支持的设备: $device"
        return 1
    fi
    
    # 检查插件兼容性
    if [ -n "$plugins" ]; then
        check_plugin_compatibility "$device" "$plugins"
    fi
    
    # 生成兼容性报告
    generate_compatibility_report "$device" "$plugins"
    
    log_success "兼容性检查完成"
    return 0
}

# 检查插件兼容性
check_plugin_compatibility() {
    local device="$1"
    local plugins="$2"
    
    log_debug "检查插件兼容性: $device"
    
    # 获取设备信息
    local device_arch=$(get_device_info "$device" "arch")
    local device_performance=$(get_device_info "$device" "performance")
    local max_plugins=$(get_device_info "$device" "max_plugins")
    
    # 统计插件数量
    local plugin_count=$(echo "$plugins" | tr ',' '\n' | wc -l)
    
    log_info "插件兼容性分析:"
    echo "  目标设备: $device ($device_arch)"
    echo "  性能等级: $device_performance"
    echo "  推荐最大插件数: $max_plugins"
    echo "  当前插件数: $plugin_count"
    
    # 检查插件数量
    if [ "$plugin_count" -gt "$max_plugins" ]; then
        log_warning "插件数量超出推荐值，可能影响性能"
    fi
    
    # 检查架构特定的插件兼容性
    check_arch_specific_plugins "$device_arch" "$plugins"
}

# 检查架构特定的插件兼容性
check_arch_specific_plugins() {
    local device_arch="$1"
    local plugins="$2"
    
    log_debug "检查架构特定插件: $device_arch"
    
    # 解析插件列表
    IFS=',' read -ra plugin_array <<< "$plugins"
    
    for plugin in "${plugin_array[@]}"; do
        plugin=$(echo "$plugin" | xargs)
        
        case "$plugin" in
            "luci-app-dockerman")
                if [ "$device_arch" = "mipsel" ]; then
                    log_warning "Docker在MIPS架构上可能不稳定"
                fi
                ;;
            "luci-app-kvm")
                if [ "$device_arch" != "x86_64" ]; then
                    log_warning "KVM虚拟化仅支持x86_64架构"
                fi
                ;;
            "luci-app-qbittorrent")
                if [ "$device_arch" = "mipsel" ]; then
                    log_warning "qBittorrent在MIPS设备上资源消耗较大"
                fi
                ;;
        esac
    done
}

# 生成兼容性报告
generate_compatibility_report() {
    local device="$1"
    local plugins="$2"
    
    log_info "📋 兼容性报告:"
    
    # 基本信息
    echo "  设备型号: $(get_device_info "$device" "name")"
    echo "  架构: $(get_device_info "$device" "arch")"
    echo "  内存: $(get_device_info "$device" "ram")"
    echo "  存储: $(get_device_info "$device" "flash")"
    
    # 性能评估
    local performance=$(get_device_info "$device" "performance")
    case "$performance" in
        "high")
            echo "  性能评估: ✅ 高性能设备，支持复杂配置"
            ;;
        "medium-high")
            echo "  性能评估: ✅ 中高性能设备，支持大部分功能"
            ;;
        "medium")
            echo "  性能评估: ⚠️ 中等性能设备，建议适度配置"
            ;;
        *)
            echo "  性能评估: ⚠️ 入门级设备，建议精简配置"
            ;;
    esac
    
    # 插件建议
    if [ -n "$plugins" ]; then
        local plugin_count=$(echo "$plugins" | tr ',' '\n' | wc -l)
        local max_plugins=$(get_device_info "$device" "max_plugins")
        
        if [ "$plugin_count" -le "$((max_plugins / 2))" ]; then
            echo "  插件配置: ✅ 轻量化配置，性能良好"
        elif [ "$plugin_count" -le "$max_plugins" ]; then
            echo "  插件配置: ⚠️ 中等配置，注意资源使用"
        else
            echo "  插件配置: ❌ 重载配置，可能影响稳定性"
        fi
    fi
}

#========================================================================================================================
# 帮助信息和主函数
#========================================================================================================================

show_help() {
    cat << EOF
${CYAN}OpenWrt 设备适配器 v${ADAPTER_VERSION}${NC}

${CYAN}使用方法:${NC}
  $0 <操作> [选项...]

${CYAN}操作:${NC}
  validate              验证设备型号
  get-name              获取设备名称
  get-arch              获取设备架构
  list                  列出支持的设备
  check-compatibility   检查设备兼容性

${CYAN}选项:${NC}
  --device <设备>       设备型号
  --plugins <插件>      插件列表（逗号分隔）
  --verbose             详细输出
  -h, --help            显示帮助信息
  --version             显示版本信息

${CYAN}示例:${NC}
  # 验证设备
  $0 validate --device x86_64 --verbose
  
  # 获取设备名称
  $0 get-name --device rpi_4b
  
  # 列出支持的设备
  $0 list
  
  # 检查兼容性
  $0 check-compatibility --device xiaomi_4a_gigabit --plugins "luci-app-ssr-plus,luci-theme-argon"
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
        validate|get-name|get-arch|list|check-compatibility)
            operation="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --version)
            echo "OpenWrt 设备适配器 版本 $ADAPTER_VERSION"
            exit 0
            ;;
        *)
            log_error "未知操作: $1"
            show_help
            exit 1
            ;;
    esac
    
    # 创建设备配置目录
    mkdir -p "$DEVICE_PROFILES_DIR"
    
    # 执行操作
    case "$operation" in
        "validate")
            operation_validate "$@"
            ;;
        "get-name")
            operation_get_name "$@"
            ;;
        "get-arch")
            operation_get_arch "$@"
            ;;
        "list")
            operation_list "$@"
            ;;
        "check-compatibility")
            operation_check_compatibility "$@"
            ;;
    esac
}

# 检查脚本是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi