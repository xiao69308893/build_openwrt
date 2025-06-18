#!/bin/bash
#========================================================================================================================
# OpenWrt 产物管理模块
# 功能: 编译产物整理、校验和生成、发布包创建
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
log_info() { echo -e "${BLUE}[ARTIFACT-MANAGER]${NC} $1"; }
log_success() { echo -e "${GREEN}[ARTIFACT-MANAGER]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[ARTIFACT-MANAGER]${NC} $1"; }
log_error() { echo -e "${RED}[ARTIFACT-MANAGER]${NC} $1" >&2; }
log_debug() { [ "$VERBOSE" = true ] && echo -e "${CYAN}[ARTIFACT-MANAGER-DEBUG]${NC} $1"; }

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

# 格式化文件大小
format_file_size() {
    local size_bytes="$1"
    
    if [ "$size_bytes" -lt 1024 ]; then
        echo "${size_bytes}B"
    elif [ "$size_bytes" -lt 1048576 ]; then
        echo "$((size_bytes / 1024))KB"
    elif [ "$size_bytes" -lt 1073741824 ]; then
        echo "$((size_bytes / 1048576))MB"
    else
        echo "$((size_bytes / 1073741824))GB"
    fi
}

#========================================================================================================================
# 固件文件识别和分类
#========================================================================================================================

# 设备固件文件模式定义
declare -A FIRMWARE_PATTERNS

# 初始化固件文件模式
init_firmware_patterns() {
    log_debug "初始化固件文件模式..."
    
    # X86_64 设备固件
    FIRMWARE_PATTERNS["x86_64"]="*generic*ext4*.img.gz|*generic*squashfs*.img.gz|*combined*.vmdk|*uefi*.img.gz"
    
    # MIPS 路由器固件
    FIRMWARE_PATTERNS["xiaomi_4a_gigabit"]="*xiaomi*4a*gigabit*.bin|*mi-router-4a-gigabit*.bin"
    FIRMWARE_PATTERNS["newifi_d2"]="*newifi*d2*.bin|*d-team*newifi-d2*.bin"
    
    # ARM64 开发板固件
    FIRMWARE_PATTERNS["rpi_4b"]="*rpi*4*.img.gz|*bcm2711*.img.gz|*raspberry*.img.gz"
    FIRMWARE_PATTERNS["nanopi_r2s"]="*nanopi*r2s*.img.gz|*friendlyarm*nanopi-r2s*.img.gz"
    
    log_debug "固件文件模式初始化完成"
}

# 查找固件文件
find_firmware_files() {
    local device="$1"
    local search_dir="${2:-bin}"
    
    if [ ! -d "$search_dir" ]; then
        log_error "编译输出目录不存在: $search_dir"
        return 1
    fi
    
    # 初始化固件模式
    init_firmware_patterns
    
    # 获取设备对应的文件模式
    local pattern="${FIRMWARE_PATTERNS[$device]:-}"
    
    local firmware_files=()
    
    if [ -n "$pattern" ]; then
        # 使用设备特定模式查找
        log_debug "使用设备模式查找: $pattern"
        
        IFS='|' read -ra patterns <<< "$pattern"
        for p in "${patterns[@]}"; do
            while IFS= read -r -d '' file; do
                firmware_files+=("$file")
            done < <(find "$search_dir" -name "$p" -type f -print0 2>/dev/null)
        done
    else
        # 使用通用模式查找
        log_debug "使用通用模式查找固件文件"
        
        local common_extensions=("*.bin" "*.img" "*.img.gz" "*.tar.gz" "*.vmdk")
        
        for ext in "${common_extensions[@]}"; do
            while IFS= read -r -d '' file; do
                # 排除不必要的文件
                if [[ ! "$file" =~ (packages|kernel|rootfs\.tar) ]]; then
                    firmware_files+=("$file")
                fi
            done < <(find "$search_dir" -name "$ext" -type f -print0 2>/dev/null)
        done
    fi
    
    # 去重并排序
    if [ ${#firmware_files[@]} -gt 0 ]; then
        printf '%s\n' "${firmware_files[@]}" | sort -u
        return 0
    else
        log_warning "未找到固件文件"
        return 1
    fi
}

# 分类固件文件
classify_firmware_files() {
    local files=("$@")
    
    declare -A classified_files
    
    for file in "${files[@]}"; do
        local basename=$(basename "$file")
        local category="other"
        
        # 按文件名特征分类
        if [[ "$basename" =~ ext4.*img ]]; then
            category="ext4_image"
        elif [[ "$basename" =~ squashfs.*img ]]; then
            category="squashfs_image"
        elif [[ "$basename" =~ combined.*img ]]; then
            category="combined_image"
        elif [[ "$basename" =~ uefi.*img ]]; then
            category="uefi_image"
        elif [[ "$basename" =~ \.vmdk$ ]]; then
            category="vmware_image"
        elif [[ "$basename" =~ sysupgrade.*bin$ ]]; then
            category="sysupgrade_firmware"
        elif [[ "$basename" =~ factory.*bin$ ]]; then
            category="factory_firmware"
        elif [[ "$basename" =~ \.bin$ ]]; then
            category="generic_firmware"
        elif [[ "$basename" =~ initramfs ]]; then
            category="initramfs"
        fi
        
        classified_files["$category"]+="$file "
    done
    
    # 输出分类结果
    for category in "${!classified_files[@]}"; do
        echo "$category:${classified_files[$category]}"
    done
}

#========================================================================================================================
# 产物整理和重命名
#========================================================================================================================

# 整理固件文件
organize_firmware_files() {
    local device="$1"
    local output_dir="$2"
    
    log_info "整理固件文件: $device -> $output_dir"
    
    # 创建输出目录
    mkdir -p "$output_dir"
    
    # 查找固件文件
    local firmware_files=($(find_firmware_files "$device"))
    
    if [ ${#firmware_files[@]} -eq 0 ]; then
        log_error "未找到任何固件文件"
        return 1
    fi
    
    log_info "找到 ${#firmware_files[@]} 个固件文件"
    
    # 获取构建信息
    local build_tag=$(get_config_value '.build_info.build_tag' "OpenWrt_${device}_$(date +%Y%m%d_%H%M%S)")
    local source_branch=$(get_config_value '.build_params.source_branch' 'unknown')
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    
    # 复制和重命名固件文件
    local copied_files=()
    local total_size=0
    
    for file in "${firmware_files[@]}"; do
        local basename=$(basename "$file")
        local extension="${basename##*.}"
        local size=$(stat -c%s "$file")
        local size_formatted=$(format_file_size "$size")
        
        # 生成新的文件名
        local new_name="${build_tag}_${basename}"
        
        # 如果文件名太长，简化它
        if [ ${#new_name} -gt 100 ]; then
            local simplified_basename=$(echo "$basename" | sed 's/openwrt-[0-9]*\.[0-9]*\.[0-9]*-//' | sed 's/-[0-9]*\.[0-9]*\.[0-9]*-/-/')
            new_name="${build_tag}_${simplified_basename}"
        fi
        
        log_debug "复制文件: $basename -> $new_name ($size_formatted)"
        
        # 复制文件
        cp "$file" "$output_dir/$new_name"
        copied_files+=("$new_name")
        total_size=$((total_size + size))
    done
    
    # 生成文件列表
    log_info "生成文件清单..."
    generate_file_manifest "$output_dir" "${copied_files[@]}"
    
    # 生成校验和
    log_info "生成文件校验和..."
    generate_checksums "$output_dir" "${copied_files[@]}"
    
    # 生成固件信息文件
    log_info "生成固件信息..."
    generate_firmware_info "$output_dir" "$device" "$build_tag" "$source_branch" "$total_size" "${copied_files[@]}"
    
    log_success "固件文件整理完成: $output_dir"
    log_info "总计大小: $(format_file_size $total_size)"
    
    # 输出到GitHub Actions环境变量
    echo "firmware_path=$output_dir" >> $GITHUB_OUTPUT 2>/dev/null || true
    echo "firmware_count=${#copied_files[@]}" >> $GITHUB_OUTPUT 2>/dev/null || true
    echo "total_size=$total_size" >> $GITHUB_OUTPUT 2>/dev/null || true
    echo "status=success" >> $GITHUB_OUTPUT 2>/dev/null || true
    
    return 0
}

# 生成文件清单
generate_file_manifest() {
    local output_dir="$1"
    shift
    local files=("$@")
    
    local manifest_file="$output_dir/FILES.txt"
    
    {
        echo "# OpenWrt 固件文件清单"
        echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# 文件数量: ${#files[@]}"
        echo ""
        
        echo "文件列表:"
        for file in "${files[@]}"; do
            if [ -f "$output_dir/$file" ]; then
                local size=$(stat -c%s "$output_dir/$file")
                local size_formatted=$(format_file_size "$size")
                echo "  $file (${size_formatted})"
            fi
        done
        
        echo ""
        echo "使用说明:"
        echo "1. 请根据设备型号选择对应的固件文件"
        echo "2. 刷机前请确认设备型号和硬件版本"
        echo "3. 建议先备份原厂固件"
        echo "4. 刷机有风险，请谨慎操作"
        
    } > "$manifest_file"
    
    log_debug "文件清单已生成: $manifest_file"
}

# 生成校验和文件
generate_checksums() {
    local output_dir="$1"
    shift
    local files=("$@")
    
    local checksum_file="$output_dir/sha256sums.txt"
    
    log_debug "生成SHA256校验和..."
    
    # 进入输出目录计算校验和
    (
        cd "$output_dir"
        
        {
            echo "# SHA256 校验和文件"
            echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
            echo ""
        } > sha256sums.txt
        
        for file in "${files[@]}"; do
            if [ -f "$file" ]; then
                sha256sum "$file" >> sha256sums.txt
                log_debug "生成校验和: $file"
            fi
        done
    )
    
    log_debug "校验和文件已生成: $checksum_file"
}

# 生成固件信息文件
generate_firmware_info() {
    local output_dir="$1"
    local device="$2"
    local build_tag="$3"
    local source_branch="$4"
    local total_size="$5"
    shift 5
    local files=("$@")
    
    local info_file="$output_dir/firmware_info.txt"
    
    # 获取设备信息
    local device_name="$device"
    if command -v "$SCRIPT_DIR/../device-adapter.sh" &> /dev/null; then
        device_name=$("$SCRIPT_DIR/../device-adapter.sh" get-name --device "$device" 2>/dev/null || echo "$device")
    fi
    
    # 获取编译信息
    local compiler_version=$(gcc --version 2>/dev/null | head -n1 || echo "未知")
    local build_time=$(date '+%Y-%m-%d %H:%M:%S')
    local plugins=$(get_config_value '.build_params.plugins' '无额外插件')
    
    {
        echo "# OpenWrt 智能编译固件信息"
        echo ""
        echo "## 📋 基本信息"
        echo "- **设备型号**: $device_name ($device)"
        echo "- **源码分支**: $source_branch"
        echo "- **编译标签**: $build_tag"
        echo "- **编译时间**: $build_time"
        echo "- **编译器版本**: $compiler_version"
        echo ""
        echo "## 🔧 编译配置"
        echo "- **选择插件**: $plugins"
        echo "- **固件数量**: ${#files[@]} 个文件"
        echo "- **总计大小**: $(format_file_size $total_size)"
        echo ""
        echo "## 📦 固件文件"
        
        # 按类型分组显示文件
        local classified=($(classify_firmware_files "${files[@]/#/$output_dir/}"))
        
        for classification in "${classified[@]}"; do
            local category="${classification%%:*}"
            local file_list="${classification#*:}"
            
            case "$category" in
                "ext4_image")
                    echo "### EXT4 镜像文件"
                    echo "- 适用于: 需要可写文件系统的场景"
                    ;;
                "squashfs_image")
                    echo "### SquashFS 镜像文件"
                    echo "- 适用于: 标准路由器安装（推荐）"
                    ;;
                "sysupgrade_firmware")
                    echo "### Sysupgrade 固件"
                    echo "- 适用于: 系统升级（已安装OpenWrt的设备）"
                    ;;
                "factory_firmware")
                    echo "### Factory 固件"
                    echo "- 适用于: 从原厂固件首次刷入"
                    ;;
                "vmware_image")
                    echo "### VMware 镜像"
                    echo "- 适用于: VMware 虚拟机"
                    ;;
                *)
                    echo "### 其他文件"
                    ;;
            esac
            
            for file_path in $file_list; do
                local file=$(basename "$file_path")
                if [ -f "$output_dir/$file" ]; then
                    local size=$(stat -c%s "$output_dir/$file")
                    local size_formatted=$(format_file_size "$size")
                    echo "- \`$file\` (${size_formatted})"
                fi
            done
            echo ""
        done
        
        echo "## ⚠️ 重要提醒"
        echo "1. **刷机风险**: 刷机有变砖风险，请确保了解刷机流程"
        echo "2. **设备确认**: 请确认设备型号完全匹配，避免刷错固件"
        echo "3. **备份原厂**: 建议先备份原厂固件，以便出问题时恢复"
        echo "4. **电源稳定**: 刷机过程中请确保电源稳定，不要断电"
        echo "5. **网络连接**: 首次启动后，默认IP通常为 192.168.1.1"
        echo ""
        echo "## 🔗 相关链接"
        echo "- **项目地址**: https://github.com/$GITHUB_REPOSITORY"
        echo "- **OpenWrt官网**: https://openwrt.org"
        echo "- **使用文档**: https://github.com/$GITHUB_REPOSITORY/wiki"
        echo ""
        echo "---"
        echo "*本固件由 OpenWrt 智能编译系统自动构建*"
        
    } > "$info_file"
    
    log_debug "固件信息文件已生成: $info_file"
}

#========================================================================================================================
# 发布包创建
#========================================================================================================================

# 创建发布包
create_release_package() {
    local output_dir="$1"
    local device="$2"
    
    log_info "创建发布包..."
    
    local build_tag=$(get_config_value '.build_info.build_tag' "OpenWrt_${device}_$(date +%Y%m%d_%H%M%S)")
    local release_name="OpenWrt 智能编译 - $device ($(date '+%Y-%m-%d %H:%M'))"
    
    # 输出GitHub Actions环境变量
    echo "release_tag=$build_tag" >> $GITHUB_OUTPUT 2>/dev/null || true
    echo "release_name=$release_name" >> $GITHUB_OUTPUT 2>/dev/null || true
    
    log_success "发布包信息已生成"
    log_info "发布标签: $build_tag"
    log_info "发布名称: $release_name"
    
    return 0
}

#========================================================================================================================
# 主要操作函数
#========================================================================================================================

# 整理编译产物
operation_organize() {
    local config_file=""
    local device=""
    local output_dir=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                config_file="$2"
                BUILD_CONFIG_FILE="$config_file"
                shift 2
                ;;
            --device)
                device="$2"
                shift 2
                ;;
            --output)
                output_dir="$2"
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
    
    # 从配置文件读取设备信息
    if [ -z "$device" ] && [ -n "$BUILD_CONFIG_FILE" ]; then
        device=$(get_config_value '.build_params.target_device' '')
    fi
    
    if [ -z "$device" ]; then
        log_error "请指定目标设备"
        return 1
    fi
    
    # 设置默认输出目录
    if [ -z "$output_dir" ]; then
        output_dir="$PROJECT_ROOT/firmware_output"
    fi
    
    log_info "📦 开始整理编译产物..."
    log_info "目标设备: $device"
    log_info "输出目录: $output_dir"
    
    # 检查编译输出是否存在
    if [ ! -d "bin" ]; then
        log_error "编译输出目录 'bin' 不存在，请先完成编译"
        return 1
    fi
    
    # 执行产物整理
    if ! organize_firmware_files "$device" "$output_dir"; then
        log_error "固件文件整理失败"
        return 1
    fi
    
    # 创建发布包信息
    if ! create_release_package "$output_dir" "$device"; then
        log_warning "发布包创建可能有问题"
    fi
    
    # 显示整理结果
    log_success "📦 编译产物整理完成"
    
    if [ -d "$output_dir" ]; then
        local file_count=$(find "$output_dir" -type f | wc -l)
        local dir_size=$(du -sh "$output_dir" | cut -f1)
        
        log_info "整理结果:"
        echo "  📁 输出目录: $output_dir"
        echo "  📄 文件数量: $file_count"
        echo "  💾 目录大小: $dir_size"
        
        # 列出主要文件
        echo "  📋 主要文件:"
        find "$output_dir" -name "*.bin" -o -name "*.img" -o -name "*.img.gz" -o -name "*.vmdk" | head -5 | while read file; do
            local basename=$(basename "$file")
            local size=$(stat -c%s "$file" 2>/dev/null || echo "0")
            local size_formatted=$(format_file_size "$size")
            echo "    - $basename ($size_formatted)"
        done
    fi
    
    return 0
}

# 验证产物
operation_validate() {
    local output_dir="$1"
    
    if [ -z "$output_dir" ]; then
        log_error "请指定产物目录"
        return 1
    fi
    
    log_info "🔍 验证编译产物..."
    
    if [ ! -d "$output_dir" ]; then
        log_error "产物目录不存在: $output_dir"
        return 1
    fi
    
    # 检查必要文件
    local required_files=("sha256sums.txt" "firmware_info.txt" "FILES.txt")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$output_dir/$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        log_warning "缺少文件: ${missing_files[*]}"
    fi
    
    # 验证校验和
    if [ -f "$output_dir/sha256sums.txt" ]; then
        log_info "验证文件校验和..."
        
        (
            cd "$output_dir"
            if sha256sum -c sha256sums.txt &>/dev/null; then
                log_success "校验和验证通过"
            else
                log_error "校验和验证失败"
                return 1
            fi
        )
    fi
    
    # 统计信息
    local firmware_count=$(find "$output_dir" -name "*.bin" -o -name "*.img" -o -name "*.img.gz" -o -name "*.vmdk" | wc -l)
    
    log_success "产物验证完成"
    log_info "固件文件数量: $firmware_count"
    
    return 0
}

#========================================================================================================================
# 帮助信息和主函数
#========================================================================================================================

show_help() {
    cat << EOF
${CYAN}OpenWrt 产物管理模块 v${MODULE_VERSION}${NC}

${CYAN}使用方法:${NC}
  $0 <操作> [选项...]

${CYAN}操作:${NC}
  organize                整理编译产物
  validate                验证产物完整性

${CYAN}选项:${NC}
  --config <文件>         构建配置文件
  --device <设备>         目标设备
  --output <目录>         输出目录
  --verbose               详细输出
  -h, --help              显示帮助信息
  --version               显示版本信息

${CYAN}示例:${NC}
  # 整理产物
  $0 organize --config /tmp/build_config.json --device x86_64 --output ./firmware
  
  # 验证产物
  $0 validate ./firmware
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
        organize|validate)
            operation="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --version)
            echo "产物管理模块 版本 $MODULE_VERSION"
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
        "organize")
            operation_organize "$@"
            ;;
        "validate")
            operation_validate "$@"
            ;;
    esac
}

# 检查脚本是否被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi