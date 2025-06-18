#!/bin/bash
#========================================================================================================================
# OpenWrt 配置生成器 - 重构版
# 功能: 根据设备型号和插件列表生成精确的.config文件，确保架构匹配
# 版本: 2.0.0
#========================================================================================================================

set -euo pipefail

# 脚本版本和路径
readonly GENERATOR_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly CONFIG_TEMPLATES_DIR="$PROJECT_ROOT/config/build-templates"
readonly DEVICE_PROFILES_DIR="$PROJECT_ROOT/config/device-profiles"

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
log_info() { echo -e "${BLUE}[CONFIG-GEN]${NC} $1"; }
log_success() { echo -e "${GREEN}[CONFIG-GEN]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[CONFIG-GEN]${NC} $1"; }
log_error() { echo -e "${RED}[CONFIG-GEN]${NC} $1" >&2; }
log_debug() { [ "$VERBOSE" = true ] && echo -e "${CYAN}[CONFIG-GEN-DEBUG]${NC} $1"; }

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
# 设备配置映射 - 确保架构匹配
#========================================================================================================================

# 获取设备的基础配置
get_device_config() {
    local device="$1"
    
    log_debug "获取设备配置: $device"
    
    case "$device" in
        "x86_64")
            cat << 'EOF'
# X86_64 设备配置
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y

# CPU 类型
CONFIG_TARGET_ARCH="x86_64"
CONFIG_TARGET_BOARD="x86"
CONFIG_TARGET_SUBTARGET="64"

# 固件格式
CONFIG_TARGET_IMAGES_GZIP=y
CONFIG_TARGET_KERNEL_PARTSIZE=32
CONFIG_TARGET_ROOTFS_PARTSIZE=512

# UEFI 支持
CONFIG_GRUB_EFI_IMAGES=y
CONFIG_EFI_IMAGES=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_ROOTFS_EXT4FS=y

# VMware 支持
CONFIG_VMDK_IMAGES=y
CONFIG_TARGET_IMAGES_PAD=y
EOF
            ;;
        "xiaomi_4a_gigabit")
            cat << 'EOF'
# 小米路由器4A千兆版配置
CONFIG_TARGET_ramips=y
CONFIG_TARGET_ramips_mt7621=y
CONFIG_TARGET_ramips_mt7621_DEVICE_xiaomi_mi-router-4a-gigabit=y

# CPU 架构
CONFIG_TARGET_ARCH="mipsel"
CONFIG_TARGET_BOARD="ramips"
CONFIG_TARGET_SUBTARGET="mt7621"

# 设备特定配置
CONFIG_TARGET_DEVICE_ramips_mt7621_DEVICE_xiaomi_mi-router-4a-gigabit=y
CONFIG_TARGET_DEVICE_PACKAGES_ramips_mt7621_DEVICE_xiaomi_mi-router-4a-gigabit=""

# 固件格式
CONFIG_TARGET_IMAGES_GZIP=y
EOF
            ;;
        "newifi_d2")
            cat << 'EOF'
# 新路由3(Newifi D2)配置
CONFIG_TARGET_ramips=y
CONFIG_TARGET_ramips_mt7621=y
CONFIG_TARGET_ramips_mt7621_DEVICE_d-team_newifi-d2=y

# CPU 架构
CONFIG_TARGET_ARCH="mipsel"
CONFIG_TARGET_BOARD="ramips"
CONFIG_TARGET_SUBTARGET="mt7621"

# 设备特定配置
CONFIG_TARGET_DEVICE_ramips_mt7621_DEVICE_d-team_newifi-d2=y
CONFIG_TARGET_DEVICE_PACKAGES_ramips_mt7621_DEVICE_d-team_newifi-d2=""

# 固件格式
CONFIG_TARGET_IMAGES_GZIP=y
EOF
            ;;
        "rpi_4b")
            cat << 'EOF'
# 树莓派4B配置
CONFIG_TARGET_bcm27xx=y
CONFIG_TARGET_bcm27xx_bcm2711=y
CONFIG_TARGET_bcm27xx_bcm2711_DEVICE_rpi-4=y

# CPU 架构
CONFIG_TARGET_ARCH="aarch64"
CONFIG_TARGET_BOARD="bcm27xx"
CONFIG_TARGET_SUBTARGET="bcm2711"

# 设备特定配置
CONFIG_TARGET_DEVICE_bcm27xx_bcm2711_DEVICE_rpi-4=y

# GPU 和多媒体支持
CONFIG_PACKAGE_kmod-vc4=y
CONFIG_PACKAGE_kmod-drm-vc4=y

# 固件格式
CONFIG_TARGET_IMAGES_GZIP=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
EOF
            ;;
        "nanopi_r2s")
            cat << 'EOF'
# NanoPi R2S配置
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r2s=y

# CPU 架构
CONFIG_TARGET_ARCH="aarch64"
CONFIG_TARGET_BOARD="rockchip"
CONFIG_TARGET_SUBTARGET="armv8"

# 设备特定配置
CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_friendlyarm_nanopi-r2s=y

# 固件格式
CONFIG_TARGET_IMAGES_GZIP=y
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
EOF
            ;;
        *)
            log_error "不支持的设备类型: $device"
            return 1
            ;;
    esac
}

# 获取设备的架构信息
get_device_arch() {
    local device="$1"
    
    case "$device" in
        "x86_64")
            echo "x86_64"
            ;;
        "xiaomi_4a_gigabit"|"newifi_d2")
            echo "mipsel"
            ;;
        "rpi_4b"|"nanopi_r2s")
            echo "aarch64"
            ;;
        *)
            log_error "未知设备架构: $device"
            return 1
            ;;
    esac
}

#========================================================================================================================
# 插件配置生成 - 根据设备架构适配
#========================================================================================================================

# 生成插件配置
generate_plugin_config() {
    local plugins="$1"
    local device_arch="$2"
    
    if [ -z "$plugins" ]; then
        log_debug "没有额外插件，跳过插件配置生成"
        return 0
    fi
    
    log_info "生成插件配置（架构: $device_arch）..."
    
    # 解析插件列表
    IFS=',' read -ra plugin_array <<< "$plugins"
    
    echo ""
    echo "# ================================="
    echo "# 用户选择的插件配置"
    echo "# 插件数量: ${#plugin_array[@]}"
    echo "# 目标架构: $device_arch"
    echo "# ================================="
    
    # 处理每个插件
    for plugin in "${plugin_array[@]}"; do
        plugin=$(echo "$plugin" | xargs)  # 去除空白字符
        
        if [ -n "$plugin" ]; then
            log_debug "处理插件: $plugin"
            generate_single_plugin_config "$plugin" "$device_arch"
        fi
    done
}

# 生成单个插件的配置
generate_single_plugin_config() {
    local plugin="$1"
    local device_arch="$2"
    
    echo ""
    echo "# --- $plugin ---"
    
    # 基础插件配置
    echo "CONFIG_PACKAGE_${plugin}=y"
    
    # 根据插件类型添加依赖和相关配置
    case "$plugin" in
        # 代理类插件
        "luci-app-ssr-plus")
            echo "CONFIG_PACKAGE_shadowsocksr-libev-ssr-local=y"
            echo "CONFIG_PACKAGE_shadowsocksr-libev-ssr-redir=y"
            echo "CONFIG_PACKAGE_v2ray-core=y"
            echo "CONFIG_PACKAGE_v2ray-plugin=y"
            echo "CONFIG_PACKAGE_simple-obfs=y"
            echo "CONFIG_PACKAGE_trojan=y"
            echo "CONFIG_PACKAGE_ipt2socks=y"
            echo "CONFIG_PACKAGE_dns2socks=y"
            echo "CONFIG_PACKAGE_microsocks=y"
            echo "CONFIG_PACKAGE_tcping=y"
            ;;
        "luci-app-passwall")
            echo "CONFIG_PACKAGE_haproxy=y"
            echo "CONFIG_PACKAGE_v2ray-core=y"
            echo "CONFIG_PACKAGE_xray-core=y"
            echo "CONFIG_PACKAGE_trojan-plus=y"
            echo "CONFIG_PACKAGE_brook=y"
            echo "CONFIG_PACKAGE_chinadns-ng=y"
            echo "CONFIG_PACKAGE_dns2socks=y"
            echo "CONFIG_PACKAGE_ipt2socks=y"
            echo "CONFIG_PACKAGE_kcptun-client=y"
            echo "CONFIG_PACKAGE_simple-obfs=y"
            echo "CONFIG_PACKAGE_v2ray-plugin=y"
            ;;
        "luci-app-passwall2")
            echo "CONFIG_PACKAGE_v2ray-core=y"
            echo "CONFIG_PACKAGE_xray-core=y"
            echo "CONFIG_PACKAGE_sing-box=y"
            echo "CONFIG_PACKAGE_hysteria=y"
            echo "CONFIG_PACKAGE_chinadns-ng=y"
            ;;
        "luci-app-openclash")
            echo "CONFIG_PACKAGE_clash=y"
            echo "CONFIG_PACKAGE_iptables-mod-tproxy=y"
            echo "CONFIG_PACKAGE_iptables-mod-extra=y"
            echo "CONFIG_PACKAGE_kmod-tun=y"
            ;;
            
        # 系统管理插件
        "luci-app-dockerman")
            echo "CONFIG_PACKAGE_docker=y"
            echo "CONFIG_PACKAGE_dockerd=y"
            echo "CONFIG_PACKAGE_docker-compose=y"
            echo "CONFIG_PACKAGE_cgroupfs-mount=y"
            echo "CONFIG_PACKAGE_containerd=y"
            echo "CONFIG_PACKAGE_runc=y"
            echo "CONFIG_PACKAGE_tini=y"
            ;;
        "luci-app-aria2")
            echo "CONFIG_PACKAGE_aria2=y"
            echo "CONFIG_PACKAGE_ariang=y"
            ;;
        "luci-app-qbittorrent")
            echo "CONFIG_PACKAGE_qBittorrent-Enhanced-Edition=y"
            echo "CONFIG_PACKAGE_qt5-core=y"
            echo "CONFIG_PACKAGE_qt5-network=y"
            echo "CONFIG_PACKAGE_qt5-xml=y"
            ;;
            
        # 网络工具插件
        "luci-app-adguardhome")
            echo "CONFIG_PACKAGE_adguardhome=y"
            ;;
        "luci-app-smartdns")
            echo "CONFIG_PACKAGE_smartdns=y"
            ;;
        "luci-app-unblockmusic")
            echo "CONFIG_PACKAGE_node=y"
            echo "CONFIG_PACKAGE_UnblockNeteaseMusic=y"
            echo "CONFIG_PACKAGE_UnblockNeteaseMusic-Go=y"
            ;;
            
        # 主题插件
        "luci-theme-"*)
            # 主题插件通常不需要额外依赖
            ;;
            
        # 存储相关插件
        "luci-app-samba"*)
            echo "CONFIG_PACKAGE_samba36-server=y"
            echo "CONFIG_PACKAGE_kmod-fs-cifs=y"
            echo "CONFIG_PACKAGE_kmod-fs-ntfs=y"
            ;;
            
        # 默认处理
        *)
            log_debug "插件 $plugin 使用默认配置"
            ;;
    esac
    
    # 架构特定的优化
    apply_arch_specific_config "$plugin" "$device_arch"
}

# 应用架构特定的配置优化
apply_arch_specific_config() {
    local plugin="$1"
    local device_arch="$2"
    
    case "$device_arch" in
        "x86_64")
            # x86_64 设备通常性能较好，可以启用更多功能
            case "$plugin" in
                "luci-app-dockerman")
                    echo "CONFIG_DOCKER_CGROUP_OPTIONS=y"
                    echo "CONFIG_DOCKER_NET_MACVLAN=y"
                    echo "CONFIG_DOCKER_NET_OVERLAY=y"
                    echo "CONFIG_DOCKER_NET_TFTP=y"
                    ;;
            esac
            ;;
        "mipsel")
            # MIPS 设备资源有限，启用节省内存的选项
            case "$plugin" in
                "luci-app-ssr-plus"|"luci-app-passwall")
                    echo "# MIPS架构内存优化"
                    echo "CONFIG_PACKAGE_ip-tiny=y"
                    ;;
            esac
            ;;
        "aarch64")
            # ARM64 设备，平衡性能和功耗
            case "$plugin" in
                "luci-app-dockerman")
                    echo "CONFIG_PACKAGE_libseccomp=y"
                    ;;
            esac
            ;;
    esac
}

#========================================================================================================================
# 通用配置生成
#========================================================================================================================

# 生成通用系统配置
generate_common_config() {
    local device_arch="$1"
    
    cat << 'EOF'

# =================================
# 通用系统配置
# =================================

# 基础系统
CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y
CONFIG_PACKAGE_ipv6helper=y
CONFIG_PACKAGE_kmod-ipt-raw=y
CONFIG_PACKAGE_kmod-ipt-tproxy=y
CONFIG_PACKAGE_kmod-ipt-nat6=y

# 文件系统支持
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-ntfs=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-exfat=y

# USB 支持
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-storage-extras=y
CONFIG_PACKAGE_kmod-usb-storage-uas=y

# 网络工具
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_ca-certificates=y
CONFIG_PACKAGE_ca-bundle=y

# 系统工具
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_unzip=y
CONFIG_PACKAGE_zip=y

# LuCI 界面
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y

# 防火墙
CONFIG_PACKAGE_ip6tables=y
CONFIG_PACKAGE_iptables-mod-tproxy=y
CONFIG_PACKAGE_iptables-mod-extra=y

# 无线支持（如果设备支持）
CONFIG_PACKAGE_hostapd-common=y
CONFIG_PACKAGE_wpad-openssl=y

EOF

    # 架构特定的通用配置
    case "$device_arch" in
        "x86_64")
            cat << 'EOF'
# X86_64 特定配置
CONFIG_PACKAGE_kmod-kvm-amd=y
CONFIG_PACKAGE_kmod-kvm-intel=y
CONFIG_PACKAGE_kmod-kvm-x86=y

EOF
            ;;
        "aarch64")
            cat << 'EOF'
# ARM64 特定配置
CONFIG_PACKAGE_kmod-crypto-hw-ccp=y

EOF
            ;;
    esac
}

# 生成编译优化配置
generate_build_optimization() {
    cat << 'EOF'

# =================================
# 编译和优化配置
# =================================

# 编译优化
CONFIG_DEVEL=y
CONFIG_CCACHE=y

# 内核配置
CONFIG_KERNEL_BUILD_USER="OpenWrt-Builder"
CONFIG_KERNEL_BUILD_DOMAIN="buildhost"

# 高级配置
CONFIG_KERNEL_KALLSYMS=y
CONFIG_KERNEL_DEBUG_FS=y
CONFIG_KERNEL_DEBUG_KERNEL=y

# 包管理
CONFIG_PACKAGE_opkg=y
CONFIG_SIGNATURE_CHECK=y

EOF
}

#========================================================================================================================
# 主要操作函数
#========================================================================================================================

# 生成完整配置
operation_generate() {
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
    
    log_info "🔧 开始生成配置文件..."
    
    # 读取构建参数
    local target_device=$(get_config_value '.build_params.target_device' '')
    local plugins=$(get_config_value '.build_params.plugins' '')
    local source_branch=$(get_config_value '.build_params.source_branch' '')
    
    if [ -z "$target_device" ]; then
        log_error "未指定目标设备"
        return 1
    fi
    
    log_info "配置参数: 设备=$target_device, 源码=$source_branch"
    log_info "插件列表: ${plugins:-无额外插件}"
    
    # 获取设备架构
    local device_arch=$(get_device_arch "$target_device")
    log_info "设备架构: $device_arch"
    
    # 生成配置文件
    local config_output=".config"
    
    {
        echo "# ========================================================"
        echo "# OpenWrt 编译配置文件"
        echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# 目标设备: $target_device"
        echo "# 设备架构: $device_arch"
        echo "# 源码分支: $source_branch"
        echo "# 生成器版本: $GENERATOR_VERSION"
        echo "# ========================================================"
        echo ""
        
        # 设备基础配置
        get_device_config "$target_device"
        
        # 通用系统配置
        generate_common_config "$device_arch"
        
        # 插件配置
        generate_plugin_config "$plugins" "$device_arch"
        
        # 编译优化配置
        generate_build_optimization
        
        echo ""
        echo "# 配置文件生成完成"
        echo "# ========================================================"
        
    } > "$config_output"
    
    # 验证生成的配置
    if [ -f "$config_output" ] && [ -s "$config_output" ]; then
        local config_lines=$(wc -l < "$config_output")
        log_success "配置文件生成完成: $config_output (${config_lines}行)"
        
        # 显示配置摘要
        log_info "配置摘要:"
        echo "  - 目标设备: $target_device ($device_arch)"
        echo "  - 配置行数: $config_lines"
        echo "  - 插件数量: $(echo "$plugins" | grep -o ',' | wc -l | awk '{print $1 + 1}')"
        
        return 0
    else
        log_error "配置文件生成失败"
        return 1
    fi
}

# 验证配置文件
operation_validate() {
    local config_file=".config"
    
    if [ ! -f "$config_file" ]; then
        log_error "配置文件不存在: $config_file"
        return 1
    fi
    
    log_info "🔍 验证配置文件..."
    
    # 基础验证
    local target_lines=$(grep -c "^CONFIG_TARGET_" "$config_file" || true)
    local package_lines=$(grep -c "^CONFIG_PACKAGE_" "$config_file" || true)
    
    if [ "$target_lines" -eq 0 ]; then
        log_error "配置文件缺少目标设备配置"
        return 1
    fi
    
    log_success "配置验证通过"
    log_info "统计信息:"
    echo "  - 目标配置项: $target_lines"
    echo "  - 包配置项: $package_lines"
    
    return 0
}

#========================================================================================================================
# 帮助信息和主函数
#========================================================================================================================

show_help() {
    cat << EOF
${CYAN}OpenWrt 配置生成器 v${GENERATOR_VERSION}${NC}

${CYAN}使用方法:${NC}
  $0 <操作> [选项...]

${CYAN}操作:${NC}
  generate              生成配置文件
  validate              验证配置文件

${CYAN}选项:${NC}
  --config <文件>       构建配置文件
  --verbose             详细输出
  -h, --help            显示帮助信息
  --version             显示版本信息

${CYAN}示例:${NC}
  # 生成配置文件
  $0 generate --config /tmp/build_config.json --verbose
  
  # 验证配置文件
  $0 validate
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
        generate|validate)
            operation="$1"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --version)
            echo "OpenWrt 配置生成器 版本 $GENERATOR_VERSION"
            exit 0
            ;;
        *)
            log_error "未知操作: $1"
            show_help
            exit 1
            ;;
    esac
    
    # 创建配置目录
    mkdir -p "$CONFIG_TEMPLATES_DIR" "$DEVICE_PROFILES_DIR"
    
    # 执行操作
    case "$operation" in
        "generate")
            operation_generate "$@"
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