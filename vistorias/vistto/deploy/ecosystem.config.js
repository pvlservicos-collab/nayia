// PM2 (VPS sem Docker): pm2 start deploy/ecosystem.config.js && pm2 save
module.exports = {
  apps: [{
    name: 'vistto',
    script: 'server/index.js',
    node_args: '--no-warnings',
    cwd: __dirname + '/..',
    env: { NODE_ENV: 'production', PORT: 3000 },
    max_memory_restart: '700M',
  }],
};
