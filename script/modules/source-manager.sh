#!/bin/bash
#========================================================================================================================
# OpenWrt 源码管理模块
# 功能: 源码下载、分支切换、feeds更新、补丁应用
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
BUILD_CONFIG_FILE=""
VERBOSE=false

#========================================================================================================================
# 基础工具函数
#========================================================================================================================

# 日志函数
log_info() { echo -e "${BLUE}[SOURCE-MANAGER]${NC} $1"; }
log_success() { echo -e "${GREEN}[SOURCE-MANAGER]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[SOURCE-MANAGER]${NC} $1"; }
log_error() { echo -e "${RED}[SOURCE-MANAGER]${NC} $1" >&2; }
log_debug() { [ "$VERBOSE" = true ] && echo -e "${CYAN}[SOURCE-MANAGER-DEBUG]${NC} $1"; }

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
# 源码仓库定义
#========================================================================================================================

# 获取源码仓库信息
get_source_info() {
    local branch="$1"
    
    case "$branch" in
        "lede-master")
            echo "https://github.com/coolsnowwolf/lede.git" "master" "Lean的LEDE源码"
            ;;
        "openwrt-main")
            echo "https://git.openwrt.org/openwrt/openwrt.git" "main" "OpenWrt官方主线"
            ;;
        "immortalwrt-master")
            echo "https://github.com/immortalwrt/immortalwrt.git" "master" "ImmortalWrt源码"
            ;;
        "Lienol-master")
            echo "https://github.com/Lienol/openwrt.git" "main" "Lienol的OpenWrt"
            ;;
        *)
            log_error "不支持的源码分支: $branch"
            return 1
            ;;
    esac
}

# 验证源码分支
validate_source_branch() {
    local branch="$1"
    
    local source_info=($(get_source_info "$branch" 2>/dev/null))
    if [ ${#source_info[@]} -eq 3 ]; then
        return 0
    else
        return 1
    fi
}

#========================================================================================================================
# 源码操作函数
#========================================================================================================================

# 检查源码状态
check_source_status() {
    log_debug "检查源码状态..."
    
    # 检查是否在Git仓库中
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        log_warning "当前目录不是Git仓库"
        return 1
    fi
    
    # 获取当前分支和远程信息
    local current_branch=$(git branch --show-current 2>/dev/null || echo "分离头指针")
    local remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "无远程仓库")
    local commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "无提交")
    local commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    
    log_info "源码状态:"
    echo "  当前分支: $current_branch"
    echo "  远程仓库: $remote_url"
    echo "  提交哈希: ${commit_hash:0:8}"
    echo "  提交数量: $commit_count"
    
    # 检查工作区状态
    if ! git diff-index --quiet HEAD 2>/dev/null; then
        log_warning "工作区有未提交的更改"
        return 1
    fi
    
    return 0
}

# 清理源码目录
clean_source_directory() {
    log_info "清理源码目录..."
    
    # 清理编译产物
    if [ -f "Makefile" ]; then
        log_debug "执行 make clean..."
        make clean &>/dev/null || true
    fi
    
    # 清理Git状态
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        log_debug "重置Git状态..."
        git reset --hard HEAD &>/dev/null || true
        git clean -fd &>/dev/null || true
    fi
    
    # 清理特定目录
    local clean_dirs=(
        "bin" "build_dir" "staging_dir" "tmp" "logs"
        "dl/.tmp" "feeds/packages" "feeds/luci" "feeds/routing"
        "feeds/telephony" "feeds/management"
    )
    
    for dir in "${clean_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_debug "清理目录: $dir"
            rm -rf "$dir"
        fi
    done
    
    log_success "源码目录清理完成"
}

# 更新源码
update_source_code() {
    local target_branch="$1"
    
    log_info "更新源码到分支: $target_branch"
    
    # 获取源码信息
    local source_info=($(get_source_info "$target_branch"))
    local repo_url="${source_info[0]}"
    local branch_name="${source_info[1]}"
    local description="${source_info[2]}"
    
    log_debug "仓库URL: $repo_url"
    log_debug "分支名称: $branch_name"
    log_debug "描述: $description"
    
    # 如果当前不是Git仓库，执行克隆
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        log_info "初始化源码仓库..."
        return clone_source_repository "$repo_url" "$branch_name"
    fi
    
    # 检查远程仓库是否匹配
    local current_remote=$(git config --get remote.origin.url 2>/dev/null || echo "")
    if [ "$current_remote" != "$repo_url" ]; then
        log_warning "当前仓库与目标仓库不匹配"
        log_info "当前: $current_remote"
        log_info "目标: $repo_url"
        
        # 重新设置远程仓库
        git remote set-url origin "$repo_url"
        log_info "已更新远程仓库URL"
    fi
    
    # 获取最新更改
    log_info "获取最新更改..."
    if ! git fetch origin "$branch_name" --depth=1; then
        log_error "获取源码更改失败"
        return 1
    fi
    
    # 切换到目标分支
    log_info "切换到分支: $branch_name"
    if ! git checkout -B "$branch_name" "origin/$branch_name"; then
        log_error "分支切换失败"
        return 1
    fi
    
    # 显示更新信息
    local latest_commit=$(git log -1 --pretty=format:"%h %s (%cr)")
    log_success "源码更新完成"
    log_info "最新提交: $latest_commit"
    
    return 0
}

# 克隆源码仓库
clone_source_repository() {
    local repo_url="$1"
    local branch_name="$2"
    
    log_info "克隆源码仓库..."
    log_debug "URL: $repo_url"
    log_debug "分支: $branch_name"
    
    # 清理现有目录（如果存在）
    if [ "$(ls -A . 2>/dev/null)" ]; then
        log_warning "当前目录不为空，清理现有文件..."
        rm -rf ./* .[^.]* 2>/dev/null || true
    fi
    
    # 执行克隆
    if ! git clone --single-branch --branch "$branch_name" --depth=1 "$repo_url" .; then
        log_error "源码克隆失败"
        return 1
    fi
    
    log_success "源码克隆完成"
    return 0
}

#========================================================================================================================
# Feeds管理
#========================================================================================================================

# 更新feeds配置
update_feeds_config() {
    log_info "更新feeds配置..."
    
    # 检查feeds配置文件
    local feeds_file=""
    if [ -f "feeds.conf" ]; then
        feeds_file="feeds.conf"
    elif [ -f "feeds.conf.default" ]; then
        feeds_file="feeds.conf.default"
    else
        log_error "未找到feeds配置文件"
        return 1
    fi
    
    log_debug "使用feeds配置: $feeds_file"
    
    # 备份原始配置
    if [ -f "$feeds_file" ]; then
        cp "$feeds_file" "$feeds_file.backup"
        log_debug "已备份feeds配置"
    fi
    
    # 如果存在自定义feeds配置，使用它
    if [ -f "feeds.conf.default" ] && [ "$feeds_file" != "feeds.conf.default" ]; then
        log_info "使用自定义feeds配置"
        cp "feeds.conf.default" "feeds.conf"
        feeds_file="feeds.conf"
    fi
    
    log_success "feeds配置更新完成"
    return 0
}

# 更新和安装feeds
update_and_install_feeds() {
    log_info "更新和安装feeds..."
    
    # 确保feeds脚本可执行
    if [ ! -x "scripts/feeds" ]; then
        log_error "feeds脚本不存在或不可执行"
        return 1
    fi
    
    # 清理旧的feeds
    log_debug "清理旧的feeds..."
    rm -rf feeds/packages feeds/luci feeds/routing feeds/telephony feeds/management 2>/dev/null || true
    
    # 更新feeds
    log_info "更新feeds源..."
    if ! ./scripts/feeds update -a; then
        log_error "feeds更新失败"
        return 1
    fi
    
    # 安装feeds
    log_info "安装feeds包..."
    if ! ./scripts/feeds install -a; then
        log_error "feeds安装失败"
        return 1
    fi
    
    # 显示feeds统计
    local feeds_count=$(find feeds -name "Makefile" | wc -l)
    log_success "feeds安装完成，共 $feeds_count 个包"
    
    return 0
}

# 安装特定feeds
install_specific_feeds() {
    local feeds_list="$1"
    
    if [ -z "$feeds_list" ]; then
        log_debug "没有指定特定feeds，跳过"
        return 0
    fi
    
    log_info "安装特定feeds包..."
    
    # 解析feeds列表
    IFS=',' read -ra feeds_array <<< "$feeds_list"
    
    for feed in "${feeds_array[@]}"; do
        feed=$(echo "$feed" | xargs)  # 去除空白字符
        
        if [ -n "$feed" ]; then
            log_debug "安装feeds: $feed"
            if ! ./scripts/feeds install "$feed"; then
                log_warning "feeds安装失败: $feed"
            fi
        fi
    done
    
    log_success "特定feeds安装完成"
    return 0
}

#========================================================================================================================
# 补丁和自定义脚本
#========================================================================================================================

# 应用自定义脚本
apply_custom_scripts() {
    local source_branch="$1"
    
    log_info "应用自定义脚本..."
    
    # 查找并执行diy脚本
    local script_patterns=("diy-part1.sh" "diy.sh" "$source_branch-diy.sh")
    
    for pattern in "${script_patterns[@]}"; do
        if [ -f "$pattern" ]; then
            log_info "执行自定义脚本: $pattern"
            chmod +x "$pattern"
            
            if ! ./"$pattern"; then
                log_warning "自定义脚本执行失败: $pattern"
            else
                log_success "自定义脚本执行完成: $pattern"
            fi
        fi
    done
    
    return 0
}

# 应用补丁文件
apply_patches() {
    local patch_dir="patches"
    
    if [ ! -d "$patch_dir" ]; then
        log_debug "补丁目录不存在，跳过补丁应用"
        return 0
    fi
    
    log_info "应用补丁文件..."
    
    # 查找补丁文件
    local patches=($(find "$patch_dir" -name "*.patch" -type f | sort))
    
    if [ ${#patches[@]} -eq 0 ]; then
        log_debug "没有找到补丁文件"
        return 0
    fi
    
    log_info "找到 ${#patches[@]} 个补丁文件"
    
    # 应用每个补丁
    for patch in "${patches[@]}"; do
        log_debug "应用补丁: $patch"
        
        if ! patch -p1 < "$patch"; then
            log_warning "补丁应用失败: $patch"
        else
            log_debug "补丁应用成功: $patch"
        fi
    done
    
    log_success "补丁应用完成"
    return 0
}

#========================================================================================================================
# 主要操作函数
#========================================================================================================================

# 准备源码
operation_prepare() {
    local branch=""
    local config_file=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --branch)
                branch="$2"
                shift 2
                ;;
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
    
    # 从配置文件读取分支信息
    if [ -z "$branch" ] && [ -n "$BUILD_CONFIG_FILE" ]; then
        branch=$(get_config_value '.build_params.source_branch' '')
    fi
    
    if [ -z "$branch" ]; then
        log_error "请指定源码分支"
        return 1
    fi
    
    log_info "🚀 准备源码: $branch"
    
    # 验证分支
    if ! validate_source_branch "$branch"; then
        log_error "不支持的源码分支: $branch"
        return 1
    fi
    
    # 执行源码准备步骤
    local prepare_steps=()
    
    # 步骤1: 检查当前状态
    log_info "1️⃣ 检查源码状态"
    check_source_status || prepare_steps+=("状态检查有问题")
    
    # 步骤2: 清理源码目录
    log_info "2️⃣ 清理源码目录"
    clean_source_directory
    prepare_steps+=("✅ 目录清理完成")
    
    # 步骤3: 更新源码
    log_info "3️⃣ 更新源码"
    if ! update_source_code "$branch"; then
        prepare_steps+=("❌ 源码更新失败")
        return 1
    else
        prepare_steps+=("✅ 源码更新完成")
    fi
    
    # 步骤4: 更新feeds配置
    log_info "4️⃣ 更新feeds配置"
    if ! update_feeds_config; then
        prepare_steps+=("⚠️ feeds配置更新有问题")
    else
        prepare_steps+=("✅ feeds配置更新完成")
    fi
    
    # 步骤5: 更新和安装feeds
    log_info "5️⃣ 更新和安装feeds"
    if ! update_and_install_feeds; then
        prepare_steps+=("❌ feeds安装失败")
        return 1
    else
        prepare_steps+=("✅ feeds安装完成")
    fi
    
    # 步骤6: 应用自定义脚本和补丁
    log_info "6️⃣ 应用自定义内容"
    apply_custom_scripts "$branch"
    apply_patches
    prepare_steps+=("✅ 自定义内容应用完成")
    
    # 显示准备结果
    echo ""
    log_info "📋 源码准备结果:"
    for step in "${prepare_steps[@]}"; do
        echo "  $step"
    done
    
    echo ""
    log_success "🎉 源码准备完成，可以开始配置和编译"
    return 0
}

# 检查源码
operation_check() {
    log_info "🔍 检查源码状态..."
    
    # 基础检查
    check_source_status
    
    # 检查必要文件
    local required_files=("Makefile" "feeds.conf.default" "scripts/feeds")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        log_error "缺少必要文件: ${missing_files[*]}"
        return 1
    fi
    
    # 检查feeds状态
    local feeds_dirs=("feeds/packages" "feeds/luci")
    local missing_feeds=()
    
    for dir in "${feeds_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            missing_feeds+=("$dir")
        fi
    done
    
    if [ ${#missing_feeds[@]} -gt 0 ]; then
        log_warning "缺少feeds目录: ${missing_feeds[*]}"
        log_info "建议运行feeds更新"
    fi
    
    log_success "源码检查完成"
    return 0
}

#========================================================================================================================
# 帮助信息和主函数
#========================================================================================================================

show_help() {
    cat << EOF
${CYAN}OpenWrt 源码管理模块 v${MODULE_VERSION}${NC}

${CYAN}使用方法:${NC}
  $0 <操作> [选项...]

${CYAN}操作:${NC}
  prepare               准备源码（下载/更新/feeds）
  check                 检查源码状态

${CYAN}选项:${NC}
  --branch <分支>       源码分支
  --config <文件>       构建配置文件
  --verbose             详细输出
  -h, --help            显示帮助信息
  --version             显示版本信息

${CYAN}支持的分支:${NC}
  lede-master           Lean的LEDE源码
  openwrt-main          OpenWrt官方主线
  immortalwrt-master    ImmortalWrt源码
  Lienol-master         Lienol的OpenWrt

${CYAN}示例:${NC}
  # 准备源码
  $0 prepare --branch lede-master --verbose
  
  # 使用配置文件准备
  $0 prepare --config /tmp/build_config.json
  
  # 检查源码状态
  $0 check
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
        prepare|check)
            operation="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --version)
            echo "源码管理模块 版本 $MODULE_VERSION"
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
        "prepare")
            operation_prepare "$@"
            ;;
        "check")
            operation_check "$@"
            ;;
    esac
}

# 检查脚本是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi