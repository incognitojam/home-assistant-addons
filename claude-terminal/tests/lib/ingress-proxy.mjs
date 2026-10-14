// A minimal stand-in for Home Assistant ingress.
//
// Supervisor serves an add-on at /api/hassio_ingress/<token>/ and forwards
// <prefix>/<path> to http://<addon>:<port>/<path>, adding X-Ingress-Path and
// X-Forwarded-* headers, for both plain HTTP and WebSocket upgrades. Anything
// outside the prefix is not the add-on's to serve, so this proxy answers 404
// there. A page that uses absolute URLs (/token, /ws, /assets/...) therefore
// breaks here just as it would behind real ingress.

import http from 'node:http';
import net from 'node:net';

export async function startIngressProxy({ target, token = 'e2e-synthetic-ingress-token' }) {
    const targetUrl = new URL(target);
    const prefix = `/api/hassio_ingress/${token}`;
    const misses = [];
    const tunnels = new Set();

    const upstreamPath = url => (url.startsWith(`${prefix}/`) ? url.slice(prefix.length) : undefined);

    const forwardedHeaders = (req, proxyHost) => ({
        ...req.headers,
        host: targetUrl.host,
        'x-ingress-path': prefix,
        'x-forwarded-for': req.socket.remoteAddress,
        'x-forwarded-host': proxyHost,
        'x-forwarded-proto': 'http',
    });

    const server = http.createServer((req, res) => {
        const path = upstreamPath(req.url);
        if (path === undefined) {
            misses.push(req.url);
            res.writeHead(404, { 'content-type': 'text/plain' }).end(`Not under ingress prefix: ${req.url}\n`);
            return;
        }

        const upstream = http.request({
            host: targetUrl.hostname,
            port: targetUrl.port,
            method: req.method,
            path,
            headers: forwardedHeaders(req, req.headers.host),
        }, upstreamRes => {
            res.writeHead(upstreamRes.statusCode, upstreamRes.headers);
            upstreamRes.pipe(res);
        });
        upstream.on('error', error => {
            res.writeHead(502, { 'content-type': 'text/plain' }).end(`Upstream error: ${error.message}\n`);
        });
        req.pipe(upstream);
    });

    // Forward WebSocket upgrades as a raw TCP tunnel after rewriting the
    // request line, so subprotocol negotiation (ttyd requires "tty") and
    // framing are untouched end to end.
    server.on('upgrade', (req, socket, head) => {
        const path = upstreamPath(req.url);
        if (path === undefined) {
            misses.push(req.url);
            socket.end('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
            return;
        }

        const upstream = net.connect(Number(targetUrl.port), targetUrl.hostname, () => {
            const headers = forwardedHeaders(req, req.headers.host);
            const headerLines = Object.entries(headers).map(([name, value]) => `${name}: ${value}`);
            upstream.write(`${req.method} ${path} HTTP/1.1\r\n${headerLines.join('\r\n')}\r\n\r\n`);
            if (head.length) upstream.write(head);
            upstream.pipe(socket);
            socket.pipe(upstream);
        });
        tunnels.add(socket).add(upstream);
        const close = () => {
            socket.destroy();
            upstream.destroy();
            tunnels.delete(socket);
            tunnels.delete(upstream);
        };
        upstream.on('error', close);
        socket.on('error', close);
        upstream.on('close', close);
        socket.on('close', close);
    });

    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const { port } = server.address();

    return {
        // Real ingress URLs always end in a slash; ttyd builds its token and
        // WebSocket URLs relative to location.pathname.
        url: `http://127.0.0.1:${port}${prefix}/`,
        prefix,
        misses,
        close: () => new Promise(resolve => {
            tunnels.forEach(tunnel => tunnel.destroy());
            server.closeAllConnections();
            server.close(() => resolve());
        }),
    };
}
