// Minimal stand-in for seo-hub used by tests/hub.test.sh. Records requests, answers the contract.
const http = require('node:http')
const log = []
let flaky = 0 // number of 500s to return before succeeding on /api/plan
const server = http.createServer((req, res) => {
  let body = ''
  req.on('data', (c) => (body += c))
  req.on('end', () => {
    log.push({ method: req.method, url: req.url, auth: req.headers.authorization, body: body ? JSON.parse(body) : null })
    const send = (code, obj) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj)) }
    if (req.headers.authorization !== 'Bearer tok') return send(401, { error: 'unauthorized' })
    if (req.url === '/__log') return send(200, log)
    if (req.url === '/__flaky') { flaky = 2; return send(200, {}) }
    if (req.url === '/api/plan') { if (flaky > 0) { flaky--; return send(500, { error: 'boom' }) } return send(200, { weekOf: '2026-08-31', sites: [] }) }
    if (req.url === '/api/runs' && req.method === 'POST') return send(201, { run: { id: 7 } })
    if (/^\/api\/runs\/\d+$/.test(req.url) && req.method === 'PATCH') return send(200, { run: { id: 7, summary: log.at(-1).body.summary } })
    if (req.url === '/api/jobs' && req.method === 'POST') return send(201, { job: { id: 42 } })
    if (req.url === '/api/jobs' && req.method === 'GET') return send(200, { jobs: [] })
    if (/^\/api\/jobs\/42\/steps$/.test(req.url)) return send(200, { job: { id: 42, state: 'researched' } })
    if (/^\/api\/jobs\/42\/audit$/.test(req.url)) return send(200, { pass: false, issues: [{ code: 'x', severity: 'error', message: 'm' }] })
    if (/^\/api\/jobs\/42\/articles$/.test(req.url)) return send(200, { article: { id: 1 } })
    if (/^\/api\/jobs\/42\/schedule$/.test(req.url)) return send(200, { job: { id: 42, state: 'scheduled' } })
    if (/^\/api\/jobs\/99\/schedule$/.test(req.url)) return send(404, { error: 'not found' })
    send(404, { error: 'no route' })
  })
})
server.listen(Number(process.env.PORT || 3999), () => console.log('mock-hub listening'))
