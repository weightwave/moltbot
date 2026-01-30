#!/bin/bash
set -e

CONFIG_DIR="/root/.clawdbot"
mkdir -p "$CONFIG_DIR"

echo "=== Railway Moltbot Startup ==="
echo "PORT: ${PORT:-18789}"

# 运行非交互式 onboard
echo "Running onboarding..."
node dist/index.js onboard \
  --non-interactive \
  --accept-risk \
  --flow quickstart \
  --gateway-bind lan \
  --gateway-port "${PORT:-18789}" \
  --gateway-auth password \
  --gateway-password "${GATEWAY_PASSWORD}" \
  --auth-choice gemini-api-key \
  --gemini-api-key "${GEMINI_API_KEY}" \
  --skip-channels \
  --skip-skills \
  --skip-health

echo "Onboarding complete."

# 配置 Team9 Channel (如果环境变量存在)
if [ -n "$TEAM9_BASE_URL" ] && [ -n "$TEAM9_USERNAME" ] && [ -n "$TEAM9_PASSWORD" ]; then
  echo "Configuring Team9 channel..."

  CONFIG_FILE="$CONFIG_DIR/moltbot.json"

  # 使用 node 来更新配置文件 (合并而非覆盖)
  node -e "
const fs = require('fs');
const path = '$CONFIG_FILE';

let config = {};
try {
  const content = fs.readFileSync(path, 'utf8');
  // 简单的 JSON5 解析 (移除注释和尾随逗号)
  const jsonStr = content
    .replace(/\/\/.*$/gm, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/,(\s*[}\]])/g, '\$1');
  config = JSON.parse(jsonStr);
  console.log('Loaded existing config');
} catch (e) {
  console.log('Creating new config file');
}

// 合并 Team9 配置 (保留其他配置)
config.channels = config.channels || {};
config.channels.team9 = {
  ...(config.channels.team9 || {}),
  enabled: true,
  baseUrl: process.env.TEAM9_BASE_URL,
  wsUrl: process.env.TEAM9_WS_URL || process.env.TEAM9_BASE_URL.replace(/^http/, 'ws') + '/im',
  credentials: {
    username: process.env.TEAM9_USERNAME,
    password: process.env.TEAM9_PASSWORD
  },
  dm: {
    ...(config.channels.team9?.dm || {}),
    policy: process.env.TEAM9_DM_POLICY || 'allow'
  }
};

// 添加可选配置
if (process.env.TEAM9_WORKSPACE_ID) {
  config.channels.team9.workspaceId = process.env.TEAM9_WORKSPACE_ID;
}

// 启用 team9 插件 (bundled 插件默认禁用，必须显式启用)
config.plugins = config.plugins || {};
config.plugins.entries = config.plugins.entries || {};
config.plugins.entries.team9 = {
  ...(config.plugins.entries.team9 || {}),
  enabled: true
};

// 配置 agents.defaults (性能与并发)
config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
Object.assign(config.agents.defaults, {
  contextPruning: { mode: 'cache-ttl', ttl: '1h' },
  compaction: { mode: 'safeguard' },
  heartbeat: { every: '30m' },
  maxConcurrent: 4,
  subagents: { maxConcurrent: 8 }
});

// 配置 LLM 模型 (如果环境变量存在)
if (process.env.LLM_MODEL) {
  config.agents.defaults.model = {
    ...(config.agents.defaults.model || {}),
    primary: process.env.LLM_MODEL
  };
  console.log('LLM Model: ' + process.env.LLM_MODEL);
}

// 消息确认策略
config.messages = config.messages || {};
config.messages.ackReactionScope = config.messages.ackReactionScope || 'group-mentions';

// 启用原生命令与技能
config.commands = config.commands || {};
config.commands.native = config.commands.native || 'auto';
config.commands.nativeSkills = config.commands.nativeSkills || 'auto';

// 启用内部 hooks (session-memory / boot-md / command-logger)
config.hooks = config.hooks || {};
config.hooks.internal = {
  enabled: true,
  entries: {
    'boot-md': { enabled: true },
    'command-logger': { enabled: true },
    'session-memory': { enabled: true }
  }
};

// skills 包管理器
config.skills = config.skills || {};
config.skills.install = config.skills.install || {};
config.skills.install.nodeManager = config.skills.install.nodeManager || 'pnpm';

fs.writeFileSync(path, JSON.stringify(config, null, 2));
console.log('Team9 channel configured: ' + process.env.TEAM9_BASE_URL);
console.log('  Username: ' + process.env.TEAM9_USERNAME);
"
fi

echo "Starting Gateway..."

# 启动 Gateway
exec node dist/index.js gateway --bind lan --port "${PORT:-18789}"
