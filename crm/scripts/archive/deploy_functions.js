const https = require('https');
const fs = require('fs');

const TOKEN = process.env.SUPABASE_TOKEN;
const PROJECT_ID = 'hklfcfadultzuhwgkqmz';
const BASE = 'c:/Users/venan/.gemini/antigravity/scratch/atlasEye/supabase/functions';

function initSession() {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'node-client', version: '1.0' } } });
    const options = {
      hostname: 'mcp.supabase.com', path: '/mcp', method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream', 'Authorization': 'Bearer ' + TOKEN, 'Content-Length': Buffer.byteLength(body) }
    };
    const req = https.request(options, res => {
      const sessionId = res.headers['mcp-session-id'];
      let data = ''; res.on('data', c => data += c); res.on('end', () => resolve(sessionId));
    });
    req.on('error', reject); req.write(body); req.end();
  });
}

function mcpRequest(sessionId, method, params) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ jsonrpc: '2.0', id: 1, method, params });
    const options = {
      hostname: 'mcp.supabase.com', path: '/mcp', method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream', 'Authorization': 'Bearer ' + TOKEN, 'Mcp-Session-Id': sessionId, 'Content-Length': Buffer.byteLength(body) }
    };
    const req = https.request(options, res => {
      let data = ''; res.on('data', c => data += c);
      res.on('end', () => {
        for (const line of data.split('\n')) {
          if (line.startsWith('data: ')) { try { resolve(JSON.parse(line.slice(6))); return; } catch { } }
        }
        try { resolve(JSON.parse(data)); } catch { resolve({ raw: data }); }
      });
    });
    req.on('error', reject); req.write(body); req.end();
  });
}

async function deployFn(sessionId, name, filePath) {
  const code = fs.readFileSync(filePath, 'utf8');
  console.log(`Deploying ${name}...`);
  const result = await mcpRequest(sessionId, 'tools/call', {
    name: 'deploy_edge_function',
    arguments: { project_id: PROJECT_ID, name, entrypoint_path: `supabase/functions/${name}/index.ts`, files: [{ name: `supabase/functions/${name}/index.ts`, content: code }] }
  });
  const txt = result?.result?.content?.[0]?.text ?? JSON.stringify(result);
  console.log(`${name}:`, txt);
}

async function main() {
  const sessionId = await initSession();
  console.log('Session:', sessionId.slice(0, 30) + '...');

  await deployFn(sessionId, 'accept-invite', `${BASE}/accept-invite/index.ts`);
  await deployFn(sessionId, 'generate-ai-insights', `${BASE}/generate-ai-insights/index.ts`);
  await deployFn(sessionId, 'invite-member', `${BASE}/invite-member/index.ts`);
  await deployFn(sessionId, 'manage-member', `${BASE}/manage-member/index.ts`);

  console.log('All deployments done.');
}

main().catch(console.error);
