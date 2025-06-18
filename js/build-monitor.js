/**
 * OpenWrt 编译监控增强模块
 * 专门处理GitHub Actions实时状态监控和进度更新
 */

class BuildMonitorEnhanced {
    constructor() {
        this.isMonitoring = false;
        this.monitorInterval = null;
        this.currentRunId = null;
        this.startTime = null;
        this.lastStatus = null;
        this.checkCount = 0;
        this.maxChecks = 150; // 最多监控2.5小时
        this.checkIntervalMs = 60000; // 每分钟检查一次

        this.init();
    }

    init() {
        console.log('🔨 初始化增强编译监控模块');
        this.bindEvents();
    }

    /**
     * 绑定事件监听器
     */
    bindEvents() {
        // 监听页面可见性变化，优化性能
        document.addEventListener('visibilitychange', () => {
            if (document.hidden && this.isMonitoring) {
                console.log('📱 页面隐藏，降低监控频率');
                this.adjustMonitoringFrequency(true);
            } else if (!document.hidden && this.isMonitoring) {
                console.log('📱 页面显示，恢复正常监控频率');
                this.adjustMonitoringFrequency(false);
            }
        });

        // 监听网络状态变化
        if ('onLine' in navigator) {
            window.addEventListener('online', () => {
                console.log('🌐 网络连接恢复');
                if (this.isMonitoring) {
                    this.addLogEntry('info', '🌐 网络连接恢复，继续监控编译进度');
                }
            });

            window.addEventListener('offline', () => {
                console.log('🌐 网络连接断开');
                if (this.isMonitoring) {
                    this.addLogEntry('warning', '⚠️ 网络连接断开，监控可能受影响');
                }
            });
        }
    }

    /**
     * 开始监控指定的GitHub Actions运行
     */
    async startMonitoring(token, repoUrl, buildConfig = {}) {
        try {
            this.isMonitoring = true;
            this.startTime = Date.now();
            this.checkCount = 0;
            this.lastStatus = null;

            console.log('🚀 开始GitHub Actions编译监控');
            this.addLogEntry('info', '🔄 开始监控GitHub Actions编译状态...');

            // 等待GitHub处理dispatch事件
            this.addLogEntry('info', '⏳ 等待GitHub Actions处理编译请求...');
            await this.delay(10000); // 等待10秒

            // 查找最新的工作流运行
            await this.findLatestWorkflowRun(token, repoUrl);

        } catch (error) {
            console.error('启动监控失败:', error);
            this.addLogEntry('error', `❌ 启动监控失败: ${error.message}`);
            this.stopMonitoring();
        }
    }

    /**
     * 查找最新的工作流运行
     */
    async findLatestWorkflowRun(token, repoUrl, retryCount = 0) {
        try {
            const maxRetries = 5;

            // 获取最新的工作流运行
            const runsResponse = await fetch(`https://api.github.com/repos/${repoUrl}/actions/runs?per_page=10`, {
                headers: {
                    'Authorization': `token ${token}`,
                    'Accept': 'application/vnd.github.v3+json',
                    'User-Agent': 'OpenWrt-Smart-Builder'
                }
            });

            if (!runsResponse.ok) {
                throw new Error(`获取工作流运行失败: ${runsResponse.status} ${runsResponse.statusText}`);
            }

            const runsData = await runsResponse.json();

            // 查找最新的智能编译工作流运行（最近5分钟内启动的）
            const fiveMinutesAgo = Date.now() - 5 * 60 * 1000;
            const recentRuns = runsData.workflow_runs.filter(run => {
                const runTime = new Date(run.created_at).getTime();
                return runTime > fiveMinutesAgo;
            });

            // 查找智能编译工作流
            const smartBuildRun = recentRuns.find(run =>
                run.name.includes('智能编译') ||
                run.name.includes('Smart Build') ||
                run.path.includes('smart-build.yml') ||
                (run.event === 'repository_dispatch' && run.status !== 'completed')
            );

            if (smartBuildRun) {
                this.currentRunId = smartBuildRun.id;
                this.addLogEntry('success', `🎯 找到编译任务 #${smartBuildRun.run_number}`);
                this.addLogEntry('info', `📋 运行状态: ${this.getStatusText(smartBuildRun.status)}`);
                this.addLogEntry('info', `🕐 启动时间: ${new Date(smartBuildRun.created_at).toLocaleString()}`);

                // 开始持续监控这个运行
                this.startContinuousMonitoring(token, repoUrl, smartBuildRun.id);

            } else if (retryCount < maxRetries) {
                // 没找到，继续等待并重试
                this.addLogEntry('info', `🔍 第${retryCount + 1}次查找编译任务...`);
                setTimeout(() => {
                    if (this.isMonitoring) {
                        this.findLatestWorkflowRun(token, repoUrl, retryCount + 1);
                    }
                }, 15000); // 15秒后重试

            } else {
                // 重试次数用完，切换到基础监控
                this.addLogEntry('warning', '⚠️ 未找到对应的编译任务');
                this.addLogEntry('info', '🔄 可能编译任务仍在队列中，切换到基础监控模式');
                this.startBasicMonitoring(token, repoUrl);
            }

        } catch (error) {
            console.error('查找工作流运行失败:', error);
            this.addLogEntry('error', `❌ 查找编译任务失败: ${error.message}`);

            if (retryCount < 3) {
                this.addLogEntry('info', '🔄 稍后重试查找...');
                setTimeout(() => {
                    if (this.isMonitoring) {
                        this.findLatestWorkflowRun(token, repoUrl, retryCount + 1);
                    }
                }, 20000);
            } else {
                this.startBasicMonitoring(token, repoUrl);
            }
        }
    }

    /**
     * 开始持续监控工作流运行
     */
    startContinuousMonitoring(token, repoUrl, runId) {
        console.log(`📊 开始持续监控运行 ${runId}`);

        this.monitorInterval = setInterval(async () => {
            this.checkCount++;

            try {
                // 检查网络连接
                if (!navigator.onLine) {
                    this.addLogEntry('warning', '⚠️ 网络连接断开，跳过本次检查');
                    return;
                }

                // 获取工作流运行详细信息
                const runData = await this.fetchWorkflowRunData(token, repoUrl, runId);

                if (runData) {
                    // 更新进度和状态
                    this.updateBuildProgress(runData);

                    // 如果编译完成，停止监控
                    if (this.isRunCompleted(runData.status)) {
                        this.handleBuildCompletion(runData, repoUrl);
                        this.stopMonitoring();
                        return;
                    }

                    // 获取工作流作业详情（更详细的进度信息）
                    await this.fetchJobDetails(token, repoUrl, runId, runData);
                }

                // 检查是否超时
                if (this.checkCount >= this.maxChecks) {
                    this.addLogEntry('warning', '⚠️ 监控超时，请手动检查编译状态');
                    this.addLogEntry('info', `🔗 查看详情: https://github.com/${repoUrl}/actions/runs/${runId}`);
                    this.stopMonitoring();
                }

            } catch (error) {
                console.error('监控过程中出错:', error);
                this.addLogEntry('warning', `⚠️ 监控连接异常: ${error.message}`);

                // 连续失败3次后切换到基础监控
                if (this.checkCount % 3 === 0) {
                    this.addLogEntry('info', '🔄 切换到基础监控模式...');
                    this.stopMonitoring();
                    this.startBasicMonitoring(token, repoUrl);
                }
            }
        }, this.checkIntervalMs);
    }

    /**
     * 获取工作流运行数据
     */
    async fetchWorkflowRunData(token, repoUrl, runId) {
        const response = await fetch(`https://api.github.com/repos/${repoUrl}/actions/runs/${runId}`, {
            headers: {
                'Authorization': `token ${token}`,
                'Accept': 'application/vnd.github.v3+json',
                'User-Agent': 'OpenWrt-Smart-Builder'
            }
        });

        if (!response.ok) {
            throw new Error(`获取运行数据失败: ${response.status} ${response.statusText}`);
        }

        return await response.json();
    }

    /**
     * 获取工作流作业详情
     */
    async fetchJobDetails(token, repoUrl, runId, runData) {
        try {
            const jobsResponse = await fetch(`https://api.github.com/repos/${repoUrl}/actions/runs/${runId}/jobs`, {
                headers: {
                    'Authorization': `token ${token}`,
                    'Accept': 'application/vnd.github.v3+json',
                    'User-Agent': 'OpenWrt-Smart-Builder'
                }
            });

            if (jobsResponse.ok) {
                const jobsData = await jobsResponse.json();
                this.updateJobProgress(jobsData.jobs, runData);
            }
        } catch (error) {
            // 作业详情获取失败不影响主要监控流程
            console.warn('获取作业详情失败:', error);
        }
    }

    /**
     * 更新作业进度
     */
    updateJobProgress(jobs, runData) {
        if (!jobs || jobs.length === 0) return;

        // 找到当前正在运行的作业
        const currentJob = jobs.find(job => job.status === 'in_progress') || jobs[jobs.length - 1];

        if (currentJob && currentJob.status !== this.lastJobStatus) {
            this.lastJobStatus = currentJob.status;

            // 显示当前作业信息
            if (currentJob.status === 'in_progress') {
                this.addLogEntry('info', `🔨 正在执行: ${currentJob.name}`);

                // 如果有步骤信息，显示详细进度
                if (currentJob.steps && currentJob.steps.length > 0) {
                    const completedSteps = currentJob.steps.filter(step => step.status === 'completed').length;
                    const totalSteps = currentJob.steps.length;
                    const stepProgress = Math.floor((completedSteps / totalSteps) * 100);

                    this.addLogEntry('info', `📋 步骤进度: ${completedSteps}/${totalSteps} (${stepProgress}%)`);
                }
            }
        }
    }

    /**
     * 更新编译进度
     */
    updateBuildProgress(runData) {
        const { status, conclusion, created_at, updated_at, run_number } = runData;

        // 防止重复更新相同状态
        if (this.lastStatus === status && status !== 'in_progress') {
            return;
        }
        this.lastStatus = status;

        let progress = 0;
        let statusText = '';
        let logLevel = 'info';

        // 根据状态计算进度
        switch (status) {
            case 'queued':
                progress = 5;
                statusText = `⏳ 编译任务 #${run_number} 排队中...`;
                break;

            case 'in_progress':
                // 根据运行时间和典型编译时间估算进度
                const startTime = new Date(created_at).getTime();
                const currentTime = Date.now();
                const elapsed = currentTime - startTime;

                // 不同阶段的估算时间（毫秒）
                const phases = [
                    { name: '环境准备', duration: 3 * 60 * 1000, progress: 10 },      // 3分钟
                    { name: '下载源码', duration: 8 * 60 * 1000, progress: 20 },      // 8分钟  
                    { name: '配置编译', duration: 5 * 60 * 1000, progress: 30 },      // 5分钟
                    { name: '编译内核', duration: 25 * 60 * 1000, progress: 60 },     // 25分钟
                    { name: '编译软件包', duration: 35 * 60 * 1000, progress: 85 },   // 35分钟
                    { name: '打包固件', duration: 8 * 60 * 1000, progress: 95 }       // 8分钟
                ];

                let accumulatedTime = 0;
                let currentPhase = phases[0];

                for (const phase of phases) {
                    if (elapsed <= accumulatedTime + phase.duration) {
                        currentPhase = phase;
                        const phaseProgress = Math.min(1, (elapsed - accumulatedTime) / phase.duration);
                        const prevProgress = phases.indexOf(phase) > 0 ? phases[phases.indexOf(phase) - 1].progress : 0;
                        progress = prevProgress + (phase.progress - prevProgress) * phaseProgress;
                        break;
                    }
                    accumulatedTime += phase.duration;
                }

                // 确保进度不超过90%（为完成阶段预留）
                progress = Math.min(90, progress);

                statusText = `🚀 正在编译... (${currentPhase.name}) - 任务 #${run_number}`;

                // 定期显示时间信息
                const elapsedMinutes = Math.floor(elapsed / 60000);
                if (elapsedMinutes > 0 && this.checkCount % 3 === 0) { // 每3次检查显示一次
                    this.addLogEntry('info', `⏱️ 已运行 ${elapsedMinutes} 分钟，当前阶段: ${currentPhase.name}`);
                }
                break;

            case 'completed':
                progress = 100;
                if (conclusion === 'success') {
                    statusText = '✅ 编译成功完成！';
                    logLevel = 'success';
                } else if (conclusion === 'failure') {
                    statusText = '❌ 编译失败';
                    logLevel = 'error';
                } else if (conclusion === 'cancelled') {
                    statusText = '⚠️ 编译被取消';
                    logLevel = 'warning';
                } else {
                    statusText = '⚠️ 编译异常结束';
                    logLevel = 'warning';
                }
                break;

            default:
                statusText = `📊 状态: ${this.getStatusText(status)}`;
        }

        // 更新UI进度
        this.updateProgressBar(Math.floor(progress));

        // 只在状态变化时添加日志
        if (statusText !== this.lastStatusText) {
            this.addLogEntry(logLevel, statusText);
            this.lastStatusText = statusText;
        }

        // 更新浏览器标题
        this.updateBrowserTitle(progress);
    }

    /**
     * 更新进度条
     */
    updateProgressBar(progress) {
        const progressBar = document.getElementById('progress-bar');
        const progressText = document.getElementById('progress-text');
        const progressTime = document.getElementById('progress-time');

        if (progressBar) {
            progressBar.style.width = `${progress}%`;

            // 添加进度条动画效果
            progressBar.style.transition = 'width 0.5s ease-in-out';
        }

        if (progressText) {
            progressText.textContent = `${progress}%`;
        }

        if (progressTime && this.startTime) {
            const elapsed = Date.now() - this.startTime;
            const elapsedText = this.formatDuration(elapsed);

            if (progress > 5 && progress < 100) {
                // 估算剩余时间
                const estimatedTotal = (elapsed / progress) * 100;
                const remaining = estimatedTotal - elapsed;
                const remainingText = this.formatDuration(remaining);
                progressTime.textContent = `已用时: ${elapsedText} | 预计剩余: ${remainingText}`;
            } else {
                progressTime.textContent = `运行时间: ${elapsedText}`;
            }
        }
    }

    /**
     * 更新浏览器标题
     */
    updateBrowserTitle(progress) {
        if (progress < 100) {
            document.title = `[${Math.floor(progress)}%] OpenWrt 编译中...`;
        } else {
            document.title = 'OpenWrt 智能编译工具';
        }
    }

    /**
     * 处理编译完成
     */
    handleBuildCompletion(runData, repoUrl) {
        const { conclusion, created_at, updated_at } = runData;
        const duration = this.calculateDuration(created_at, updated_at);

        switch (conclusion) {
            case 'success':
                this.addLogEntry('success', '🎉 固件编译成功完成！');
                this.addLogEntry('info', `🕐 总耗时: ${duration}`);
                this.addLogEntry('info', `🔗 查看结果: https://github.com/${repoUrl}/actions/runs/${runData.id}`);
                this.addLogEntry('info', `📦 下载固件: https://github.com/${repoUrl}/releases`);
                this.showNotification('编译成功', '固件编译完成，请前往Releases页面下载', 'success');
                break;

            case 'failure':
                this.addLogEntry('error', '❌ 固件编译失败');
                this.addLogEntry('info', `🕐 运行时间: ${duration}`);
                this.addLogEntry('error', `🔍 查看详细日志: https://github.com/${repoUrl}/actions/runs/${runData.id}`);
                this.addLogEntry('info', '💡 建议: 检查插件冲突、减少插件数量或选择不同的源码分支');
                this.showNotification('编译失败', '请检查配置或查看详细日志', 'error');
                break;

            case 'cancelled':
                this.addLogEntry('warning', '⚠️ 编译任务已被取消');
                this.addLogEntry('info', `🕐 运行时间: ${duration}`);
                this.showNotification('编译取消', '编译任务已被取消', 'warning');
                break;

            default:
                this.addLogEntry('warning', `⚠️ 编译结束，状态: ${conclusion}`);
                this.addLogEntry('info', `🔗 查看详情: https://github.com/${repoUrl}/actions/runs/${runData.id}`);
        }
    }

    /**
     * 基础监控模式（备用方案）
     */
    startBasicMonitoring(token, repoUrl) {
        this.addLogEntry('info', '📊 启用基础监控模式');
        this.addLogEntry('info', '🔄 进度信息将基于预估时间显示');

        let progress = 10;
        let phaseIndex = 0;
        const phases = [
            { name: '环境准备', duration: 2 * 60 * 1000 },
            { name: '下载源码', duration: 5 * 60 * 1000 },
            { name: '配置编译', duration: 3 * 60 * 1000 },
            { name: '编译内核', duration: 25 * 60 * 1000 },
            { name: '编译软件包', duration: 35 * 60 * 1000 },
            { name: '打包固件', duration: 8 * 60 * 1000 }
        ];

        this.monitorInterval = setInterval(() => {
            if (!this.isMonitoring) return;

            progress += Math.random() * 3 + 1; // 每次增加1-4%
            progress = Math.min(progress, 95); // 最多到95%

            this.updateProgressBar(Math.floor(progress));

            // 模拟阶段变化
            const currentPhase = phases[Math.min(phaseIndex, phases.length - 1)];
            if (progress > (phaseIndex + 1) * 15 && phaseIndex < phases.length - 1) {
                phaseIndex++;
                this.addLogEntry('info', `🔄 当前阶段: ${phases[phaseIndex].name}`);
            }

            // 定期提醒用户查看GitHub Actions
            if (this.checkCount % 5 === 0) {
                this.addLogEntry('info', `📋 请访问 GitHub Actions 查看详细进度: https://github.com/${repoUrl}/actions`);
            }

            this.checkCount++;
        }, this.checkIntervalMs); // 每分钟更新一次
    }

    /**
     * 调整监控频率
     */
    adjustMonitoringFrequency(isBackground) {
        if (this.monitorInterval) {
            clearInterval(this.monitorInterval);

            // 背景模式降低检查频率
            this.checkIntervalMs = isBackground ? 120000 : 60000; // 背景2分钟，前台1分钟

            // 重新设置定时器
            this.monitorInterval = setInterval(() => {
                // 这里会调用相应的监控逻辑
            }, this.checkIntervalMs);
        }
    }

    /**
     * 停止监控
     */
    stopMonitoring() {
        this.isMonitoring = false;

        if (this.monitorInterval) {
            clearInterval(this.monitorInterval);
            this.monitorInterval = null;
        }

        console.log('🛑 停止编译进度监控');
        this.addLogEntry('info', '🛑 编译监控已停止');
    }

    // === 工具方法 ===

    /**
     * 延迟执行
     */
    delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    /**
     * 检查运行是否完成
     */
    isRunCompleted(status) {
        return ['completed', 'cancelled'].includes(status);
    }

    /**
     * 获取状态文本
     */
    getStatusText(status) {
        const statusMap = {
            'queued': '排队中',
            'in_progress': '进行中',
            'completed': '已完成',
            'cancelled': '已取消'
        };
        return statusMap[status] || status;
    }

    /**
     * 计算持续时间
     */
    calculateDuration(startTime, endTime) {
        const start = new Date(startTime).getTime();
        const end = new Date(endTime).getTime();
        return this.formatDuration(end - start);
    }

    /**
     * 格式化持续时间
     */
    formatDuration(duration) {
        const minutes = Math.floor(duration / 60000);
        const hours = Math.floor(minutes / 60);

        if (hours > 0) {
            return `${hours}小时${minutes % 60}分钟`;
        } else {
            return `${minutes}分钟`;
        }
    }

    /**
     * 添加日志条目
     */
    addLogEntry(type, message) {
        const logsContent = document.getElementById('logs-content');
        if (!logsContent) return;

        const timestamp = new Date().toLocaleTimeString();
        const logEntry = document.createElement('div');
        logEntry.className = `log-entry ${type}`;

        const iconMap = {
            'info': 'ℹ️',
            'success': '✅',
            'warning': '⚠️',
            'error': '❌'
        };

        const icon = iconMap[type] || 'ℹ️';

        logEntry.innerHTML = `
            <span class="log-timestamp">${timestamp}</span>
            <span class="log-icon">${icon}</span>
            <span class="log-message">${message}</span>
        `;

        logsContent.appendChild(logEntry);
        logsContent.scrollTop = logsContent.scrollHeight;

        // 控制台同步输出
        console.log(`[${timestamp}] ${type.toUpperCase()}: ${message}`);

        // 限制日志条目数量
        const maxLogEntries = 1000;
        const logEntries = logsContent.querySelectorAll('.log-entry');
        if (logEntries.length > maxLogEntries) {
            for (let i = 0; i < logEntries.length - maxLogEntries; i++) {
                logEntries[i].remove();
            }
        }
    }

    /**
     * 显示通知
     */
    showNotification(title, message, type = 'info') {
        // 浏览器通知
        if ('Notification' in window && Notification.permission === 'granted') {
            const notification = new Notification(title, {
                body: message,
                icon: '/favicon.ico',
                badge: '/favicon.ico'
            });

            setTimeout(() => notification.close(), 5000);
        }

        // 页面内通知
        this.showInPageNotification(title, message, type);
    }

    /**
     * 页面内通知
     */
    showInPageNotification(title, message, type) {
        const notification = document.createElement('div');
        notification.className = `notification notification-${type}`;
        notification.innerHTML = `
            <h4>${title}</h4>
            <p>${message}</p>
            <button onclick="this.parentElement.remove()">×</button>
        `;

        notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            background: ${type === 'success' ? '#4caf50' : type === 'error' ? '#f44336' : '#ff9800'};
            color: white;
            padding: 15px 20px;
            border-radius: 8px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
            z-index: 10000;
            max-width: 300px;
            animation: slideIn 0.3s ease;
        `;

        document.body.appendChild(notification);

        setTimeout(() => {
            if (notification.parentElement) {
                notification.remove();
            }
        }, 5000);
    }
}

// 创建全局监控实例
window.buildMonitorEnhanced = new BuildMonitorEnhanced();

// 导出供其他模块使用
if (typeof module !== 'undefined' && module.exports) {
    module.exports = BuildMonitorEnhanced;
}