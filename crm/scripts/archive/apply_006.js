const https = require('https');
const fs = require('fs');

const TOKEN = process.env.SUPABASE_TOKEN;
const PROJECT_ID = 'hklfcfadultzuhwgkqmz';

function mcpRequest(sessionId, method, params) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ jsonrpc: '2.0', id: 1, method, params });
    const options = {
      hostname: 'mcp.supabase.com',
      path: '/mcp',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        'Authorization': 'Bearer ' + TOKEN,
        'Mcp-Session-Id': sessionId,
        'Content-Length': Buffer.byteLength(body)
      }
    };
    const req = https.request(options, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        const lines = data.split('\n');
        for (const line of lines) {
          if (line.startsWith('data: ')) {
            try { resolve(JSON.parse(line.slice(6))); return; } catch {}
          }
        }
        try { resolve(JSON.parse(data)); } catch { resolve({ raw: data }); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function initSession() {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'node-client', version: '1.0' } } });
    const options = {
      hostname: 'mcp.supabase.com',
      path: '/mcp',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        'Authorization': 'Bearer ' + TOKEN,
        'Content-Length': Buffer.byteLength(body)
      }
    };
    const req = https.request(options, res => {
      const sessionId = res.headers['mcp-session-id'];
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(sessionId));
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function main() {
  console.log('Initializing MCP session...');
  const sessionId = await initSession();
  console.log('Session ID:', sessionId);

  const sql = fs.readFileSync('c:/Users/venan/.gemini/antigravity/scratch/atlasEye/database/006_rbac_and_automation.sql', 'utf8');

  console.log('Applying migration 006_rbac_and_automation...');
  const result = await mcpRequest(sessionId, 'tools/call', {
    name: 'apply_migration',
    arguments: {
      project_id: PROJECT_ID,
      name: '006_rbac_and_automation',
      query: sql
    }
  });
  console.log('Migration result:', JSON.stringify(result, null, 2));
}

main().catch(console.error);
