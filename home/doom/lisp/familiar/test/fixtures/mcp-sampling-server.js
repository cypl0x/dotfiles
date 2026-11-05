// A fake MCP server: asks its client for a completion (sampling), writes the answer.
const fs = require('fs');
const out = process.argv[2];
let buf = '', clientCaps = null;
const send = (m) => process.stdout.write(JSON.stringify(m) + '\n');
process.stdin.on('data', (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i); buf = buf.slice(i + 1);
    if (!line.trim()) continue;
    const m = JSON.parse(line);
    if (m.method === 'initialize') {
      clientCaps = m.params.capabilities;
      send({jsonrpc: '2.0', id: m.id, result: {protocolVersion: m.params.protocolVersion, capabilities: {}, serverInfo: {name: 'fake', version: '0'}}});
    } else if (m.method === 'notifications/initialized') {
      send({jsonrpc: '2.0', id: 's1', method: 'sampling/createMessage',
            params: {messages: [{role: 'user', content: {type: 'text', text: 'Say hi'}}],
                     systemPrompt: 'Be brief.', maxTokens: 50,
                     modelPreferences: {hints: [{name: 'haiku'}], intelligencePriority: 0.9}}});
    } else if (m.id === 's1' && !m.method) {
      fs.writeFileSync(out, JSON.stringify({clientCaps, reply: m}));
    } else if (m.id !== undefined && m.method) {
      send({jsonrpc: '2.0', id: m.id, result: {}});
    }
  }
});
