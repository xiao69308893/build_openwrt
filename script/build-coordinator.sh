#!/bin/bash
#========================================================================================================================
# OpenWrt 构建协调器 - 重构后的主控脚本
# 功能: 统一协调整个构建流程，接管原smart-build.yml中的复杂逻辑
# 版本: 2.0.0
#========================================================================================================================

set -euo pipefail

# 脚本版本和基础信息
readonly COORDINATOR_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly CONFIG_DIR="$PROJECT_ROOT/config"
readonly BUILD_TEMP_DIR="$PROJECT_ROOT/.build_temp"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# 全局变量
BUILD_CONFIG_FILE=""
AUTO_FIX=false
VERBOSE=false
DRY_RUN=false

#========================================================================================================================
# 基础工具函数
#========================================================================================================================

# 标准化日志函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")    echo -e "${BLUE}[INFO]${NC} [$timestamp] $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} [$timestamp] $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} [$timestamp] $message" ;;
        "ERROR")   echo -e "${RED}[ERROR]${NC} [$timestamp] $message" >&2 ;;
        "DEBUG")   [ "$VERBOSE" = true ] && echo -e "${PURPLE}[DEBUG]${NC} [$timestamp] $message" ;;
    esac
}

# 便捷日志函数
log_info() { log "INFO" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_warning() { log "WARNING" "$1"; }
log_error() { log "ERROR" "$1"; }
log_debug() { log "DEBUG" "$1"; }

# 显示协调器标题
show_header() {
    echo -e "${CYAN}"
    echo "========================================================================================================================="
    echo "                                    🎭 OpenWrt 构建协调器 v${COORDINATOR_VERSION}"
    echo "                                       重构版本 | 模块化架构 | 智能编译"
    echo "========================================================================================================================="
    echo -e "${NC}"
}

# 错误处理函数
handle_error() {
    local exit_code=$?
    local line_number=$1
    
    log_error "脚本在第 $line_number 行发生错误 (退出码: $exit_code)"
    
    # 如果启用了自动修复，尝试恢复
    if [ "$AUTO_FIX" = true ]; then
        log_info "尝试自动错误恢复..."
        auto_error_recovery "$exit_code" "$line_number"
    fi
    
    exit $exit_code
}

# 设置错误处理
trap 'handle_error $LINENO' ERR

#========================================================================================================================
# 模块接口 - 标准化的模块调用
#========================================================================================================================

# 调用模块的标准接口
call_module() {
    local module_name="$1"
    local operation="$2"
    shift 2
    local args=("$@")
    
    log_debug "调用模块: $module_name -> $operation"
    
    # 确定模块脚本路径
    local module_script=""
    case "$module_name" in
        "config-generator")
            module_script="$SCRIPT_DIR/config-generator.sh"
            ;;
        "plugin-resolver")
            module_script="$SCRIPT_DIR/plugin-resolver.sh"
            ;;
        "device-adapter")
            module_script="$SCRIPT_DIR/device-adapter.sh"
            ;;
        "build-validator")
            module_script="$SCRIPT_DIR/build-validator.sh"
            ;;
        "error-handler")
            module_script="$SCRIPT_DIR/modules/error-handler.sh"
            ;;
        "env-checker")
            module_script="$SCRIPT_DIR/modules/env-checker.sh"
            ;;
        "source-manager")
            module_script="$SCRIPT_DIR/modules/source-manager.sh"
            ;;
        "artifact-manager")
            module_script="$SCRIPT_DIR/modules/artifact-manager.sh"
            ;;
        *)
            log_error "未知模块: $module_name"
            return 1
            ;;
    esac
    
    # 检查模块脚本是否存在
    if [ ! -f "$module_script" ]; then
        log_error "模块脚本不存在: $module_script"
        return 1
    fi
    
    # 执行模块
    log_debug "执行: $module_script $operation ${args[*]}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] 模拟执行: $module_name $operation"
        return 0
    fi
    
    chmod +x "$module_script"
    "$module_script" "$operation" "${args[@]}"
    
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log_debug "模块执行成功: $module_name"
    else
        log_error "模块执行失败: $module_name (退出码: $exit_code)"
    fi
    
    return $exit_code
}

#========================================================================================================================
# 配置管理 - 统一的配置接口
#========================================================================================================================

# 创建构建配置文件
create_build_config() {
    local source_branch="$1"
    local target_device="$2"
    local plugins="$3"
    local description="$4"
    
    # 生成唯一的构建ID
    local build_id="build_$(date +%s)_$$"
    local build_tag="OpenWrt_${target_device}_$(date +%Y%m%d_%H%M%S)"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    # 确保配置目录存在
    mkdir -p "$BUILD_TEMP_DIR"
    
    # 生成构建配置文件
    BUILD_CONFIG_FILE="$BUILD_TEMP_DIR/build_config_${build_id}.json"
    
    cat > "$BUILD_CONFIG_FILE" << EOF
{
  "build_info": {
    "build_id": "$build_id",
    "build_tag": "$build_tag",
    "created_at": "$timestamp",
    "description": "$description",
    "coordinator_version": "$COORDINATOR_VERSION"
  },
  "build_params": {
    "source_branch": "$source_branch",
    "target_device": "$target_device",
    "plugins": "$plugins",
    "auto_fix": $AUTO_FIX,
    "verbose": $VERBOSE
  },
  "runtime_config": {
    "project_root": "$PROJECT_ROOT",
    "script_dir": "$SCRIPT_DIR",
    "config_dir": "$CONFIG_DIR",
    "temp_dir": "$BUILD_TEMP_DIR"
  }
}
EOF
    
    log_success "构建配置已创建: $BUILD_CONFIG_FILE"
    echo "$BUILD_CONFIG_FILE"
}

# 从配置文件读取值
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
# 主要操作函数
#========================================================================================================================

# 准备构建参数和配置
operation_prepare() {
    local source_branch=""
    local target_device=""
    local plugins=""
    local description=""
    local output_env=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --source)
                source_branch="$2"
                shift 2
                ;;
            --device)
                target_device="$2"
                shift 2
                ;;
            --plugins)
                plugins="$2"
                shift 2
                ;;
            --description)
                description="$2"
                shift 2
                ;;
            --output-env)
                output_env=true
                shift
                ;;
            *)
                log_error "未知参数: $1"
                return 1
                ;;
        esac
    done
    
    log_info "🔧 准备构建参数..."
    
    # 验证必需参数
    if [ -z "$source_branch" ] || [ -z "$target_device" ]; then
        log_error "缺少必需参数: source_branch 和 target_device"
        return 1
    fi
    
    # 设置默认值
    description="${description:-智能编译}"
    plugins="${plugins:-}"
    
    # 调用设备适配器验证设备
    if ! call_module "device-adapter" "validate" --device "$target_device"; then
        log_error "设备验证失败: $target_device"
        return 1
    fi
    
    # 调用插件解析器验证插件
    if [ -n "$plugins" ]; then
        if ! call_module "plugin-resolver" "validate" --plugins "$plugins" --device "$target_device"; then
            log_warning "插件验证发现问题，但继续处理"
        fi
    fi
    
    # 创建构建配置
    local config_file=$(create_build_config "$source_branch" "$target_device" "$plugins" "$description")
    
    # 获取设备友好名称
    local device_name=$(call_module "device-adapter" "get-name" --device "$target_device" || echo "$target_device")
    
    # 输出GitHub Actions环境变量
    if [ "$output_env" = true ]; then
        echo "build_config=$config_file" >> $GITHUB_OUTPUT
        echo "source_branch=$source_branch" >> $GITHUB_OUTPUT
        echo "target_device=$target_device" >> $GITHUB_OUTPUT
        echo "plugins_list=$plugins" >> $GITHUB_OUTPUT
        echo "build_tag=$(get_config_value '.build_info.build_tag')" >> $GITHUB_OUTPUT
        echo "device_name=$device_name" >> $GITHUB_OUTPUT
    fi
    
    log_success "构建参数准备完成"
    return 0
}

# 执行完整构建流程
operation_build() {
    local config_file=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config-file)
                config_file="$2"
                BUILD_CONFIG_FILE="$config_file"
                shift 2
                ;;
            --auto-fix)
                AUTO_FIX=true
                shift
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
    
    log_info "🚀 开始构建流程..."
    
    # 读取构建参数
    local source_branch=$(get_config_value '.build_params.source_branch')
    local target_device=$(get_config_value '.build_params.target_device')
    local plugins=$(get_config_value '.build_params.plugins')
    
    log_info "构建参数: $source_branch / $target_device / 插件数: $(echo "$plugins" | tr ',' '\n' | wc -l)"
    
    # 步骤1: 环境检查
    log_info "📋 步骤1: 环境检查"
    if ! call_module "env-checker" "full-check"; then
        if [ "$AUTO_FIX" = true ]; then
            log_info "尝试自动修复环境问题..."
            call_module "env-checker" "auto-fix"
        else
            log_error "环境检查失败"
            return 1
        fi
    fi
    
    # 步骤2: 源码管理
    log_info "📦 步骤2: 源码管理"
    if ! call_module "source-manager" "prepare" --branch "$source_branch" --config "$BUILD_CONFIG_FILE"; then
        log_error "源码准备失败"
        return 1
    fi
    
    # 步骤3: 配置生成
    log_info "⚙️ 步骤3: 配置生成"
    if ! call_module "config-generator" "generate" --config "$BUILD_CONFIG_FILE"; then
        log_error "配置生成失败"
        return 1
    fi
    
    # 步骤4: 构建验证
    log_info "🔍 步骤4: 构建验证"
    if ! call_module "build-validator" "pre-build" --config "$BUILD_CONFIG_FILE"; then
        if [ "$AUTO_FIX" = true ]; then
            log_info "尝试自动修复构建问题..."
            call_module "error-handler" "auto-fix" --config "$BUILD_CONFIG_FILE"
        else
            log_error "构建验证失败"
            return 1
        fi
    fi
    
    # 步骤5: 执行编译
    log_info "🔨 步骤5: 执行编译"
    if ! execute_compilation; then
        log_error "编译失败"
        return 1
    fi
    
    # 输出构建状态
    echo "status=success" >> $GITHUB_OUTPUT
    log_success "构建流程完成"
    return 0
}

# 执行实际编译（核心编译逻辑）
execute_compilation() {
    log_info "开始OpenWrt编译..."
    
    # 获取CPU核心数
    local cpu_cores=$(nproc)
    local make_jobs=$((cpu_cores + 1))
    
    log_info "编译配置: ${make_jobs}并行任务"
    
    # 更新feeds
    log_info "更新feeds..."
    ./scripts/feeds update -a
    ./scripts/feeds install -a
    
    # 生成配置
    log_info "生成最终配置..."
    make defconfig
    
    # 下载依赖包
    log_info "下载依赖包..."
    make download -j${make_jobs}
    
    # 开始编译，先尝试并行编译
    log_info "开始并行编译..."
    if ! make -j${make_jobs} V=s; then
        log_warning "并行编译失败，切换到单线程编译..."
        
        # 如果启用自动修复，先尝试修复
        if [ "$AUTO_FIX" = true ]; then
            log_info "尝试自动修复编译错误..."
            call_module "error-handler" "fix-compilation-errors" --config "$BUILD_CONFIG_FILE"
        fi
        
        # 单线程重试
        if ! make -j1 V=s; then
            log_error "编译失败"
            return 1
        fi
    fi
    
    log_success "编译完成"
    return 0
}

# 整理编译产物
operation_organize() {
    local config_file=""
    local target_device=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config-file)
                config_file="$2"
                BUILD_CONFIG_FILE="$config_file"
                shift 2
                ;;
            --device)
                target_device="$2"
                shift 2
                ;;
            *)
                log_error "未知参数: $1"
                return 1
                ;;
        esac
    done
    
    log_info "📦 整理编译产物..."
    
    # 调用产物管理器
    if ! call_module "artifact-manager" "organize" --config "$BUILD_CONFIG_FILE" --device "$target_device"; then
        log_error "产物整理失败"
        return 1
    fi
    
    log_success "产物整理完成"
    return 0
}

# 构建通知
operation_notify() {
    local config_file=""
    local build_status=""
    local run_id=""
    local repository=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config-file)
                config_file="$2"
                BUILD_CONFIG_FILE="$config_file"
                shift 2
                ;;
            --build-status)
                build_status="$2"
                shift 2
                ;;
            --run-id)
                run_id="$2"
                shift 2
                ;;
            --repository)
                repository="$2"
                shift 2
                ;;
            *)
                log_error "未知参数: $1"
                return 1
                ;;
        esac
    done
    
    log_info "📱 生成构建通知..."
    
    # 生成构建报告
    generate_build_report "$build_status" "$run_id" "$repository"
    
    log_success "通知完成"
    return 0
}

# 生成构建报告
generate_build_report() {
    local build_status="$1"
    local run_id="$2"
    local repository="$3"
    
    local source_branch=$(get_config_value '.build_params.source_branch' '未知')
    local target_device=$(get_config_value '.build_params.target_device' '未知')
    local plugins=$(get_config_value '.build_params.plugins' '')
    local build_tag=$(get_config_value '.build_info.build_tag' '未知')
    
    echo "=========================================================="
    if [ "$build_status" = "success" ]; then
        echo "🎉 OpenWrt智能编译成功完成!"
        echo ""
        echo "📦 固件信息:"
        echo "  源码分支: $source_branch"
        echo "  目标设备: $target_device"
        echo "  固件标签: $build_tag"
        echo "  插件列表: ${plugins:-无额外插件}"
        echo ""
        echo "📥 下载方式:"
        echo "  1. GitHub Actions Artifacts (7天有效期)"
        echo "  2. GitHub Releases (长期保存)"
        echo ""
        echo "🔗 相关链接:"
        echo "  - Actions: https://github.com/$repository/actions/runs/$run_id"
        echo "  - Releases: https://github.com/$repository/releases"
    else
        echo "❌ OpenWrt编译失败"
        echo ""
        echo "📋 失败信息:"
        echo "  源码分支: $source_branch"
        echo "  目标设备: $target_device"
        echo "  插件列表: ${plugins:-无额外插件}"
        echo ""
        echo "🔍 可能的失败原因:"
        echo "  1. 插件配置冲突"
        echo "  2. 设备存储空间不足"
        echo "  3. 网络连接问题"
        echo "  4. 源码或依赖包问题"
        echo ""
        echo "🔗 编译日志: https://github.com/$repository/actions/runs/$run_id"
    fi
    echo "=========================================================="
}

# 自动错误恢复
auto_error_recovery() {
    local exit_code="$1"
    local line_number="$2"
    
    log_info "执行自动错误恢复..."
    
    # 根据错误类型进行恢复
    case $exit_code in
        1)
            log_info "尝试清理临时文件..."
            rm -rf "$BUILD_TEMP_DIR"/*.tmp 2>/dev/null || true
            ;;
        2)
            log_info "尝试重新初始化环境..."
            call_module "env-checker" "reset" 2>/dev/null || true
            ;;
        *)
            log_info "执行通用错误恢复..."
            ;;
    esac
}

#========================================================================================================================
# 帮助信息和主函数
#========================================================================================================================

# 显示帮助信息
show_help() {
    cat << EOF
${CYAN}OpenWrt 构建协调器 v${COORDINATOR_VERSION}${NC}

${CYAN}使用方法:${NC}
  $0 <操作> [选项...]

${CYAN}操作:${NC}
  prepare               准备构建参数和配置
  build                 执行完整构建流程
  organize              整理编译产物
  notify                生成构建通知

${CYAN}prepare 操作选项:${NC}
  --source <分支>       源码分支
  --device <设备>       目标设备
  --plugins <插件>      插件列表（逗号分隔）
  --description <描述>  构建描述
  --output-env          输出GitHub Actions环境变量

${CYAN}build 操作选项:${NC}
  --config-file <文件>  构建配置文件
  --auto-fix            启用自动修复
  --verbose             详细输出

${CYAN}organize 操作选项:${NC}
  --config-file <文件>  构建配置文件
  --device <设备>       目标设备

${CYAN}全局选项:${NC}
  --dry-run             预览模式，不实际执行
  -h, --help            显示帮助信息
  --version             显示版本信息

${CYAN}示例:${NC}
  # 准备构建参数
  $0 prepare --source lede-master --device x86_64 --plugins "luci-app-ssr-plus" --output-env
  
  # 执行构建
  $0 build --config-file /tmp/build_config.json --auto-fix --verbose
  
  # 整理产物
  $0 organize --config-file /tmp/build_config.json --device x86_64
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
    
    # 解析全局参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            prepare|build|organize|notify)
                operation="$1"
                shift
                break
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                echo "OpenWrt 构建协调器 版本 $COORDINATOR_VERSION"
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 显示标题
    show_header
    
    # 创建临时目录
    mkdir -p "$BUILD_TEMP_DIR"
    
    # 执行对应操作
    case "$operation" in
        "prepare")
            operation_prepare "$@"
            ;;
        "build")
            operation_build "$@"
            ;;
        "organize")
            operation_organize "$@"
            ;;
        "notify")
            operation_notify "$@"
            ;;
        "")
            log_error "请指定操作"
            show_help
            exit 1
            ;;
        *)
            log_error "未知操作: $operation"
            exit 1
            ;;
    esac
}

# 检查脚本是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi