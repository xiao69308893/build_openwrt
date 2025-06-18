#!/bin/bash
#========================================================================================================================
# OpenWrt 构建验证器
# 功能: 构建前验证、配置检查、依赖验证、空间检查
# 版本: 2.0.0
#========================================================================================================================

set -euo pipefail

# 脚本版本和路径
readonly VALIDATOR_VERSION="2.0.0"
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
BUILD_CONFIG_FILE=""
VERBOSE=false

#========================================================================================================================
# 基础工具函数
#========================================================================================================================

# 日志函数
log_info() { echo -e "${BLUE}[BUILD-VALIDATOR]${NC} $1"; }
log_success() { echo -e "${GREEN}[BUILD-VALIDATOR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[BUILD-VALIDATOR]${NC} $1"; }
log_error() { echo -e "${RED}[BUILD-VALIDATOR]${NC} $1" >&2; }
log_debug() { [ "$VERBOSE" = true ] && echo -e "${CYAN}[BUILD-VALIDATOR-DEBUG]${NC} $1"; }

# 从构建配置文件读取值
get_config_value() {
    local key_path="$1"
    local default_value="$2"
    
    if [ -f "$BUILD_CONFIG_FILE" ] && command -v jq &> /dev/null; then
        local value=$(jq -r "$key_path" "$BUILD_CONFIG_FILE" 2>/dev/null)
        if [ "$value" != "null" ] && [ -n "$value" ]; then
            echo "$value"
        else
            echo "$default_value"
        fi
    else
        echo "$default_value"
    fi
}

#========================================================================================================================
# 系统环境验证
#========================================================================================================================

# 检查系统要求
check_system_requirements() {
    log_debug "检查系统要求..."
    
    local issues=()
    
    # 检查操作系统
    if [ ! -f "/etc/os-release" ]; then
        issues+=("无法确定操作系统类型")
    else
        local os_name=$(grep "^NAME=" /etc/os-release | cut -d'"' -f2)
        log_debug "操作系统: $os_name"
        
        # 检查是否为受支持的系统
        if [[ "$os_name" != *"Ubuntu"* ]] && [[ "$os_name" != *"Debian"* ]]; then
            issues+=("当前系统 ($os_name) 可能不完全兼容，建议使用 Ubuntu 20.04+")
        fi
    fi
    
    # 检查系统架构
    local arch=$(uname -m)
    if [ "$arch" != "x86_64" ]; then
        issues+=("非x86_64架构 ($arch) 可能导致编译问题")
    fi
    
    # 检查内核版本
    local kernel_version=$(uname -r)
    log_debug "内核版本: $kernel_version"
    
    # 返回检查结果
    if [ ${#issues[@]} -eq 0 ]; then
        log_success "系统要求检查通过"
        return 0
    else
        log_warning "系统要求检查发现问题:"
        for issue in "${issues[@]}"; do
            log_warning "  - $issue"
        done
        return 1
    fi
}

# 检查必需的软件包
check_required_packages() {
    log_debug "检查必需的软件包..."
    
    local required_packages=(
        "build-essential" "asciidoc" "binutils" "bzip2" "gawk" "gettext" 
        "git" "libncurses5-dev" "libz-dev" "patch" "python3" "python2.7" 
        "unzip" "zlib1g-dev" "lib32gcc1" "libc6-dev-i386" "subversion" 
        "flex" "uglifyjs" "git-core" "gcc-multilib" "p7zip" "p7zip-full" 
        "msmtp" "libssl-dev" "texinfo" "libglib2.0-dev" "xmlto" "qemu-utils" 
        "upx" "libelf-dev" "autoconf" "automake" "libtool" "autopoint" 
        "device-tree-compiler" "g++-multilib" "antlr3" "gperf" "wget" 
        "curl" "swig" "rsync"
    )
    
    local missing_packages=()
    
    for package in "${required_packages[@]}"; do
        if ! dpkg -l "$package" &> /dev/null; then
            missing_packages+=("$package")
            log_debug "缺少软件包: $package"
        fi
    done
    
    if [ ${#missing_packages[@]} -eq 0 ]; then
        log_success "软件包检查通过"
        return 0
    else
        log_warning "缺少 ${#missing_packages[@]} 个必需软件包"
        log_info "缺少的软件包: ${missing_packages[*]}"
        log_info "安装命令: sudo apt update && sudo apt install -y ${missing_packages[*]}"
        return 1
    fi
}

# 检查磁盘空间
check_disk_space() {
    log_debug "检查磁盘空间..."
    
    # 检查当前目录的可用空间
    local available_space=$(df -BG "$PWD" | awk 'NR==2 {print $4}' | sed 's/G//')
    local required_space=30  # 至少需要30GB
    
    log_debug "可用空间: ${available_space}GB, 需要空间: ${required_space}GB"
    
    if [ "$available_space" -lt "$required_space" ]; then
        log_error "磁盘空间不足: 可用 ${available_space}GB, 需要至少 ${required_space}GB"
        return 1
    else
        log_success "磁盘空间检查通过: ${available_space}GB 可用"
        return 0
    fi
}

# 检查内存
check_memory() {
    log_debug "检查系统内存..."
    
    local total_memory=$(free -m | awk 'NR==2{print $2}')
    local recommended_memory=4096  # 推荐4GB内存
    
    log_debug "系统内存: ${total_memory}MB"
    
    if [ "$total_memory" -lt "$recommended_memory" ]; then
        log_warning "内存较小: ${total_memory}MB, 推荐至少 ${recommended_memory}MB"
        log_warning "编译可能较慢或失败，建议增加交换空间"
        return 1
    else
        log_success "内存检查通过: ${total_memory}MB"
        return 0
    fi
}

#========================================================================================================================
# 源码和配置验证
#========================================================================================================================

# 检查源码目录
check_source_directory() {
    log_debug "检查源码目录..."
    
    local issues=()
    
    # 检查是否在OpenWrt源码目录中
    if [ ! -f "feeds.conf.default" ] && [ ! -f "feeds.conf" ]; then
        issues+=("当前目录不是OpenWrt源码根目录")
    fi
    
    if [ ! -d "package" ]; then
        issues+=("缺少package目录")
    fi
    
    if [ ! -d "target" ]; then
        issues+=("缺少target目录")
    fi
    
    if [ ! -f "Makefile" ]; then
        issues+=("缺少主Makefile")
    fi
    
    # 检查.config文件
    if [ ! -f ".config" ]; then
        issues+=("缺少.config配置文件")
    else
        # 验证.config文件内容
        if ! validate_config_file; then
            issues+=(".config配置文件存在问题")
        fi
    fi
    
    # 返回检查结果
    if [ ${#issues[@]} -eq 0 ]; then
        log_success "源码目录检查通过"
        return 0
    else
        log_error "源码目录检查失败:"
        for issue in "${issues[@]}"; do
            log_error "  - $issue"
        done
        return 1
    fi
}

# 验证.config配置文件
validate_config_file() {
    local config_file=".config"
    
    log_debug "验证.config文件..."
    
    # 检查基本配置项
    if ! grep -q "^CONFIG_TARGET_" "$config_file"; then
        log_error ".config文件缺少目标平台配置"
        return 1
    fi
    
    # 检查架构配置
    local target_arch=$(grep "^CONFIG_TARGET_ARCH=" "$config_file" | cut -d'"' -f2)
    if [ -z "$target_arch" ]; then
        log_warning ".config文件缺少目标架构配置"
    else
        log_debug "目标架构: $target_arch"
    fi
    
    # 检查配置文件大小
    local config_size=$(wc -l < "$config_file")
    if [ "$config_size" -lt 10 ]; then
        log_error ".config文件过小，可能不完整"
        return 1
    fi
    
    log_debug ".config文件验证通过 (${config_size}行)"
    return 0
}

# 检查feeds配置
check_feeds_configuration() {
    log_debug "检查feeds配置..."
    
    local feeds_file=""
    if [ -f "feeds.conf" ]; then
        feeds_file="feeds.conf"
    elif [ -f "feeds.conf.default" ]; then
        feeds_file="feeds.conf.default"
    else
        log_error "未找到feeds配置文件"
        return 1
    fi
    
    log_debug "使用feeds配置文件: $feeds_file"
    
    # 检查feeds格式
    local invalid_lines=0
    while IFS= read -r line; do
        # 跳过注释和空行
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
            continue
        fi
        
        # 检查feeds格式
        if [[ ! "$line" =~ ^src-git[[:space:]]+[^[:space:]]+[[:space:]]+https?:// ]]; then
            log_warning "可能的无效feeds行: $line"
            ((invalid_lines++))
        fi
    done < "$feeds_file"
    
    if [ "$invalid_lines" -gt 0 ]; then
        log_warning "发现 $invalid_lines 行可能无效的feeds配置"
    else
        log_success "feeds配置检查通过"
    fi
    
    return 0
}

#========================================================================================================================
# 构建特定验证
#========================================================================================================================

# 验证构建配置
validate_build_configuration() {
    local target_device=$(get_config_value '.build_params.target_device' '')
    local plugins=$(get_config_value '.build_params.plugins' '')
    local source_branch=$(get_config_value '.build_params.source_branch' '')
    
    log_debug "验证构建配置: $target_device / $source_branch"
    
    local issues=()
    
    # 验证设备配置
    if [ -z "$target_device" ]; then
        issues+=("未指定目标设备")
    else
        # 调用设备适配器验证
        if command -v "$SCRIPT_DIR/device-adapter.sh" &> /dev/null; then
            if ! "$SCRIPT_DIR/device-adapter.sh" validate --device "$target_device" &> /dev/null; then
                issues+=("目标设备 $target_device 验证失败")
            fi
        fi
    fi
    
    # 验证插件配置
    if [ -n "$plugins" ]; then
        # 调用插件解析器验证
        if command -v "$SCRIPT_DIR/plugin-resolver.sh" &> /dev/null; then
            if ! "$SCRIPT_DIR/plugin-resolver.sh" validate --plugins "$plugins" --device "$target_device" &> /dev/null; then
                issues+=("插件配置验证发现问题")
            fi
        fi
    fi
    
    # 验证源码分支
    local supported_branches=("lede-master" "openwrt-main" "immortalwrt-master" "Lienol-master")
    if [ -n "$source_branch" ]; then
        local branch_supported=false
        for branch in "${supported_branches[@]}"; do
            if [ "$source_branch" = "$branch" ]; then
                branch_supported=true
                break
            fi
        done
        
        if [ "$branch_supported" = false ]; then
            issues+=("不支持的源码分支: $source_branch")
        fi
    fi
    
    # 返回验证结果
    if [ ${#issues[@]} -eq 0 ]; then
        log_success "构建配置验证通过"
        return 0
    else
        log_error "构建配置验证失败:"
        for issue in "${issues[@]}"; do
            log_error "  - $issue"
        done
        return 1
    fi
}

# 检查网络连接
check_network_connectivity() {
    log_debug "检查网络连接..."
    
    local test_urls=(
        "https://github.com"
        "https://git.openwrt.org"
        "https://downloads.openwrt.org"
    )
    
    local failed_urls=()
    
    for url in "${test_urls[@]}"; do
        if ! curl -f -s --connect-timeout 10 "$url" > /dev/null; then
            failed_urls+=("$url")
            log_debug "连接失败: $url"
        else
            log_debug "连接成功: $url"
        fi
    done
    
    if [ ${#failed_urls[@]} -eq 0 ]; then
        log_success "网络连接检查通过"
        return 0
    else
        log_warning "部分网络连接失败:"
        for url in "${failed_urls[@]}"; do
            log_warning "  - $url"
        done
        return 1
    fi
}

# 检查编译工具链
check_build_toolchain() {
    log_debug "检查编译工具链..."
    
    local required_tools=("gcc" "g++" "make" "cmake" "python3" "git")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        else
            local tool_version=$("$tool" --version 2>/dev/null | head -n1)
            log_debug "$tool: $tool_version"
        fi
    done
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        log_success "编译工具链检查通过"
        return 0
    else
        log_error "缺少编译工具: ${missing_tools[*]}"
        return 1
    fi
}

#========================================================================================================================
# 主要操作函数
#========================================================================================================================

# 构建前验证
operation_pre_build() {
    local config_file=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                config_file="$2"
                BUILD_CONFIG_FILE="$config_file"
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
    
    # 验证配置文件
    if [ ! -f "$BUILD_CONFIG_FILE" ]; then
        log_error "构建配置文件不存在: $BUILD_CONFIG_FILE"
        return 1
    fi
    
    log_info "🔍 开始构建前验证..."
    
    local validation_results=()
    local failed_checks=0
    
    # 执行各项检查
    echo ""
    log_info "1️⃣ 系统环境检查"
    if ! check_system_requirements; then
        validation_results+=("❌ 系统要求检查失败")
        ((failed_checks++))
    else
        validation_results+=("✅ 系统要求检查通过")
    fi
    
    if ! check_required_packages; then
        validation_results+=("❌ 软件包检查失败")
        ((failed_checks++))
    else
        validation_results+=("✅ 软件包检查通过")
    fi
    
    if ! check_disk_space; then
        validation_results+=("❌ 磁盘空间检查失败")
        ((failed_checks++))
    else
        validation_results+=("✅ 磁盘空间检查通过")
    fi
    
    if ! check_memory; then
        validation_results+=("⚠️ 内存检查有警告")
    else
        validation_results+=("✅ 内存检查通过")
    fi
    
    echo ""
    log_info "2️⃣ 源码和配置检查"
    if ! check_source_directory; then
        validation_results+=("❌ 源码目录检查失败")
        ((failed_checks++))
    else
        validation_results+=("✅ 源码目录检查通过")
    fi
    
    if ! check_feeds_configuration; then
        validation_results+=("⚠️ feeds配置有警告")
    else
        validation_results+=("✅ feeds配置检查通过")
    fi
    
    echo ""
    log_info "3️⃣ 构建配置验证"
    if ! validate_build_configuration; then
        validation_results+=("❌ 构建配置验证失败")
        ((failed_checks++))
    else
        validation_results+=("✅ 构建配置验证通过")
    fi
    
    echo ""
    log_info "4️⃣ 网络和工具检查"
    if ! check_network_connectivity; then
        validation_results+=("⚠️ 网络连接有问题")
    else
        validation_results+=("✅ 网络连接检查通过")
    fi
    
    if ! check_build_toolchain; then
        validation_results+=("❌ 编译工具链检查失败")
        ((failed_checks++))
    else
        validation_results+=("✅ 编译工具链检查通过")
    fi
    
    # 显示验证结果摘要
    echo ""
    log_info "📋 验证结果摘要:"
    for result in "${validation_results[@]}"; do
        echo "  $result"
    done
    
    echo ""
    if [ "$failed_checks" -eq 0 ]; then
        log_success "🎉 构建前验证通过，可以开始编译"
        return 0
    else
        log_error "❌ 构建前验证失败，发现 $failed_checks 个严重问题"
        log_info "请修复上述问题后重新验证"
        return 1
    fi
}

# 快速验证
operation_quick_check() {
    log_info "⚡ 快速验证..."
    
    local issues=0
    
    # 基础检查
    if [ ! -f ".config" ]; then
        log_error "缺少.config文件"
        ((issues++))
    fi
    
    if ! command -v gcc &> /dev/null; then
        log_error "缺少gcc编译器"
        ((issues++))
    fi
    
    local available_space=$(df -BG "$PWD" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 10 ]; then
        log_error "磁盘空间不足: ${available_space}GB"
        ((issues++))
    fi
    
    if [ "$issues" -eq 0 ]; then
        log_success "快速验证通过"
        return 0
    else
        log_error "快速验证失败，发现 $issues 个问题"
        return 1
    fi
}

#========================================================================================================================
# 帮助信息和主函数
#========================================================================================================================

show_help() {
    cat << EOF
${CYAN}OpenWrt 构建验证器 v${VALIDATOR_VERSION}${NC}

${CYAN}使用方法:${NC}
  $0 <操作> [选项...]

${CYAN}操作:${NC}
  pre-build             完整的构建前验证
  quick-check           快速验证

${CYAN}选项:${NC}
  --config <文件>       构建配置文件
  --verbose             详细输出
  -h, --help            显示帮助信息
  --version             显示版本信息

${CYAN}示例:${NC}
  # 完整验证
  $0 pre-build --config /tmp/build_config.json --verbose
  
  # 快速验证
  $0 quick-check
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
        pre-build|quick-check)
            operation="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --version)
            echo "OpenWrt 构建验证器 版本 $VALIDATOR_VERSION"
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
        "pre-build")
            operation_pre_build "$@"
            ;;
        "quick-check")
            operation_quick_check "$@"
            ;;
    esac
}

# 检查脚本是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi