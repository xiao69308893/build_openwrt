/**
 * Token配置模态框管理器
 * 文件名: js/token-modal.js
 * 用途: 安全的GitHub Token配置功能
 */

class TokenModalManager {
    constructor() {
        this.currentMethod = 'input';
        this.isInitialized = false;
        this.init();
    }

    /**
     * 初始化Token模态框
     */
    init() {
        if (this.isInitialized) return;

        console.log('🔐 初始化Token配置模态框');

        // 等待DOM加载完成
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => this.setup());
        } else {
            this.setup();
        }
    }

    /**
     * 设置模态框功能
     */
    setup() {
        this.createModalHTML();
        this.bindEvents();
        this.checkExistingToken();
        this.isInitialized = true;

        console.log('✅ Token模态框初始化完成');
    }

    /**
     * 创建模态框HTML
     */
    createModalHTML() {
        const existingModal = document.getElementById('tokenModal');
        if (existingModal) return; // 已存在则不重复创建

        const modalHTML = `
            <div id="tokenModal" class="token-modal">
                <div class="token-dialog">
                    <button class="modal-close" onclick="window.tokenModal.close()">&times;</button>
                    
                    <div class="token-header">
                        <h2>🔐 GitHub Token 配置</h2>
                        <p>为了正常使用编译功能，需要配置GitHub Personal Access Token</p>
                    </div>

                    <div id="tokenStatus" class="token-status" style="display: none;">
                        <span id="statusIcon">✅</span>
                        <span id="statusText">Token配置成功</span>
                    </div>

                    <div class="token-security-tips">
                        <div class="security-title">🛡️ 安全提示</div>
                        <div class="security-tips">
                            • Token具有访问GitHub的权限，请妥善保管<br>
                            • 建议创建权限最小的Token（只选择必要权限）<br>
                            • 不要在公共场所或他人设备上保存Token<br>
                            • 定期更换Token以提高安全性
                        </div>
                    </div>

                    <div class="token-methods">
                        <div class="token-method active" data-method="input">
                            <div class="method-icon">⌨️</div>
                            <div class="method-title">手动输入</div>
                            <div class="method-desc">直接输入GitHub Token</div>
                        </div>
                        <div class="token-method" data-method="guide">
                            <div class="method-icon">📋</div>
                            <div class="method-title">创建指南</div>
                            <div class="method-desc">查看Token创建步骤</div>
                        </div>
                    </div>

                    <div id="inputSection" class="token-input-section show">
                        <div class="input-group">
                            <label for="tokenInput" class="input-label">GitHub Personal Access Token</label>
                            <input type="password" id="tokenInput" class="input-field" 
                                   placeholder="请输入以 ghp_ 或 github_pat_ 开头的Token"
                                   autocomplete="off">
                            <div class="input-help">
                                Token格式: ghp_xxxxxxxxxxxx 或 github_pat_xxxxxxxxxxxx
                            </div>
                        </div>
                        <div class="input-group">
                            <label class="checkbox-label">
                                <input type="checkbox" id="saveToken"> 
                                <span class="checkbox-text">保存到浏览器本地存储（仅在个人设备上勾选）</span>
                            </label>
                        </div>
                    </div>

                    <div id="guideSection" class="token-input-section">
                        <div class="github-steps">
                            <h4>📝 GitHub Token 创建步骤</h4>
                            <ol>
                                <li>登录GitHub，点击右上角头像 → <code>Settings</code></li>
                                <li>在左侧菜单中选择 <code>Developer settings</code></li>
                                <li>选择 <code>Personal access tokens</code> → <code>Tokens (classic)</code></li>
                                <li>点击 <code>Generate new token</code> → <code>Generate new token (classic)</code></li>
                                <li>填写Token描述，如 "OpenWrt Builder"</li>
                                <li>选择过期时间（建议30-90天）</li>
                                <li>选择权限范围：
                                    <ul style="margin-top: 8px;">
                                        <li><code>repo</code> - 仓库访问权限 ✅ <strong>必需</strong></li>
                                        <li><code>workflow</code> - GitHub Actions权限 ✅ <strong>必需</strong></li>
                                        <li><code>write:packages</code> - 包发布权限（可选）</li>
                                    </ul>
                                </li>
                                <li>点击 <code>Generate token</code> 生成Token</li>
                                <li>⚠️ <strong>立即复制Token</strong>（离开页面后无法再次查看）</li>
                            </ol>
                        </div>
                        <div class="input-group">
                            <label for="guideTokenInput" class="input-label">将创建的Token粘贴到这里</label>
                            <input type="password" id="guideTokenInput" class="input-field" 
                                   placeholder="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
                                   autocomplete="off">
                        </div>
                    </div>

                    <div class="token-actions">
                        <button class="btn btn-secondary" onclick="window.tokenModal.close()">
                            ❌ 取消
                        </button>
                        <button class="btn btn-success" onclick="window.tokenModal.test()" 
                                style="display: none;" id="testBtn">
                            🔍 测试连接
                        </button>
                        <button class="btn btn-primary" onclick="window.tokenModal.save()">
                            💾 保存配置
                        </button>
                    </div>
                </div>
            </div>
        `;

        // 添加到页面
        const container = document.getElementById('token-modal-container') || document.body;
        container.insertAdjacentHTML('beforeend', modalHTML);
    }

    /**
     * 绑定事件监听器
     */
    bindEvents() {
        // 方法选择事件
        document.querySelectorAll('.token-method').forEach(method => {
            method.addEventListener('click', () => {
                this.selectMethod(method.dataset.method);
            });
        });

        // 输入框验证事件
        const tokenInput = document.getElementById('tokenInput');
        const guideTokenInput = document.getElementById('guideTokenInput');

        if (tokenInput) {
            tokenInput.addEventListener('input', () => this.validateToken());
            tokenInput.addEventListener('paste', () => {
                setTimeout(() => this.validateToken(), 100);
            });
        }

        if (guideTokenInput) {
            guideTokenInput.addEventListener('input', () => this.validateToken());
            guideTokenInput.addEventListener('paste', () => {
                setTimeout(() => this.validateToken(), 100);
            });
        }

        // 模态框点击外部关闭
        const modal = document.getElementById('tokenModal');
        if (modal) {
            modal.addEventListener('click', (e) => {
                if (e.target === modal) {
                    this.close();
                }
            });
        }

        // ESC键关闭
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && modal?.classList.contains('show')) {
                this.close();
            }
        });
    }

    /**
     * 显示模态框
     */
    show() {
        const modal = document.getElementById('tokenModal');
        if (modal) {
            modal.classList.add('show');
            document.body.style.overflow = 'hidden'; // 防止背景滚动
            this.selectMethod('input'); // 默认选择手动输入
            this.checkExistingToken();
        }
    }

    /**
     * 关闭模态框
     */
    close() {
        const modal = document.getElementById('tokenModal');
        if (modal) {
            modal.classList.remove('show');
            document.body.style.overflow = ''; // 恢复背景滚动
            this.hideStatus();
        }
    }

    /**
     * 选择配置方法
     */
    selectMethod(method) {
        this.currentMethod = method;

        // 更新方法选择状态
        document.querySelectorAll('.token-method').forEach(m => {
            m.classList.remove('active');
        });

        const selectedMethod = document.querySelector(`[data-method="${method}"]`);
        if (selectedMethod) {
            selectedMethod.classList.add('active');
        }

        // 显示对应的输入区域
        document.querySelectorAll('.token-input-section').forEach(section => {
            section.classList.remove('show');
        });

        const targetSection = document.getElementById(method === 'input' ? 'inputSection' : 'guideSection');
        if (targetSection) {
            targetSection.classList.add('show');
        }
    }

    /**
     * 验证Token格式和有效性
     */
    validateToken() {
        const input = this.getCurrentInput();
        if (!input) return;

        const token = input.value.trim();
        const isValidFormat = token.startsWith('ghp_') || token.startsWith('github_pat_');

        if (token === '') {
            // 空输入，重置状态
            input.style.borderColor = '#e0e0e0';
            this.hideStatus();
            this.hideTestButton();
        } else if (!isValidFormat) {
            // 格式错误
            input.style.borderColor = '#e74c3c';
            this.showStatus(false, '❌ Token格式不正确');
            this.hideTestButton();
        } else {
            // 格式正确
            input.style.borderColor = '#27ae60';
            this.showStatus(true, '✅ Token格式正确');
            this.showTestButton();
        }
    }

    /**
     * 获取当前活动的输入框
     */
    getCurrentInput() {
        return this.currentMethod === 'input' ?
            document.getElementById('tokenInput') :
            document.getElementById('guideTokenInput');
    }

    /**
     * 显示状态信息
     */
    showStatus(isValid, message) {
        const statusDiv = document.getElementById('tokenStatus');
        const iconSpan = document.getElementById('statusIcon');
        const textSpan = document.getElementById('statusText');

        if (statusDiv && iconSpan && textSpan) {
            statusDiv.style.display = 'flex';
            statusDiv.className = `token-status ${isValid ? 'valid' : 'invalid'}`;
            iconSpan.textContent = isValid ? '✅' : '❌';
            textSpan.textContent = message;
        }
    }

    /**
     * 隐藏状态信息
     */
    hideStatus() {
        const statusDiv = document.getElementById('tokenStatus');
        if (statusDiv) {
            statusDiv.style.display = 'none';
        }
    }

    /**
     * 显示测试按钮
     */
    showTestButton() {
        const testBtn = document.getElementById('testBtn');
        if (testBtn) {
            testBtn.style.display = 'inline-block';
        }
    }

    /**
     * 隐藏测试按钮
     */
    hideTestButton() {
        const testBtn = document.getElementById('testBtn');
        if (testBtn) {
            testBtn.style.display = 'none';
        }
    }

    /**
     * 检查现有Token
     */
    checkExistingToken() {
        const existingToken = this.getStoredToken();
        if (existingToken) {
            // 显示部分Token信息
            const maskedToken = this.maskToken(existingToken);
            const tokenInput = document.getElementById('tokenInput');
            if (tokenInput) {
                tokenInput.placeholder = `当前Token: ${maskedToken}`;
            }
            this.showStatus(true, '✅ 已配置Token');
        }
    }

    /**
     * 获取存储的Token
     */
    getStoredToken() {
        // 按优先级检查Token来源
        const sources = [
            () => new URLSearchParams(window.location.search).get('token'),
            () => localStorage.getItem('github_token'),
            () => window.GITHUB_TOKEN
        ];

        for (const getToken of sources) {
            try {
                const token = getToken();
                if (token && this.isValidTokenFormat(token)) {
                    return token;
                }
            } catch (error) {
                console.warn('获取Token时出错:', error);
            }
        }

        return null;
    }

    /**
     * 验证Token格式
     */
    isValidTokenFormat(token) {
        return token && typeof token === 'string' &&
            (token.startsWith('ghp_') || token.startsWith('github_pat_'));
    }

    /**
     * 遮盖Token显示
     */
    maskToken(token) {
        if (!token || token.length < 16) return '***';
        return token.substring(0, 8) + '*'.repeat(12) + token.substring(token.length - 4);
    }

    /**
     * 测试Token连接
     */
    async test() {
        const input = this.getCurrentInput();
        if (!input) return;

        const token = input.value.trim();
        if (!token) {
            alert('请先输入Token');
            return;
        }

        if (!this.isValidTokenFormat(token)) {
            alert('Token格式不正确');
            return;
        }

        this.showStatus(true, '🔍 正在测试连接...');

        try {
            const response = await fetch('https://api.github.com/user', {
                headers: {
                    'Authorization': `token ${token}`,
                    'Accept': 'application/vnd.github.v3+json'
                },
                timeout: 10000 // 10秒超时
            });

            if (response.ok) {
                const userData = await response.json();
                this.showStatus(true, `🎉 连接成功！用户: ${userData.login}`);

                // 检查权限
                await this.checkTokenPermissions(token);
            } else {
                const errorData = await response.json().catch(() => ({}));
                throw new Error(errorData.message || `HTTP ${response.status}: ${response.statusText}`);
            }
        } catch (error) {
            console.error('Token测试失败:', error);
            this.showStatus(false, `❌ 连接失败: ${error.message}`);
        }
    }

    /**
     * 检查Token权限
     */
    async checkTokenPermissions(token) {
        try {
            // 检查repo权限
            const repoResponse = await fetch(`https://api.github.com/repos/${GITHUB_REPO || 'octocat/Hello-World'}`, {
                headers: {
                    'Authorization': `token ${token}`,
                    'Accept': 'application/vnd.github.v3+json'
                }
            });

            const hasRepoAccess = repoResponse.ok;

            // 检查Actions权限（通过尝试获取workflow列表）
            const actionsResponse = await fetch(`https://api.github.com/repos/${GITHUB_REPO || 'octocat/Hello-World'}/actions/workflows`, {
                headers: {
                    'Authorization': `token ${token}`,
                    'Accept': 'application/vnd.github.v3+json'
                }
            });

            const hasActionsAccess = actionsResponse.ok;

            let permissionMessage = '✅ 权限检查通过';
            if (!hasRepoAccess) {
                permissionMessage = '⚠️ 缺少repo权限';
            } else if (!hasActionsAccess) {
                permissionMessage = '⚠️ 缺少workflow权限';
            }

            this.showStatus(hasRepoAccess && hasActionsAccess, permissionMessage);
        } catch (error) {
            console.warn('权限检查失败:', error);
            // 权限检查失败不影响主要功能
        }
    }

    /**
     * 保存Token配置
     */
    save() {
        const input = this.getCurrentInput();
        if (!input) {
            alert('输入框未找到');
            return;
        }

        const token = input.value.trim();

        // 验证Token
        if (!token) {
            alert('请输入GitHub Token');
            input.focus();
            return;
        }

        if (!this.isValidTokenFormat(token)) {
            alert('Token格式不正确，请检查输入\n\n正确格式应该是：\n• ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n• github_pat_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');
            input.focus();
            return;
        }

        try {
            // 检查是否保存到本地存储
            const shouldSave = document.getElementById('saveToken')?.checked ||
                this.currentMethod === 'guide'; // 指南模式默认保存

            if (shouldSave) {
                localStorage.setItem('github_token', token);
                console.log('✅ Token已保存到本地存储');
            }

            // 设置到全局变量
            window.GITHUB_TOKEN = token;

            this.showStatus(true, '💾 Token配置成功！');

            // 触发配置完成事件
            this.triggerTokenConfiguredEvent(token);

            // 延迟关闭模态框
            setTimeout(() => {
                this.close();
                this.showSuccessMessage();
            }, 1500);

        } catch (error) {
            console.error('保存Token失败:', error);
            alert('保存Token失败: ' + error.message);
        }
    }

    /**
     * 触发Token配置完成事件
     */
    triggerTokenConfiguredEvent(token) {
        // 调用全局回调函数（如果存在）
        if (typeof window.onTokenConfigured === 'function') {
            window.onTokenConfigured(token);
        }

        // 触发自定义事件
        const event = new CustomEvent('tokenConfigured', {
            detail: {
                token: token,
                maskedToken: this.maskToken(token)
            }
        });
        window.dispatchEvent(event);

        console.log('🎉 Token配置完成事件已触发');
    }

    /**
     * 显示成功消息
     */
    showSuccessMessage() {
        // 可以在这里添加成功提示的UI
        const notification = document.createElement('div');
        notification.className = 'token-success-notification';
        notification.innerHTML = `
            <div class="notification-content">
                <span class="notification-icon">✅</span>
                <span class="notification-text">GitHub Token 配置成功！</span>
            </div>
        `;

        notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
            border-radius: 8px;
            padding: 15px 20px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
            z-index: 10001;
            animation: slideInRight 0.3s ease-out;
        `;

        document.body.appendChild(notification);

        // 3秒后自动移除
        setTimeout(() => {
            notification.style.animation = 'slideOutRight 0.3s ease-in';
            setTimeout(() => {
                if (notification.parentNode) {
                    notification.parentNode.removeChild(notification);
                }
            }, 300);
        }, 3000);
    }

    /**
     * 清除Token配置
     */
    clear() {
        const confirmMessage = `
确定要清除Token配置吗？

清除后将无法进行以下操作：
• 触发GitHub Actions编译
• 监控编译进度
• 自动发布固件

您需要重新配置Token才能使用编译功能。
        `.trim();

        if (confirm(confirmMessage)) {
            try {
                // 清除所有存储的Token
                localStorage.removeItem('github_token');
                delete window.GITHUB_TOKEN;

                // 清空输入框
                const inputs = document.querySelectorAll('#tokenInput, #guideTokenInput');
                inputs.forEach(input => {
                    if (input) {
                        input.value = '';
                        input.placeholder = input === document.getElementById('tokenInput') ?
                            '请输入以 ghp_ 或 github_pat_ 开头的Token' :
                            'ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
                        input.style.borderColor = '#e0e0e0';
                    }
                });

                // 重置状态
                this.hideStatus();
                this.hideTestButton();

                // 触发Token清除事件
                window.dispatchEvent(new CustomEvent('tokenCleared'));

                alert('✅ Token配置已清除');
                console.log('🗑️ Token配置已清除');

            } catch (error) {
                console.error('清除Token失败:', error);
                alert('清除Token失败: ' + error.message);
            }
        }
    }

    /**
     * 获取当前有效的Token
     */
    getValidToken() {
        return this.getStoredToken();
    }

    /**
     * 检查是否有有效的Token
     */
    hasValidToken() {
        return !!this.getValidToken();
    }
}

// 创建全局Token管理器实例
window.tokenModal = new TokenModalManager();

// 兼容性函数（供其他脚本调用）
window.showTokenModal = () => window.tokenModal.show();
window.closeTokenModal = () => window.tokenModal.close();
window.clearTokenConfig = () => window.tokenModal.clear();
window.getValidToken = () => window.tokenModal.getValidToken();
window.hasValidToken = () => window.tokenModal.hasValidToken();

// 添加必要的CSS动画
const style = document.createElement('style');
style.textContent = `
@keyframes slideInRight {
    from {
        transform: translateX(100%);
        opacity: 0;
    }
    to {
        transform: translateX(0);
        opacity: 1;
    }
}

@keyframes slideOutRight {
    from {
        transform: translateX(0);
        opacity: 1;
    }
    to {
        transform: translateX(100%);
        opacity: 0;
    }
}

.modal-close {
    position: absolute;
    top: 15px;
    right: 20px;
    background: none;
    border: none;
    font-size: 24px;
    font-weight: bold;
    color: #999;
    cursor: pointer;
    transition: color 0.3s ease;
}

.modal-close:hover {
    color: #333;
}

.checkbox-label {
    display: flex;
    align-items: center;
    gap: 8px;
    cursor: pointer;
}

.checkbox-text {
    user-select: none;
}

.btn-success {
    background: linear-gradient(135deg, #27ae60, #2ecc71);
    color: white;
}

.btn-success:hover {
    transform: translateY(-2px);
    box-shadow: 0 5px 15px rgba(39, 174, 96, 0.4);
}
`;

// 将样式添加到页面
if (document.head) {
    document.head.appendChild(style);
} else {
    document.addEventListener('DOMContentLoaded', () => {
        document.head.appendChild(style);
    });
}

console.log('📦 Token模态框管理器已加载');