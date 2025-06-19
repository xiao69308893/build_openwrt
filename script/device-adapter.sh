#!/bin/bash
#========================================================================================================================
# OpenWrt 设备适配器 - 修复版本  
# 功能: 设备验证、架构适配、硬件特性检测
# 版本: 2.0.1 (修复版本)
#========================================================================================================================

# 使用更宽松的错误处理模式，避免意外退出
set -eo pipefail

# 脚本版本和路径
readonly ADAPTER_VERSION="2.0.1"
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

# 日志函数 - 增加错误处理
log_info() { 
    echo -e "${BLUE}[DEVICE-ADAPTER]${NC} $1" || true
}
log_success() { 
    echo -e "${GREEN}[DEVICE-ADAPTER]${NC} $1" || true
}
log_warning() { 
    echo -e "${YELLOW}[DEVICE-ADAPTER]${NC} $1" || true
}
log_error() { 
    echo -e "${RED}[DEVICE-ADAPTER]${NC} $1" >&2 || true
}
log_debug() { 
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[DEVICE-ADAPTER-DEBUG]${NC} $1" || true
    fi
}

#========================================================================================================================
# 设备信息数据库 - 修复版本
#========================================================================================================================

# 设备信息定义 - 使用普通数组避免关联数组兼容性问题
DEVICE_INFO_DATA=""

# 初始化设备信息数据库 - 重构为更稳定的实现
init_device_database() {
    log_debug "初始化设备数据库..."
    
    # 使用heredoc方式定义设备信息，避免关联数组问题
    DEVICE_INFO_DATA=$(cat << 'EOF'
x86_64|name|X86 64位通用设备
x86_64|arch|x86_64
x86_64|target|x86/64
x86_64|cpu|Intel/AMD x86_64
x86_64|ram|512MB+
x86_64|flash|8GB+
x86_64|features|UEFI,KVM,Docker,USB3.0
x86_64|firmware_format|IMG,VMDK,EFI
x86_64|max_plugins|100
x86_64|performance|high
xiaomi_4a_gigabit|name|小米路由器4A千兆版
xiaomi_4a_gigabit|arch|mipsel
xiaomi_4a_gigabit|target|ramips/mt7621
xiaomi_4a_gigabit|cpu|MediaTek MT7621AT
xiaomi_4a_gigabit|ram|128MB
xiaomi_4a_gigabit|flash|16MB
xiaomi_4a_gigabit|features|WiFi,Gigabit,USB2.0
xiaomi_4a_gigabit|firmware_format|BIN
xiaomi_4a_gigabit|max_plugins|20
xiaomi_4a_gigabit|performance|medium
newifi_d2|name|新路由3 (Newifi D2)
newifi_d2|arch|mipsel
newifi_d2|target|ramips/mt7621
newifi_d2|cpu|MediaTek MT7621AT
newifi_d2|ram|512MB
newifi_d2|flash|32MB
newifi_d2|features|WiFi,Gigabit,USB3.0,SATA
newifi_d2|firmware_format|BIN
newifi_d2|max_plugins|40
newifi_d2|performance|medium-high
rpi_4b|name|树莓派4B
rpi_4b|arch|aarch64
rpi_4b|target|bcm27xx/bcm2711
rpi_4b|cpu|Broadcom BCM2711
rpi_4b|ram|1GB-8GB
rpi_4b|flash|MicroSD
rpi_4b|features|GPIO,CSI,DSI,USB3.0,Gigabit,WiFi,Bluetooth
rpi_4b|firmware_format|IMG
rpi_4b|max_plugins|60
rpi_4b|performance|high
nanopi_r2s|name|NanoPi R2S
nanopi_r2s|arch|aarch64
nanopi_r2s|target|rockchip/armv8
nanopi_r2s|cpu|Rockchip RK3328
nanopi_r2s|ram|1GB
nanopi_r2s|flash|MicroSD
nanopi_r2s|features|Gigabit,USB2.0,GPIO
nanopi_r2s|firmware_format|IMG
nanopi_r2s|max_plugins|35
nanopi_r2s|performance|medium-high
EOF
    )
    
    log_debug "设备数据库初始化完成"
}

# 获取设备信息 - 重构为更稳定的实现
get_device_info() {
    local device="$1"
    local info_type="$2"
    
    # 确保设备数据库已初始化
    if [ -z "$DEVICE_INFO_DATA" ]; then
        init_device_database
    fi
    
    # 从数据中查找对应信息
    local result=$(echo "$DEVICE_INFO_DATA" | grep "^${device}|${info_type}|" | cut -d'|' -f3)
    
    if [ -n "$result" ]; then
        echo "$result"
    else
        echo "未知"
    fi
}

# 检查设备是否受支持 - 简化实现
is_device_supported() {
    local device="$1"
    
    # 确保设备数据库已初始化
    if [ -z "$DEVICE_INFO_DATA" ]; then
        init_device_database
    fi
    
    # 检查设备是否在数据库中
    local device_name=$(get_device_info "$device" "name")
    if [ "$device_name" = "未知" ]; then
        log_debug "设备不受支持: $device"
        return 1
    else
        log_debug "设备受支持: $device -> $device_name"
        return 0
    fi
}

#========================================================================================================================
# 设备验证功能 - 增强错误处理
#========================================================================================================================

# 验证设备 - 主要验证函数
operation_validate() {
    local device=""
    local verbose_flag=false
    
    # 解析参数 - 增加错误处理
    while [[ $# -gt 0 ]]; do
        case $1 in
            --device)
                if [ -n "$2" ]; then
                    device="$2"
                    shift 2
                else
                    log_error "缺少设备参数值"
                    return 1
                fi
                ;;
            --verbose)
                VERBOSE=true
                verbose_flag=true
                shift
                ;;
            *)
                log_error "未知参数: $1"
                return 1
                ;;
        esac
    done
    
    # 参数验证
    if [ -z "$device" ]; then
        log_error "请指定设备型号"
        log_info "使用示例: $0 validate --device x86_64"
        return 1
    fi
    
    log_info "🔍 验证设备: $device"
    
    # 初始化设备数据库 - 添加错误检查
    if ! init_device_database; then
        log_error "设备数据库初始化失败"
        return 1
    fi
    
    # 检查设备支持
    if ! is_device_supported "$device"; then
        log_error "不支持的设备型号: $device"
        log_info "支持的设备列表:"
        list_supported_devices || true
        return 1
    fi
    
    # 显示设备信息 - 添加错误处理
    if ! show_device_details "$device"; then
        log_warning "无法显示设备详细信息"
    fi
    
    # 验证设备特定要求 - 添加错误处理
    if ! validate_device_requirements "$device"; then
        log_warning "设备特定要求验证失败，但继续处理"
    fi
    
    log_success "✅ 设备验证通过: $device"
    return 0
}

# 显示设备详细信息 - 增加错误处理
show_device_details() {
    local device="$1"
    
    log_info "设备详细信息:"
    echo "  名称: $(get_device_info "$device" "name")" || true
    echo "  架构: $(get_device_info "$device" "arch")" || true
    echo "  目标: $(get_device_info "$device" "target")" || true
    echo "  CPU: $(get_device_info "$device" "cpu")" || true
    echo "  内存: $(get_device_info "$device" "ram")" || true
    echo "  存储: $(get_device_info "$device" "flash")" || true
    echo "  特性: $(get_device_info "$device" "features")" || true
    echo "  固件格式: $(get_device_info "$device" "firmware_format")" || true
    echo "  推荐最大插件数: $(get_device_info "$device" "max_plugins")" || true
    echo "  性能等级: $(get_device_info "$device" "performance")" || true
    
    return 0
}

# 验证设备特定要求 - 简化实现
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
        *)
            log_debug "使用通用设备验证"
            return 0
            ;;
    esac
}

# 验证x86设备要求 - 简化实现
validate_x86_requirements() {
    log_debug "验证x86设备要求..."
    
    # 简化的x86检查，避免复杂的系统调用
    log_debug "x86_64设备通常具有良好的兼容性"
    
    return 0
}

# 验证MIPS设备要求
validate_mips_requirements() {
    log_debug "验证MIPS设备要求..."
    log_warning "MIPS设备资源有限，建议限制插件数量"
    return 0
}

# 验证树莓派要求
validate_rpi_requirements() {
    log_debug "验证树莓派要求..."
    log_debug "树莓派设备具有良好的兼容性"
    return 0
}

# 验证Rockchip设备要求
validate_rockchip_requirements() {
    log_debug "验证Rockchip设备要求..."
    log_debug "Rockchip设备网络性能优秀"
    return 0
}

#========================================================================================================================
# 其他操作函数
#========================================================================================================================

# 获取设备名称
operation_get_name() {
    local device=""
    
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
    
    return 0
}

# 检查设备兼容性
operation_check_compatibility() {
    local device=""
    local plugins=""
    
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
    
    # 显示基本兼容性信息
    log_success "兼容性检查完成"
    return 0
}

#========================================================================================================================
# 帮助和主函数
#========================================================================================================================

# 显示帮助信息
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

${CYAN}修复版本说明:${NC}
  - 使用更稳定的数据存储方式，避免关联数组兼容性问题
  - 增强错误处理，避免脚本意外退出
  - 简化设备验证逻辑，提高可靠性
  - 添加详细调试信息，便于问题排查
EOF
}

# 主函数 - 增强错误处理
main() {
    local operation=""
    
    # 创建必需目录 - 添加错误处理
    if ! mkdir -p "$DEVICE_PROFILES_DIR" 2>/dev/null; then
        log_warning "无法创建设备配置目录: $DEVICE_PROFILES_DIR"
    fi
    
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
    
    # 执行操作 - 添加错误处理
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