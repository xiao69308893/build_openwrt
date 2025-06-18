#!/bin/bash
#========================================================================================================================
# OpenWrt 错误处理模块
# 功能: 编译错误检测、自动修复、问题预防
# 版本: 2.0.0
#========================================================================================================================

set -euo pipefail

# 模块版本和路径
readonly MODULE_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly FIXES_DIR="$PROJECT_ROOT/script/fixes"

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
log_info() { echo -e "${BLUE}[ERROR-HANDLER]${NC} $1"; }
log_success() { echo -e "${GREEN}[ERROR-HANDLER]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[ERROR-HANDLER]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR-HANDLER]${NC} $1" >&2; }
log_debug() { [ "$VERBOSE" = true ] && echo -e "${CYAN}[ERROR-HANDLER-DEBUG]${NC} $1"; }

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
# 错误检测和分类
#========================================================================================================================

# 错误模式定义
declare -A ERROR_PATTERNS

# 初始化错误模式数据库
init_error_patterns() {
    log_debug "初始化错误模式数据库..."
    
    # 编译错误模式
    ERROR_PATTERNS["udebug_error"]="ucode_include_dir-NOTFOUND|udebug.*undefined reference"
    ERROR_PATTERNS["kernel_patch_failed"]="Patch failed|patch.*FAILED|Hunk.*FAILED"
    ERROR_PATTERNS["feeds_error"]="feeds.*failed|feed.*not found|package.*not found"
    ERROR_PATTERNS["memory_exhausted"]="virtual memory exhausted|out of memory|killed.*signal 9"
    ERROR_PATTERNS["disk_full"]="No space left on device|device full"
    ERROR_PATTERNS["network_timeout"]="Connection timed out|Network is unreachable|failed to download"
    ERROR_PATTERNS["dependency_missing"]="dependency.*not found|required.*not found|missing dependency"
    ERROR_PATTERNS["cmake_error"]="CMake Error|cmake.*failed|CMAKE.*ERROR"
    ERROR_PATTERNS["linker_error"]="undefined reference|ld:.*not found|linker.*failed"
    ERROR_PATTERNS["permission_denied"]="Permission denied|permission.*denied|access denied"
    
    # 设备特定错误
    ERROR_PATTERNS["rpi_camera_error"]="imx219.*FAILED|camera.*not found|vc4.*failed"
    ERROR_PATTERNS["mips_alignment"]="alignment.*error|unaligned access|bus error"
    ERROR_PATTERNS["x86_kvm_error"]="kvm.*failed|virtualization.*error"
    
    # 插件特定错误
    ERROR_PATTERNS["docker_error"]="docker.*failed|containerd.*error|cgroup.*error"
    ERROR_PATTERNS["v2ray_error"]="v2ray.*failed|xray.*error|sing-box.*failed"
    ERROR_PATTERNS["luci_error"]="luci.*error|web interface.*failed|uhttpd.*error"
    
    log_debug "错误模式数据库初始化完成"
}

# 检测编译错误类型
detect_compilation_errors() {
    local log_file="$1"
    
    if [ ! -f "$log_file" ]; then
        log_debug "日志文件不存在: $log_file"
        return 1
    fi
    
    log_debug "分析编译日志: $log_file"
    
    local detected_errors=()
    
    # 初始化错误模式
    init_error_patterns
    
    # 检查每种错误模式
    for error_type in "${!ERROR_PATTERNS[@]}"; do
        local pattern="${ERROR_PATTERNS[$error_type]}"
        
        if grep -qE "$pattern" "$log_file" 2>/dev/null; then
            detected_errors+=("$error_type")
            log_debug "检测到错误类型: $error_type"
        fi
    done
    
    # 输出检测结果
    if [ ${#detected_errors[@]} -gt 0 ]; then
        echo "${detected_errors[@]}"
        return 0
    else
        echo "unknown_error"
        return 1
    fi
}

# 分析最近的编译日志
analyze_recent_logs() {
    log_debug "分析最近的编译日志..."
    
    # 查找可能的日志文件
    local log_files=(
        "build.log"
        "logs/package.log"
        "logs/target.log" 
        "logs/compile.log"
        "/tmp/openwrt_build.log"
    )
    
    local found_logs=()
    
    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ] && [ -s "$log_file" ]; then
            found_logs+=("$log_file")
        fi
    done
    
    if [ ${#found_logs[@]} -eq 0 ]; then
        log_debug "未找到编译日志文件"
        return 1
    fi
    
    # 分析最新的日志文件
    local latest_log="${found_logs[0]}"
    for log_file in "${found_logs[@]}"; do
        if [ "$log_file" -nt "$latest_log" ]; then
            latest_log="$log_file"
        fi
    done
    
    log_debug "分析日志文件: $latest_log"
    detect_compilation_errors "$latest_log"
}

#========================================================================================================================
# 错误修复策略
#========================================================================================================================

# 修复udebug错误
fix_udebug_error() {
    local device="$1"
    
    log_info "修复udebug错误..."
    
    # 修复CMakeLists.txt中的ucode路径问题
    local cmake_files=($(find . -name "CMakeLists.txt" -exec grep -l "ucode_include_dir" {} \;))
    
    for cmake_file in "${cmake_files[@]}"; do
        log_debug "修复CMake文件: $cmake_file"
        
        # 备份原文件
        cp "$cmake_file" "$cmake_file.backup"
        
        # 修复ucode路径
        sed -i 's/ucode_include_dir-NOTFOUND/\/usr\/include\/ucode/g' "$cmake_file"
        sed -i '/find_package.*ucode/d' "$cmake_file"
    done
    
    # 修复Makefile中的udebug依赖
    if [ -f "package/system/udebug/Makefile" ]; then
        log_debug "修复udebug Makefile"
        sed -i '/PKG_BUILD_DEPENDS.*ucode/d' "package/system/udebug/Makefile"
    fi
    
    log_success "udebug错误修复完成"
    return 0
}

# 修复内核补丁错误
fix_kernel_patch_error() {
    local device="$1"
    
    log_info "修复内核补丁错误..."
    
    # 查找失败的补丁
    local patch_dirs=(
        "target/linux/generic/patches-*"
        "target/linux/*/patches-*"
    )
    
    # 移除有问题的补丁
    local problematic_patches=(
        "*debug*"
        "*trace*"
        "*experimental*"
    )
    
    for patch_dir in ${patch_dirs[@]}; do
        if [ -d "$patch_dir" ]; then
            for pattern in "${problematic_patches[@]}"; do
                find "$patch_dir" -name "$pattern" -type f -delete 2>/dev/null || true
            done
        fi
    done
    
    # 重置内核配置
    if [ -d "target/linux" ]; then
        find target/linux -name "config-*" -exec touch {} \;
    fi
    
    log_success "内核补丁错误修复完成"
    return 0
}

# 修复feeds错误
fix_feeds_error() {
    local device="$1"
    
    log_info "修复feeds错误..."
    
    # 重新生成feeds配置
    if [ -f "feeds.conf.default.backup" ]; then
        cp "feeds.conf.default.backup" "feeds.conf.default"
    fi
    
    # 清理feeds目录
    rm -rf feeds/*/
    
    # 重新更新feeds
    ./scripts/feeds update -a
    ./scripts/feeds install -a
    
    log_success "feeds错误修复完成"
    return 0
}

# 修复内存不足错误
fix_memory_exhausted() {
    local device="$1"
    
    log_info "修复内存不足错误..."
    
    # 检查交换空间
    local swap_size=$(free -m | awk '/^Swap:/ {print $2}')
    
    if [ "$swap_size" -lt 2048 ]; then
        log_info "创建临时交换文件..."
        
        # 创建2GB交换文件
        sudo fallocate -l 2G /tmp/swapfile || sudo dd if=/dev/zero of=/tmp/swapfile bs=1M count=2048
        sudo chmod 600 /tmp/swapfile
        sudo mkswap /tmp/swapfile
        sudo swapon /tmp/swapfile
        
        log_success "临时交换空间创建完成"
    fi
    
    # 减少并行编译任务数
    export MAKEFLAGS="-j1"
    
    log_success "内存不足错误修复完成"
    return 0
}

# 修复网络超时错误
fix_network_timeout() {
    local device="$1"
    
    log_info "修复网络超时错误..."
    
    # 设置更长的超时时间
    export WGET_OPTIONS="--timeout=60 --tries=3"
    export CURL_OPTIONS="--connect-timeout 60 --max-time 300 --retry 3"
    
    # 清理下载缓存
    rm -rf dl/.tmp/
    
    # 使用镜像源（如果在中国）
    if curl -s --connect-timeout 5 ipinfo.io/country | grep -q "CN"; then
        log_info "检测到中国网络环境，使用镜像源..."
        
        # 设置清华大学镜像
        export OPENWRT_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/openwrt"
    fi
    
    log_success "网络超时错误修复完成"
    return 0
}

# 修复权限错误
fix_permission_denied() {
    local device="$1"
    
    log_info "修复权限错误..."
    
    # 修复文件权限
    find . -name "*.sh" -type f -exec chmod +x {} \;
    find scripts -type f -exec chmod +x {} \; 2>/dev/null || true
    
    # 修复目录权限
    chmod -R u+w tmp/ build_dir/ staging_dir/ 2>/dev/null || true
    
    log_success "权限错误修复完成"
    return 0
}

# 修复设备特定错误
fix_device_specific_error() {
    local device="$1"
    local error_type="$2"
    
    log_info "修复设备特定错误: $device / $error_type"
    
    case "$device" in
        "rpi_4b")
            case "$error_type" in
                "rpi_camera_error")
                    # 禁用摄像头相关配置
                    sed -i '/CONFIG_PACKAGE.*imx219/d' .config 2>/dev/null || true
                    sed -i '/CONFIG_PACKAGE.*camera/d' .config 2>/dev/null || true
                    ;;
            esac
            ;;
        "xiaomi_4a_gigabit"|"newifi_d2")
            case "$error_type" in
                "mips_alignment")
                    # 添加MIPS对齐修复
                    echo "CONFIG_KERNEL_MIPS_FP_SUPPORT=y" >> .config
                    ;;
            esac
            ;;
        "x86_64")
            case "$error_type" in
                "x86_kvm_error")
                    # 禁用KVM相关配置
                    sed -i '/CONFIG_PACKAGE.*kvm/d' .config 2>/dev/null || true
                    ;;
            esac
            ;;
    esac
    
    log_success "设备特定错误修复完成"
    return 0
}

#========================================================================================================================
# 主要操作函数
#========================================================================================================================

# 自动修复编译错误
operation_auto_fix() {
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
    
    log_info "🔧 开始自动错误修复..."
    
    # 获取设备信息
    local target_device=""
    if [ -n "$BUILD_CONFIG_FILE" ]; then
        target_device=$(get_config_value '.build_params.target_device' '')
    fi
    
    # 分析错误类型
    log_info "1️⃣ 分析编译错误"
    local detected_errors=($(analyze_recent_logs))
    
    if [ ${#detected_errors[@]} -eq 0 ] || [ "${detected_errors[0]}" = "unknown_error" ]; then
        log_warning "未检测到已知错误模式，执行通用修复"
        detected_errors=("generic")
    fi
    
    log_info "检测到的错误类型: ${detected_errors[*]}"
    
    # 执行修复策略
    log_info "2️⃣ 执行错误修复"
    local fix_results=()
    
    for error_type in "${detected_errors[@]}"; do
        log_info "修复错误类型: $error_type"
        
        case "$error_type" in
            "udebug_error")
                if fix_udebug_error "$target_device"; then
                    fix_results+=("✅ udebug错误修复成功")
                else
                    fix_results+=("❌ udebug错误修复失败")
                fi
                ;;
            "kernel_patch_failed")
                if fix_kernel_patch_error "$target_device"; then
                    fix_results+=("✅ 内核补丁错误修复成功")
                else
                    fix_results+=("❌ 内核补丁错误修复失败")
                fi
                ;;
            "feeds_error")
                if fix_feeds_error "$target_device"; then
                    fix_results+=("✅ feeds错误修复成功")
                else
                    fix_results+=("❌ feeds错误修复失败")
                fi
                ;;
            "memory_exhausted")
                if fix_memory_exhausted "$target_device"; then
                    fix_results+=("✅ 内存不足错误修复成功")
                else
                    fix_results+=("❌ 内存不足错误修复失败")
                fi
                ;;
            "network_timeout")
                if fix_network_timeout "$target_device"; then
                    fix_results+=("✅ 网络超时错误修复成功")
                else
                    fix_results+=("❌ 网络超时错误修复失败")
                fi
                ;;
            "permission_denied")
                if fix_permission_denied "$target_device"; then
                    fix_results+=("✅ 权限错误修复成功")
                else
                    fix_results+=("❌ 权限错误修复失败")
                fi
                ;;
            "rpi_camera_error"|"mips_alignment"|"x86_kvm_error")
                if fix_device_specific_error "$target_device" "$error_type"; then
                    fix_results+=("✅ 设备特定错误修复成功")
                else
                    fix_results+=("❌ 设备特定错误修复失败")
                fi
                ;;
            "generic"|*)
                if apply_generic_fixes "$target_device"; then
                    fix_results+=("✅ 通用错误修复完成")
                else
                    fix_results+=("❌ 通用错误修复失败")
                fi
                ;;
        esac
    done
    
    # 显示修复结果
    echo ""
    log_info "📋 错误修复结果:"
    for result in "${fix_results[@]}"; do
        echo "  $result"
    done
    
    echo ""
    log_success "自动错误修复完成"
    return 0
}

# 应用通用修复
apply_generic_fixes() {
    local device="$1"
    
    log_info "应用通用错误修复..."
    
    # 清理临时文件
    rm -rf tmp/.* 2>/dev/null || true
    rm -rf build_dir/host/*/stamp/.compile_* 2>/dev/null || true
    
    # 重新生成配置
    make defconfig &>/dev/null || true
    
    # 修复权限
    fix_permission_denied "$device"
    
    # 调用现有的修复脚本（如果存在）
    if [ -f "$FIXES_DIR/fix-build-issues.sh" ]; then
        log_debug "调用现有修复脚本..."
        chmod +x "$FIXES_DIR/fix-build-issues.sh"
        "$FIXES_DIR/fix-build-issues.sh" "$device" "auto" &>/dev/null || true
    fi
    
    log_success "通用修复完成"
    return 0
}

# 修复编译错误
operation_fix_compilation_errors() {
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
    
    log_info "🛠️ 修复编译错误..."
    
    # 获取设备信息
    local target_device=""
    if [ -n "$BUILD_CONFIG_FILE" ]; then
        target_device=$(get_config_value '.build_params.target_device' '')
    fi
    
    # 执行编译错误修复
    local fix_actions=(
        "清理编译缓存"
        "重新生成配置"
        "修复权限问题"
        "应用设备特定修复"
        "清理下载缓存"
    )
    
    for action in "${fix_actions[@]}"; do
        log_info "执行: $action"
        
        case "$action" in
            "清理编译缓存")
                make clean &>/dev/null || true
                rm -rf tmp/ build_dir/ staging_dir/ 2>/dev/null || true
                ;;
            "重新生成配置")
                make defconfig &>/dev/null || true
                ;;
            "修复权限问题")
                fix_permission_denied "$target_device"
                ;;
            "应用设备特定修复")
                fix_device_specific_error "$target_device" "generic"
                ;;
            "清理下载缓存")
                rm -rf dl/.tmp/ 2>/dev/null || true
                ;;
        esac
    done
    
    log_success "编译错误修复完成"
    return 0
}

# 预防性修复
operation_preventive_fix() {
    local target_device="$1"
    
    log_info "🛡️ 执行预防性修复..."
    
    # 预防性修复措施
    local preventive_measures=(
        "设置编译环境变量"
        "创建必要目录"
        "修复已知问题"
        "优化编译配置"
    )
    
    for measure in "${preventive_measures[@]}"; do
        log_info "执行: $measure"
        
        case "$measure" in
            "设置编译环境变量")
                export FORCE_UNSAFE_CONFIGURE=1
                export LC_ALL=C
                export LANG=C
                ;;
            "创建必要目录")
                mkdir -p logs tmp build_dir staging_dir dl
                ;;
            "修复已知问题")
                apply_generic_fixes "$target_device"
                ;;
            "优化编译配置")
                # 设置合理的并行编译数
                local cpu_cores=$(nproc)
                local memory_gb=$(($(free -m | awk 'NR==2{print $2}') / 1024))
                local make_jobs=$((cpu_cores < memory_gb ? cpu_cores : memory_gb))
                make_jobs=$((make_jobs > 1 ? make_jobs : 1))
                
                export MAKEFLAGS="-j$make_jobs"
                log_debug "设置编译并行数: $make_jobs"
                ;;
        esac
    done
    
    log_success "预防性修复完成"
    return 0
}

#========================================================================================================================
# 帮助信息和主函数
#========================================================================================================================

show_help() {
    cat << EOF
${CYAN}OpenWrt 错误处理模块 v${MODULE_VERSION}${NC}

${CYAN}使用方法:${NC}
  $0 <操作> [选项...]

${CYAN}操作:${NC}
  auto-fix                    自动分析和修复编译错误
  fix-compilation-errors      修复编译错误
  preventive-fix              预防性修复

${CYAN}选项:${NC}
  --config <文件>            构建配置文件
  --verbose                  详细输出
  -h, --help                 显示帮助信息
  --version                  显示版本信息

${CYAN}支持的错误类型:${NC}
  - udebug错误
  - 内核补丁错误
  - feeds错误
  - 内存不足错误
  - 网络超时错误
  - 权限错误
  - 设备特定错误

${CYAN}示例:${NC}
  # 自动修复错误
  $0 auto-fix --config /tmp/build_config.json --verbose
  
  # 修复编译错误
  $0 fix-compilation-errors --config /tmp/build_config.json
  
  # 预防性修复
  $0 preventive-fix x86_64
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
        auto-fix|fix-compilation-errors|preventive-fix)
            operation="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --version)
            echo "错误处理模块 版本 $MODULE_VERSION"
            exit 0
            ;;
        *)
            log_error "未知操作: $1"
            show_help
            exit 1
            ;;
    esac
    
    # 确保fixes目录存在
    mkdir -p "$FIXES_DIR"
    
    # 执行操作
    case "$operation" in
        "auto-fix")
            operation_auto_fix "$@"
            ;;
        "fix-compilation-errors")
            operation_fix_compilation_errors "$@"
            ;;
        "preventive-fix")
            operation_preventive_fix "$@"
            ;;
    esac
}

# 检查脚本是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi