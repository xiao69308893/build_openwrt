#!/bin/bash
#========================================================================================================================
# OpenWrt 构建协调器 - 修复版本
# 功能: 统一协调整个构建流程，接管原smart-build.yml中的复杂逻辑
# 版本: 2.0.1 (修复版本)
#========================================================================================================================

# 使用更宽松的错误处理，避免意外退出
set -eo pipefail

# 脚本版本和基础信息
readonly COORDINATOR_VERSION="2.0.1"
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

# 标准化日志函数 - 增加错误处理
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$(date)")
    
    case "$level" in
        "INFO")    echo -e "${BLUE}[INFO]${NC} [$timestamp] $message" || true ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} [$timestamp] $message" || true ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} [$timestamp] $message" || true ;;
        "ERROR")   echo -e "${RED}[ERROR]${NC} [$timestamp] $message" >&2 || true ;;
        "DEBUG")   [ "$VERBOSE" = true ] && echo -e "${PURPLE}[DEBUG]${NC} [$timestamp] $message" || true ;;
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

# 错误处理函数 - 简化实现
handle_error() {
    local exit_code=$?
    local line_number=${1:-"未知"}
    
    log_error "脚本在第 $line_number 行发生错误 (退出码: $exit_code)"
    
    # 如果启用了自动修复，尝试恢复
    if [ "$AUTO_FIX" = true ]; then
        log_info "尝试自动错误恢复..."
        auto_error_recovery "$exit_code" "$line_number" || true
    fi
    
    exit $exit_code
}

# 设置错误处理 - 使用更安全的方式
trap 'handle_error $LINENO' ERR

#========================================================================================================================
# 模块接口 - 标准化的模块调用
#========================================================================================================================

# 调用模块的标准接口 - 增强错误处理
call_module() {
    local module_name="${1:-}"
    local operation="${2:-}"
    
    if [ -z "$module_name" ] || [ -z "$operation" ]; then
        log_error "模块调用参数不完整: module_name='$module_name', operation='$operation'"
        return 1
    fi
    
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
    
    # 确保脚本有执行权限
    chmod +x "$module_script" 2>/dev/null || true
    
    # 执行模块，捕获错误
    if "$module_script" "$operation" "${args[@]}"; then
        local exit_code=$?
        log_debug "模块执行成功: $module_name"
        return $exit_code
    else
        local exit_code=$?
        log_error "模块执行失败: $module_name (退出码: $exit_code)"
        return $exit_code
    fi
}

#========================================================================================================================
# 配置管理 - 统一的配置接口
#========================================================================================================================

# 创建构建配置文件 - 增强参数验证
create_build_config() {
    local source_branch="${1:-}"
    local target_device="${2:-}"
    local plugins="${3:-}"
    local description="${4:-智能编译}"
    
    # 参数验证
    if [ -z "$source_branch" ] || [ -z "$target_device" ]; then
        log_error "创建构建配置失败: 缺少必需参数"
        return 1
    fi
    
    # 生成唯一的构建ID
    local build_id="build_$(date +%s)_$$"
    local build_tag="OpenWrt_${target_device}_$(date +%Y%m%d_%H%M%S)"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)
    
    # 确保配置目录存在
    mkdir -p "$BUILD_TEMP_DIR" || {
        log_error "无法创建临时目录: $BUILD_TEMP_DIR"
        return 1
    }
    
    # 生成构建配置文件
    BUILD_CONFIG_FILE="$BUILD_TEMP_DIR/build_config_${build_id}.json"
    
    # 创建配置文件，添加错误处理
if ! cat > "$BUILD_CONFIG_FILE" << EOF
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
    then
        log_error "创建构建配置文件失败: $BUILD_CONFIG_FILE"
        return 1
    fi
    
    log_success "构建配置已创建: $BUILD_CONFIG_FILE" >&2  # 日志输出到stderr
    echo "$BUILD_CONFIG_FILE"  # 只有文件路径输出到stdout
}

# 从配置文件读取值 - 修复 $2 未绑定变量问题
get_config_value() {
    local key_path="${1:-}"
    local default_value="${2:-}"  # 提供默认的默认值，避免未绑定变量错误
    
    # 参数验证
    if [ -z "$key_path" ]; then
        log_error "get_config_value: 缺少key_path参数"
        echo "$default_value"
        return 1
    fi
    
    # 检查配置文件是否存在
    if [ ! -f "$BUILD_CONFIG_FILE" ]; then
        log_debug "配置文件不存在: $BUILD_CONFIG_FILE"
        echo "$default_value"
        return 0
    fi
    
    # 检查jq命令是否可用
    if ! command -v jq &> /dev/null; then
        log_debug "jq命令不可用，返回默认值"
        echo "$default_value"
        return 0
    fi
    
    # 读取配置值
    local value=$(jq -r "$key_path" "$BUILD_CONFIG_FILE" 2>/dev/null || echo "")
    
    if [ -n "$value" ] && [ "$value" != "null" ]; then
        echo "$value"
    else
        echo "$default_value"
    fi
}

#========================================================================================================================
# 主要操作函数
#========================================================================================================================

# 准备构建参数和配置 - 修复版本
operation_prepare() {
    local source_branch=""
    local target_device=""
    local plugins=""
    local description=""
    local output_env=false
    
    # 解析参数 - 增强错误处理
    while [[ $# -gt 0 ]]; do
        case $1 in
            --source)
                if [ -n "${2:-}" ]; then
                    source_branch="$2"
                    shift 2
                else
                    log_error "缺少 --source 参数值"
                    return 1
                fi
                ;;
            --device)
                if [ -n "${2:-}" ]; then
                    target_device="$2"
                    shift 2
                else
                    log_error "缺少 --device 参数值"
                    return 1
                fi
                ;;
            --plugins)
                plugins="${2:-}"  # 插件列表可以为空
                shift 2
                ;;
            --description)
                description="${2:-智能编译}"
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
        log_error "缺少必需参数: source_branch='$source_branch', target_device='$target_device'"
        return 1
    fi
    
    # 设置默认值
    description="${description:-智能编译}"
    plugins="${plugins:-}"
    
    log_debug "构建参数: source_branch=$source_branch, target_device=$target_device, plugins='$plugins', description='$description'"
    
    # 调用设备适配器验证设备
    log_info "验证目标设备..."
    if ! call_module "device-adapter" "validate" --device "$target_device"; then
        log_error "设备验证失败: $target_device"
        return 1
    fi
    
    # 调用插件解析器验证插件（如果有插件）
    if [ -n "$plugins" ]; then
        log_info "验证插件配置..."
        if ! call_module "plugin-resolver" "validate" --plugins "$plugins" --device "$target_device"; then
            log_warning "插件验证发现问题，但继续处理"
        fi
    else
        log_info "未指定额外插件，跳过插件验证"
    fi
    
    # 创建构建配置
    log_info "创建构建配置..."
    local config_file
    if ! config_file=$(create_build_config "$source_branch" "$target_device" "$plugins" "$description"); then
        log_error "创建构建配置失败"
        return 1
    fi
    
    # 获取设备友好名称
    log_info "获取设备信息..."
    local device_name
    if ! device_name=$(call_module "device-adapter" "get-name" --device "$target_device" 2>/dev/null); then
        device_name="$target_device"
        log_warning "无法获取设备友好名称，使用原始名称: $device_name"
    fi
    
    # 输出GitHub Actions环境变量 - 修复格式问题
    if [ "$output_env" = true ]; then
        log_info "输出环境变量到GitHub Actions..."
        
        # 检查 GITHUB_OUTPUT 环境变量
        if [ -z "${GITHUB_OUTPUT:-}" ]; then
            log_warning "GITHUB_OUTPUT 环境变量未设置，尝试创建临时文件"
            export GITHUB_OUTPUT="/tmp/github_output_$$.txt"
            touch "$GITHUB_OUTPUT" || {
                log_error "无法创建GitHub输出文件"
                return 1
            }
        fi
        
        # 安全地写入环境变量，使用printf避免格式问题
        {
            printf "build_config=%s\n" "$config_file"
            printf "source_branch=%s\n" "$source_branch"
            printf "target_device=%s\n" "$target_device"
            printf "plugins_list=%s\n" "$plugins"
            printf "build_tag=%s\n" "$(get_config_value '.build_info.build_tag' 'OpenWrt_Build')"
            printf "device_name=%s\n" "$device_name"
        } >> "$GITHUB_OUTPUT" || {
            log_error "写入GitHub Actions环境变量失败"
            return 1
        }
        
        log_success "环境变量输出完成"
    fi
    
    log_success "构建参数准备完成"
    log_info "配置文件: $config_file"
    log_info "目标设备: $device_name ($target_device)"
    log_info "源码分支: $source_branch"
    if [ -n "$plugins" ]; then
        log_info "插件列表: $plugins"
    fi
    
    return 0
}

# 执行完整构建流程 - 占位实现
operation_build() {
    local config_file=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config-file)
                config_file="${2:-}"
                if [ -n "$config_file" ]; then
                    BUILD_CONFIG_FILE="$config_file"
                    shift 2
                else
                    log_error "缺少 --config-file 参数值"
                    return 1
                fi
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
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        log_error "配置文件不存在或未指定: $config_file"
        return 1
    fi
    
    log_info "开始构建流程..."
    log_info "配置文件: $config_file"
    
    # TODO: 实现实际的构建逻辑
    log_warning "构建功能尚未完全实现，这是占位函数"
    
    return 0
}

# 整理编译产物 - 占位实现
operation_organize() {
    local config_file=""
    local device=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config-file)
                config_file="${2:-}"
                shift 2
                ;;
            --device)
                device="${2:-}"
                shift 2
                ;;
            *)
                log_error "未知参数: $1"
                return 1
                ;;
        esac
    done
    
    log_info "整理编译产物..."
    
    # TODO: 实现产物整理逻辑
    log_warning "产物整理功能尚未完全实现，这是占位函数"
    
    return 0
}

# 生成构建通知 - 占位实现
operation_notify() {
    log_info "生成构建通知..."
    
    # TODO: 实现通知逻辑
    log_warning "通知功能尚未完全实现，这是占位函数"
    
    return 0
}

# 自动错误恢复
auto_error_recovery() {
    local exit_code="${1:-1}"
    local line_number="${2:-未知}"
    
    log_info "执行自动错误恢复..."
    
    # 根据错误类型进行恢复
    case $exit_code in
        1)
            log_info "尝试清理临时文件..."
            rm -rf "$BUILD_TEMP_DIR"/*.tmp 2>/dev/null || true
            ;;
        2)
            log_info "尝试重新初始化环境..."
            # call_module "env-checker" "reset" 2>/dev/null || true
            ;;
        *)
            log_info "执行通用错误恢复..."
            ;;
    esac
    
    return 0
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

${CYAN}修复版本说明:${NC}
  - 修复了 \$2 未绑定变量的问题
  - 改进了GitHub Actions输出格式
  - 增强了参数验证和错误处理
  - 使用更宽松的错误处理模式
EOF
}

# 主函数 - 增强错误处理
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
    mkdir -p "$BUILD_TEMP_DIR" || {
        log_error "无法创建临时目录: $BUILD_TEMP_DIR"
        exit 1
    }
    
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