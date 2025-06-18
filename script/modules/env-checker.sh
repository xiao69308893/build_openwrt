#!/bin/bash
#========================================================================================================================
# OpenWrt 环境检查模块
# 功能: 系统环境检查、依赖安装、环境修复
# 版本: 2.0.0
#========================================================================================================================

set -euo pipefail

# 模块版本和路径
readonly MODULE_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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
log_info() { echo -e "${BLUE}[ENV-CHECKER]${NC} $1"; }
log_success() { echo -e "${GREEN}[ENV-CHECKER]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[ENV-CHECKER]${NC} $1"; }
log_error() { echo -e "${RED}[ENV-CHECKER]${NC} $1" >&2; }
log_debug() { [ "$VERBOSE" = true ] && echo -e "${CYAN}[ENV-CHECKER-DEBUG]${NC} $1"; }

#========================================================================================================================
# 系统环境检查
#========================================================================================================================

# 检查操作系统
check_operating_system() {
    log_debug "检查操作系统..."
    
    if [ ! -f "/etc/os-release" ]; then
        log_error "无法识别操作系统类型"
        return 1
    fi
    
    local os_name=$(grep "^NAME=" /etc/os-release | cut -d'"' -f2)
    local os_version=$(grep "^VERSION=" /etc/os-release | cut -d'"' -f2 2>/dev/null || echo "未知版本")
    
    log_info "操作系统: $os_name $os_version"
    
    # 检查支持的操作系统
    case "$os_name" in
        *"Ubuntu"*)
            local version_id=$(grep "^VERSION_ID=" /etc/os-release | cut -d'"' -f2)
            if [[ "$version_id" > "18.04" ]] || [[ "$version_id" == "18.04" ]]; then
                log_success "Ubuntu版本支持良好"
                return 0
            else
                log_warning "Ubuntu版本较旧，建议升级到18.04+"
                return 1
            fi
            ;;
        *"Debian"*)
            log_success "Debian系统支持良好"
            return 0
            ;;
        *)
            log_warning "当前系统 ($os_name) 可能不完全兼容"
            log_info "推荐使用: Ubuntu 20.04 LTS 或 Debian 11+"
            return 1
            ;;
    esac
}

# 检查系统架构
check_system_architecture() {
    log_debug "检查系统架构..."
    
    local arch=$(uname -m)
    local kernel_version=$(uname -r)
    
    log_info "系统架构: $arch"
    log_info "内核版本: $kernel_version"
    
    case "$arch" in
        "x86_64")
            log_success "x86_64架构支持最佳"
            return 0
            ;;
        "aarch64")
            log_info "ARM64架构支持良好"
            return 0
            ;;
        *)
            log_warning "非主流架构 ($arch)，可能遇到兼容性问题"
            return 1
            ;;
    esac
}

# 检查系统资源
check_system_resources() {
    log_debug "检查系统资源..."
    
    local cpu_cores=$(nproc)
    local total_memory=$(free -m | awk 'NR==2{print $2}')
    local available_memory=$(free -m | awk 'NR==2{print $7}')
    local disk_space=$(df -BG "$PWD" | awk 'NR==2 {print $4}' | sed 's/G//')
    
    log_info "系统资源状况:"
    echo "  CPU核心数: $cpu_cores"
    echo "  总内存: ${total_memory}MB"
    echo "  可用内存: ${available_memory}MB"
    echo "  可用磁盘: ${disk_space}GB"
    
    local resource_issues=()
    
    # 检查CPU
    if [ "$cpu_cores" -lt 2 ]; then
        resource_issues+=("CPU核心数过少 ($cpu_cores)，建议至少2核")
    fi
    
    # 检查内存
    if [ "$total_memory" -lt 2048 ]; then
        resource_issues+=("内存不足 (${total_memory}MB)，建议至少2GB")
    elif [ "$total_memory" -lt 4096 ]; then
        log_warning "内存较小 (${total_memory}MB)，编译时可能较慢"
    fi
    
    # 检查磁盘空间
    if [ "$disk_space" -lt 30 ]; then
        resource_issues+=("磁盘空间不足 (${disk_space}GB)，需要至少30GB")
    elif [ "$disk_space" -lt 50 ]; then
        log_warning "磁盘空间偏小 (${disk_space}GB)，建议至少50GB"
    fi
    
    if [ ${#resource_issues[@]} -eq 0 ]; then
        log_success "系统资源检查通过"
        return 0
    else
        log_error "系统资源检查失败:"
        for issue in "${resource_issues[@]}"; do
            log_error "  - $issue"
        done
        return 1
    fi
}

#========================================================================================================================
# 软件依赖检查
#========================================================================================================================

# 检查软件包管理器
check_package_manager() {
    log_debug "检查软件包管理器..."
    
    if command -v apt &> /dev/null; then
        log_success "检测到apt包管理器"
        
        # 检查是否可以使用sudo
        if ! sudo -n true 2>/dev/null; then
            log_warning "当前用户无sudo权限，无法自动安装软件包"
            return 1
        fi
        
        return 0
    elif command -v yum &> /dev/null; then
        log_info "检测到yum包管理器 (部分支持)"
        return 0
    elif command -v pacman &> /dev/null; then
        log_info "检测到pacman包管理器 (部分支持)"
        return 0
    else
        log_error "未检测到支持的包管理器"
        return 1
    fi
}

# 检查必需的软件包
check_required_packages() {
    log_debug "检查必需的软件包..."
    
    # 核心编译工具
    local core_packages=(
        "build-essential" "gcc" "g++" "make" "cmake" "git"
        "python3" "python3-pip" "curl" "wget" "unzip"
    )
    
    # OpenWrt特定依赖
    local openwrt_packages=(
        "libncurses5-dev" "libz-dev" "gawk" "flex" "bison"
        "gettext" "texinfo" "autoconf" "automake" "libtool"
        "libssl-dev" "subversion" "mercurial" "rsync"
        "device-tree-compiler" "u-boot-tools" "antlr3"
        "asciidoc" "binutils" "bzip2" "fastjar" "help2man"
        "intltool" "perl-modules" "python2.7-dev" "swig"
        "time" "util-linux" "zlib1g-dev" "file" "gcc-multilib"
        "g++-multilib" "lib32gcc1" "libc6-dev-i386" "qemu-utils"
        "uglifyjs" "libelf-dev" "libglib2.0-dev" "xmlto"
        "p7zip" "p7zip-full" "msmtp" "upx" "autopoint" "gperf"
    )
    
    local all_packages=("${core_packages[@]}" "${openwrt_packages[@]}")
    local missing_packages=()
    local available_packages=()
    
    # 检查每个软件包
    for package in "${all_packages[@]}"; do
        if dpkg -l "$package" &> /dev/null; then
            available_packages+=("$package")
            log_debug "✅ $package"
        else
            missing_packages+=("$package")
            log_debug "❌ $package"
        fi
    done
    
    log_info "软件包状态: ${#available_packages[@]}个已安装, ${#missing_packages[@]}个缺失"
    
    if [ ${#missing_packages[@]} -eq 0 ]; then
        log_success "所有必需软件包已安装"
        return 0
    else
        log_warning "缺少 ${#missing_packages[@]} 个软件包"
        if [ "$VERBOSE" = true ]; then
            log_info "缺失的软件包:"
            for package in "${missing_packages[@]:0:10}"; do
                echo "  - $package"
            done
            if [ ${#missing_packages[@]} -gt 10 ]; then
                echo "  - ... 还有 $((${#missing_packages[@]} - 10)) 个"
            fi
        fi
        return 1
    fi
}

# 检查Python环境
check_python_environment() {
    log_debug "检查Python环境..."
    
    local issues=()
    
    # 检查Python3
    if command -v python3 &> /dev/null; then
        local python3_version=$(python3 --version 2>&1 | cut -d' ' -f2)
        log_debug "Python3版本: $python3_version"
        
        # 检查版本是否足够新
        local major_minor=$(echo "$python3_version" | cut -d'.' -f1-2)
        if [[ "$major_minor" < "3.6" ]]; then
            issues+=("Python3版本过旧 ($python3_version)，建议3.6+")
        fi
    else
        issues+=("未安装Python3")
    fi
    
    # 检查Python2 (某些旧版本OpenWrt仍需要)
    if command -v python2 &> /dev/null; then
        local python2_version=$(python2 --version 2>&1 | cut -d' ' -f2)
        log_debug "Python2版本: $python2_version"
    else
        log_debug "Python2未安装 (大多数新版本不需要)"
    fi
    
    # 检查pip
    if ! command -v pip3 &> /dev/null; then
        issues+=("未安装pip3")
    fi
    
    if [ ${#issues[@]} -eq 0 ]; then
        log_success "Python环境检查通过"
        return 0
    else
        log_warning "Python环境检查发现问题:"
        for issue in "${issues[@]}"; do
            log_warning "  - $issue"
        done
        return 1
    fi
}

#========================================================================================================================
# 环境修复功能
#========================================================================================================================

# 自动修复环境
operation_auto_fix() {
    log_info "🔧 开始自动环境修复..."
    
    local fix_results=()
    
    # 修复1: 更新软件包索引
    log_info "1️⃣ 更新软件包索引..."
    if sudo apt update &> /dev/null; then
        fix_results+=("✅ 软件包索引更新成功")
    else
        fix_results+=("❌ 软件包索引更新失败")
    fi
    
    # 修复2: 安装缺失的软件包
    log_info "2️⃣ 安装缺失的软件包..."
    if install_missing_packages; then
        fix_results+=("✅ 软件包安装完成")
    else
        fix_results+=("❌ 软件包安装失败")
    fi
    
    # 修复3: 设置环境变量
    log_info "3️⃣ 设置环境变量..."
    if setup_environment_variables; then
        fix_results+=("✅ 环境变量设置完成")
    else
        fix_results+=("⚠️ 环境变量设置可能有问题")
    fi
    
    # 修复4: 创建必要目录
    log_info "4️⃣ 创建必要目录..."
    if create_necessary_directories; then
        fix_results+=("✅ 目录结构创建完成")
    else
        fix_results+=("❌ 目录创建失败")
    fi
    
    # 显示修复结果
    echo ""
    log_info "🔧 环境修复结果:"
    for result in "${fix_results[@]}"; do
        echo "  $result"
    done
    
    echo ""
    log_success "环境修复完成"
    return 0
}

# 安装缺失的软件包
install_missing_packages() {
    log_debug "安装缺失的软件包..."
    
    # 基础软件包列表（精简版，用于自动修复）
    local essential_packages=(
        "build-essential" "git" "curl" "wget" "unzip" "python3"
        "libncurses5-dev" "libz-dev" "gawk" "gettext" "libssl-dev"
        "subversion" "rsync" "device-tree-compiler" "flex" "bison"
        "autoconf" "automake" "libtool" "texinfo" "gcc-multilib"
        "g++-multilib" "file" "swig" "asciidoc" "binutils" "bzip2"
    )
    
    local install_command="sudo apt install -y"
    local packages_to_install=()
    
    # 检查哪些包需要安装
    for package in "${essential_packages[@]}"; do
        if ! dpkg -l "$package" &> /dev/null; then
            packages_to_install+=("$package")
        fi
    done
    
    if [ ${#packages_to_install[@]} -eq 0 ]; then
        log_info "所有基础软件包已安装"
        return 0
    fi
    
    log_info "安装 ${#packages_to_install[@]} 个软件包..."
    
    # 分批安装，避免命令行过长
    local batch_size=20
    for ((i=0; i<${#packages_to_install[@]}; i+=batch_size)); do
        local batch=("${packages_to_install[@]:i:batch_size}")
        
        log_debug "安装批次: ${batch[*]}"
        
        if ! $install_command "${batch[@]}" &> /dev/null; then
            log_warning "批次安装失败，尝试逐个安装..."
            
            # 逐个安装失败的包
            for package in "${batch[@]}"; do
                if ! $install_command "$package" &> /dev/null; then
                    log_warning "无法安装: $package"
                fi
            done
        fi
    done
    
    log_success "软件包安装完成"
    return 0
}

# 设置环境变量
setup_environment_variables() {
    log_debug "设置环境变量..."
    
    # 设置编译相关环境变量
    export FORCE_UNSAFE_CONFIGURE=1
    export MAKEFLAGS="-j$(nproc)"
    
    # 设置语言环境
    export LC_ALL=C
    export LANG=C
    
    # 设置时区
    export TZ=UTC
    
    log_debug "环境变量设置完成"
    return 0
}

# 创建必要目录
create_necessary_directories() {
    log_debug "创建必要目录..."
    
    local directories=(
        "$PROJECT_ROOT/.build_temp"
        "$PROJECT_ROOT/logs"
        "$HOME/.cache"
    )
    
    for dir in "${directories[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_debug "创建目录: $dir"
        fi
    done
    
    return 0
}

#========================================================================================================================
# 主要操作函数
#========================================================================================================================

# 完整环境检查
operation_full_check() {
    log_info "🔍 开始完整环境检查..."
    
    local check_results=()
    local failed_checks=0
    
    # 系统环境检查
    echo ""
    log_info "1️⃣ 系统环境检查"
    
    if ! check_operating_system; then
        check_results+=("❌ 操作系统检查失败")
        ((failed_checks++))
    else
        check_results+=("✅ 操作系统检查通过")
    fi
    
    if ! check_system_architecture; then
        check_results+=("⚠️ 系统架构有警告")
    else
        check_results+=("✅ 系统架构检查通过")
    fi
    
    if ! check_system_resources; then
        check_results+=("❌ 系统资源检查失败")
        ((failed_checks++))
    else
        check_results+=("✅ 系统资源检查通过")
    fi
    
    # 软件依赖检查
    echo ""
    log_info "2️⃣ 软件依赖检查"
    
    if ! check_package_manager; then
        check_results+=("❌ 包管理器检查失败")
        ((failed_checks++))
    else
        check_results+=("✅ 包管理器检查通过")
    fi
    
    if ! check_required_packages; then
        check_results+=("❌ 软件包检查失败")
        ((failed_checks++))
    else
        check_results+=("✅ 软件包检查通过")
    fi
    
    if ! check_python_environment; then
        check_results+=("⚠️ Python环境有警告")
    else
        check_results+=("✅ Python环境检查通过")
    fi
    
    # 显示检查结果
    echo ""
    log_info "📋 环境检查结果:"
    for result in "${check_results[@]}"; do
        echo "  $result"
    done
    
    echo ""
    if [ "$failed_checks" -eq 0 ]; then
        log_success "🎉 环境检查通过，系统准备就绪"
        return 0
    else
        log_error "❌ 环境检查失败，发现 $failed_checks 个问题"
        log_info "建议运行: $0 auto-fix 进行自动修复"
        return 1
    fi
}

# 重置环境
operation_reset() {
    log_info "🔄 重置编译环境..."
    
    # 清理临时文件
    rm -rf "$PROJECT_ROOT/.build_temp"/*
    rm -rf "$PROJECT_ROOT/logs"/*
    
    # 重新创建目录
    create_necessary_directories
    
    # 重新设置环境变量
    setup_environment_variables
    
    log_success "环境重置完成"
    return 0
}

#========================================================================================================================
# 帮助信息和主函数
#========================================================================================================================

show_help() {
    cat << EOF
${CYAN}OpenWrt 环境检查模块 v${MODULE_VERSION}${NC}

${CYAN}使用方法:${NC}
  $0 <操作> [选项...]

${CYAN}操作:${NC}
  full-check            完整环境检查
  auto-fix              自动修复环境问题
  reset                 重置编译环境

${CYAN}选项:${NC}
  --verbose             详细输出
  -h, --help            显示帮助信息
  --version             显示版本信息

${CYAN}示例:${NC}
  # 完整环境检查
  $0 full-check --verbose
  
  # 自动修复环境
  $0 auto-fix
  
  # 重置环境
  $0 reset
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
        full-check|auto-fix|reset)
            operation="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --version)
            echo "环境检查模块 版本 $MODULE_VERSION"
            exit 0
            ;;
        *)
            log_error "未知操作: $1"
            show_help
            exit 1
            ;;
    esac
    
    # 解析全局参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                VERBOSE=true
                shift
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done
    
    # 执行操作
    case "$operation" in
        "full-check")
            operation_full_check
            ;;
        "auto-fix")
            operation_auto_fix
            ;;
        "reset")
            operation_reset
            ;;
    esac
}

# 检查脚本是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi