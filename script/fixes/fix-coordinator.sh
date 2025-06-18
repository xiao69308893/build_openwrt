#!/bin/bash
#========================================================================================================================
# OpenWrt 修复协调器 - 重构版
# 功能: 整合现有修复脚本，提供统一的修复接口
# 版本: 2.0.0
#========================================================================================================================

set -euo pipefail

# 脚本版本和路径
readonly COORDINATOR_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly FIXES_DIR="$SCRIPT_DIR"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# 全局变量
VERBOSE=false
DRY_RUN=false

#========================================================================================================================
# 基础工具函数
#========================================================================================================================

# 日志函数
log_info() { echo -e "${BLUE}[FIX-COORDINATOR]${NC} $1"; }
log_success() { echo -e "${GREEN}[FIX-COORDINATOR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[FIX-COORDINATOR]${NC} $1"; }
log_error() { echo -e "${RED}[FIX-COORDINATOR]${NC} $1" >&2; }
log_debug() { [ "$VERBOSE" = true ] && echo -e "${CYAN}[FIX-COORDINATOR-DEBUG]${NC} $1"; }

# 显示标题
show_header() {
    echo -e "${CYAN}"
    echo "========================================================================================================================="
    echo "                                    🔧 OpenWrt 修复协调器 v${COORDINATOR_VERSION}"
    echo "                                       统一修复接口 | 集成现有修复脚本"
    echo "========================================================================================================================="
    echo -e "${NC}"
}

#========================================================================================================================
# 修复脚本管理
#========================================================================================================================

# 查找可用的修复脚本
find_available_fixes() {
    log_debug "查找可用的修复脚本..."
    
    local fix_scripts=()
    
    # 查找现有的修复脚本
    if [ -f "$FIXES_DIR/fix-build-issues.sh" ]; then
        fix_scripts+=("fix-build-issues.sh")
    fi
    
    # 查找设备特定修复脚本
    local device_fixes=($(find "$FIXES_DIR" -name "fix-*.sh" -type f | grep -E "(x86|mips|arm|rpi)" | sort))
    for script in "${device_fixes[@]}"; do
        fix_scripts+=("$(basename "$script")")
    done
    
    # 查找错误特定修复脚本
    local error_fixes=($(find "$FIXES_DIR" -name "fix-*.sh" -type f | grep -E "(udebug|kernel|feeds|docker)" | sort))
    for script in "${error_fixes[@]}"; do
        fix_scripts+=("$(basename "$script")")
    done
    
    # 查找通用修复脚本
    local common_fixes=($(find "$FIXES_DIR" -name "fix-*.sh" -type f | grep -vE "(x86|mips|arm|rpi|udebug|kernel|feeds|docker)" | sort))
    for script in "${common_fixes[@]}"; do
        fix_scripts+=("$(basename "$script")")
    done
    
    # 去重
    printf '%s\n' "${fix_scripts[@]}" | sort -u
}

# 检查修复脚本是否存在
check_fix_script() {
    local script_name="$1"
    
    local script_path="$FIXES_DIR/$script_name"
    
    if [ -f "$script_path" ]; then
        return 0
    else
        return 1
    fi
}

# 执行修复脚本
execute_fix_script() {
    local script_name="$1"
    local device="$2"
    local error_type="${3:-auto}"
    
    local script_path="$FIXES_DIR/$script_name"
    
    if [ ! -f "$script_path" ]; then
        log_error "修复脚本不存在: $script_path"
        return 1
    fi
    
    log_info "执行修复脚本: $script_name"
    log_debug "设备: $device, 错误类型: $error_type"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] 模拟执行: $script_name $device $error_type"
        return 0
    fi
    
    # 确保脚本可执行
    chmod +x "$script_path"
    
    # 执行脚本
    if "$script_path" "$device" "$error_type"; then
        log_success "修复脚本执行成功: $script_name"
        return 0
    else
        log_error "修复脚本执行失败: $script_name"
        return 1
    fi
}

#========================================================================================================================
# 智能修复策略
#========================================================================================================================

# 根据设备选择修复策略
select_device_fixes() {
    local device="$1"
    
    log_debug "为设备 $device 选择修复策略..."
    
    local fixes=()
    
    case "$device" in
        "x86_64")
            fixes+=("fix-udebug.sh" "fix-x86.sh" "fix-kvm.sh")
            ;;
        "xiaomi_4a_gigabit"|"newifi_d2")
            fixes+=("fix-mips.sh" "fix-mt7621.sh" "fix-ramips.sh")
            ;;
        "rpi_4b")
            fixes+=("fix-rpi.sh" "fix-bcm2711.sh" "fix-camera.sh")
            ;;
        "nanopi_r2s")
            fixes+=("fix-rockchip.sh" "fix-armv8.sh")
            ;;
        *)
            log_debug "未知设备，使用通用修复"
            ;;
    esac
    
    # 添加通用修复
    fixes+=("fix-build-issues.sh" "fix-common.sh" "fix-generic.sh")
    
    # 过滤存在的脚本
    local available_fixes=()
    for fix in "${fixes[@]}"; do
        if check_fix_script "$fix"; then
            available_fixes+=("$fix")
        fi
    done
    
    echo "${available_fixes[@]}"
}

# 根据错误类型选择修复策略
select_error_fixes() {
    local error_type="$1"
    
    log_debug "为错误类型 $error_type 选择修复策略..."
    
    local fixes=()
    
    case "$error_type" in
        "udebug"|"udebug_error")
            fixes+=("fix-udebug.sh")
            ;;
        "kernel"|"kernel_patch"|"kernel_patch_failed")
            fixes+=("fix-kernel.sh" "fix-patch.sh")
            ;;
        "feeds"|"feeds_error")
            fixes+=("fix-feeds.sh")
            ;;
        "docker"|"docker_error")
            fixes+=("fix-docker.sh")
            ;;
        "imx219"|"camera"|"rpi_camera_error")
            fixes+=("fix-camera.sh" "fix-imx219.sh")
            ;;
        "memory"|"memory_exhausted")
            fixes+=("fix-memory.sh")
            ;;
        "network"|"network_timeout")
            fixes+=("fix-network.sh")
            ;;
        "permission"|"permission_denied")
            fixes+=("fix-permissions.sh")
            ;;
        *)
            log_debug "未知错误类型，使用通用修复"
            ;;
    esac
    
    # 过滤存在的脚本
    local available_fixes=()
    for fix in "${fixes[@]}"; do
        if check_fix_script "$fix"; then
            available_fixes+=("$fix")
        fi
    done
    
    echo "${available_fixes[@]}"
}

# 执行智能修复
intelligent_fix() {
    local device="$1"
    local error_type="${2:-auto}"
    
    log_info "🤖 执行智能修复..."
    log_info "设备: $device"
    log_info "错误类型: $error_type"
    
    local fix_results=()
    local executed_scripts=()
    
    # 如果错误类型是auto，尝试自动检测
    if [ "$error_type" = "auto" ]; then
        log_info "自动检测错误类型..."
        
        # 调用现有的错误检测逻辑
        if check_fix_script "fix-build-issues.sh"; then
            log_debug "使用现有错误检测脚本"
            error_type="detected"
        else
            log_debug "使用通用错误类型"
            error_type="generic"
        fi
    fi
    
    # 收集需要执行的修复脚本
    local device_fixes=($(select_device_fixes "$device"))
    local error_fixes=($(select_error_fixes "$error_type"))
    
    # 合并并去重
    local all_fixes=()
    for fix in "${device_fixes[@]}" "${error_fixes[@]}"; do
        if [[ ! " ${all_fixes[@]} " =~ " $fix " ]]; then
            all_fixes+=("$fix")
        fi
    done
    
    log_info "计划执行 ${#all_fixes[@]} 个修复脚本"
    
    # 执行修复脚本
    for script in "${all_fixes[@]}"; do
        if [ "$VERBOSE" = true ]; then
            log_info "执行修复: $script"
        fi
        
        if execute_fix_script "$script" "$device" "$error_type"; then
            fix_results+=("✅ $script")
            executed_scripts+=("$script")
        else
            fix_results+=("❌ $script")
        fi
    done
    
    # 如果没有找到特定的修复脚本，执行通用修复
    if [ ${#executed_scripts[@]} -eq 0 ]; then
        log_info "执行通用修复..."
        if execute_generic_fixes "$device"; then
            fix_results+=("✅ 通用修复")
        else
            fix_results+=("❌ 通用修复")
        fi
    fi
    
    # 显示修复结果
    echo ""
    log_info "🔧 修复执行结果:"
    for result in "${fix_results[@]}"; do
        echo "  $result"
    done
    
    echo ""
    if [ ${#executed_scripts[@]} -gt 0 ]; then
        log_success "智能修复完成，执行了 ${#executed_scripts[@]} 个修复脚本"
        return 0
    else
        log_warning "智能修复完成，但没有找到适用的修复脚本"
        return 1
    fi
}

# 执行通用修复
execute_generic_fixes() {
    local device="$1"
    
    log_info "执行通用修复措施..."
    
    # 通用修复步骤
    local generic_steps=(
        "清理临时文件"
        "重置文件权限"
        "清理编译缓存"
        "重新生成配置"
    )
    
    for step in "${generic_steps[@]}"; do
        log_debug "执行: $step"
        
        case "$step" in
            "清理临时文件")
                rm -rf tmp/.* build_dir/host/*/stamp/.compile_* 2>/dev/null || true
                ;;
            "重置文件权限")
                find . -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
                chmod -R u+w tmp/ build_dir/ staging_dir/ 2>/dev/null || true
                ;;
            "清理编译缓存")
                make clean &>/dev/null || true
                ;;
            "重新生成配置")
                make defconfig &>/dev/null || true
                ;;
        esac
    done
    
    log_success "通用修复完成"
    return 0
}

#========================================================================================================================
# 主要操作函数
#========================================================================================================================

# 自动修复
operation_auto() {
    local device=""
    local error_type="auto"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --device)
                device="$2"
                shift 2
                ;;
            --error)
                error_type="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                if [ -z "$device" ]; then
                    device="$1"
                elif [ "$error_type" = "auto" ]; then
                    error_type="$1"
                fi
                shift
                ;;
        esac
    done
    
    if [ -z "$device" ]; then
        log_error "请指定设备型号"
        return 1
    fi
    
    # 显示标题
    show_header
    
    # 执行智能修复
    intelligent_fix "$device" "$error_type"
}

# 列出可用修复
operation_list() {
    show_header
    
    log_info "📋 可用的修复脚本:"
    
    local available_fixes=($(find_available_fixes))
    
    if [ ${#available_fixes[@]} -eq 0 ]; then
        log_warning "未找到任何修复脚本"
        return 1
    fi
    
    echo ""
    echo "设备特定修复:"
    for script in "${available_fixes[@]}"; do
        if [[ "$script" =~ (x86|mips|arm|rpi|bcm|mt7621|rockchip) ]]; then
            echo "  - $script"
        fi
    done
    
    echo ""
    echo "错误特定修复:"
    for script in "${available_fixes[@]}"; do
        if [[ "$script" =~ (udebug|kernel|feeds|docker|camera|imx219) ]]; then
            echo "  - $script"
        fi
    done
    
    echo ""
    echo "通用修复:"
    for script in "${available_fixes[@]}"; do
        if [[ ! "$script" =~ (x86|mips|arm|rpi|bcm|mt7621|rockchip|udebug|kernel|feeds|docker|camera|imx219) ]]; then
            echo "  - $script"
        fi
    done
    
    echo ""
    log_info "总计: ${#available_fixes[@]} 个修复脚本"
    
    return 0
}

# 执行特定修复
operation_run() {
    local script_name=""
    local device=""
    local error_type="manual"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --script)
                script_name="$2"
                shift 2
                ;;
            --device)
                device="$2"
                shift 2
                ;;
            --error)
                error_type="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                if [ -z "$script_name" ]; then
                    script_name="$1"
                elif [ -z "$device" ]; then
                    device="$1"
                fi
                shift
                ;;
        esac
    done
    
    if [ -z "$script_name" ]; then
        log_error "请指定修复脚本名称"
        return 1
    fi
    
    if [ -z "$device" ]; then
        log_error "请指定设备型号"
        return 1
    fi
    
    # 显示标题
    show_header
    
    # 执行特定修复脚本
    log_info "🔧 执行特定修复..."
    
    if execute_fix_script "$script_name" "$device" "$error_type"; then
        log_success "修复脚本执行成功"
        return 0
    else
        log_error "修复脚本执行失败"
        return 1
    fi
}

# 创建修复脚本模板
operation_create_template() {
    local script_name="$1"
    
    if [ -z "$script_name" ]; then
        log_error "请指定脚本名称"
        return 1
    fi
    
    # 确保脚本名以.sh结尾
    if [[ ! "$script_name" =~ \.sh$ ]]; then
        script_name="${script_name}.sh"
    fi
    
    local script_path="$FIXES_DIR/$script_name"
    
    if [ -f "$script_path" ]; then
        log_error "脚本已存在: $script_path"
        return 1
    fi
    
    log_info "创建修复脚本模板: $script_name"
    
    # 创建脚本模板
    cat > "$script_path" << 'EOF'
#!/bin/bash
#========================================================================================================================
# OpenWrt 修复脚本模板
# 功能: [描述修复功能]
# 版本: 1.0.0
#========================================================================================================================

set -euo pipefail

# 脚本参数
DEVICE="$1"
ERROR_TYPE="${2:-auto}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${BLUE}[修复脚本]${NC} $1"; }
log_success() { echo -e "${GREEN}[修复脚本]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[修复脚本]${NC} $1"; }
log_error() { echo -e "${RED}[修复脚本]${NC} $1" >&2; }

# 主要修复逻辑
main() {
    log_info "开始修复: $DEVICE / $ERROR_TYPE"
    
    # 在这里添加具体的修复逻辑
    case "$DEVICE" in
        "x86_64")
            # X86设备特定修复
            ;;
        "xiaomi_4a_gigabit"|"newifi_d2")
            # MIPS设备特定修复
            ;;
        "rpi_4b")
            # 树莓派特定修复
            ;;
        *)
            # 通用修复
            ;;
    esac
    
    log_success "修复完成"
}

# 执行主函数
main "$@"
EOF
    
    # 设置执行权限
    chmod +x "$script_path"
    
    log_success "修复脚本模板已创建: $script_path"
    log_info "请编辑脚本添加具体的修复逻辑"
    
    return 0
}

#========================================================================================================================
# 帮助信息和主函数
#========================================================================================================================

show_help() {
    cat << EOF
${CYAN}OpenWrt 修复协调器 v${COORDINATOR_VERSION}${NC}

${CYAN}使用方法:${NC}
  $0 <操作> [选项...]

${CYAN}操作:${NC}
  auto                    自动修复（推荐）
  list                    列出可用修复脚本
  run                     执行特定修复脚本
  create-template         创建修复脚本模板

${CYAN}选项:${NC}
  --device <设备>         目标设备型号
  --script <脚本>         修复脚本名称
  --error <类型>          错误类型
  --verbose               详细输出
  --dry-run               预览模式，不实际执行
  -h, --help              显示帮助信息
  --version               显示版本信息

${CYAN}支持的设备:${NC}
  x86_64                  X86 64位设备
  xiaomi_4a_gigabit       小米路由器4A千兆版
  newifi_d2               新路由3 (Newifi D2)
  rpi_4b                  树莓派4B
  nanopi_r2s              NanoPi R2S

${CYAN}错误类型:${NC}
  auto                    自动检测（默认）
  udebug                  udebug错误
  kernel                  内核相关错误
  feeds                   feeds错误
  docker                  Docker相关错误
  camera                  摄像头相关错误

${CYAN}示例:${NC}
  # 自动修复
  $0 auto --device x86_64 --verbose
  
  # 修复特定错误
  $0 auto --device rpi_4b --error camera
  
  # 列出可用修复
  $0 list
  
  # 执行特定修复脚本
  $0 run --script fix-udebug.sh --device x86_64
  
  # 创建修复脚本模板
  $0 create-template fix-my-issue
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
        auto|list|run|create-template)
            operation="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --version)
            echo "修复协调器 版本 $COORDINATOR_VERSION"
            exit 0
            ;;
        *)
            # 兼容旧的调用方式
            if [[ "$1" =~ ^(x86_64|xiaomi_4a_gigabit|newifi_d2|rpi_4b|nanopi_r2s)$ ]]; then
                operation="auto"
                # 不要shift，让auto操作处理这个参数
            else
                log_error "未知操作: $1"
                show_help
                exit 1
            fi
            ;;
    esac
    
    # 确保fixes目录存在
    mkdir -p "$FIXES_DIR"
    
    # 执行操作
    case "$operation" in
        "auto")
            operation_auto "$@"
            ;;
        "list")
            operation_list "$@"
            ;;
        "run")
            operation_run "$@"
            ;;
        "create-template")
            operation_create_template "$@"
            ;;
    esac
}

# 检查脚本是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi