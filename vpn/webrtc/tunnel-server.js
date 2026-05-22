/**
 * WebRTC DataChannel Tunnel — Layer 3 (аварийный)
 *
 * Запускается на VPS. Принимает WebRTC-соединения от браузерного клиента
 * и проксирует HTTP/HTTPS трафик через DataChannel.
 *
 * Схема:
 *   Браузер (tunnel-client.html)
 *     └─ WebRTC DataChannel (SCTP/DTLS через Yandex STUN)
 *         └─ этот сервер (WebSocket signaling + TCP proxy)
 *             └─ Интернет
 *
 * Почему WebRTC пробивает белые списки:
 *   ICE кандидаты проходят через STUN-серверы Яндекса (stun.yandex.ru),
 *   которые всегда в белом списке ТСПУ.
 */

'use strict';

const net  = require('net');
const http = require('http');
const { WebSocketServer } = require('ws');
const { randomUUID } = require('crypto');

const PORT     = parseInt(process.env.TUNNEL_PORT || '8765', 10);
const HOST     = process.env.TUNNEL_HOST || '0.0.0.0';
// Простой токен для защиты от случайных подключений
const TOKEN    = process.env.TUNNEL_TOKEN || (() => {
    console.warn('[WARN] TUNNEL_TOKEN не задан! Установи в .env для безопасности.');
    return 'changeme';
})();

// Максимальный размер DataChannel сообщения (browser limit ~16KB, используем 8KB)
const CHUNK_SIZE = 8 * 1024;

// Активные сессии: sessionId → { ws, tcpSocket, buffer }
const sessions = new Map();

// ─── WebSocket сервер для signaling ──────────────────────────────────────────
const httpServer = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('VPN WebRTC Tunnel Server');
});

const wss = new WebSocketServer({ server: httpServer });

wss.on('connection', (ws, req) => {
    // Проверка токена (передаётся в query string: ?token=xxx)
    const url = new URL(req.url, `http://${req.headers.host}`);
    if (url.searchParams.get('token') !== TOKEN) {
        ws.close(4001, 'Unauthorized');
        return;
    }

    const sessionId = randomUUID();
    console.log(`[+] Новая сессия: ${sessionId}`);

    sessions.set(sessionId, { ws, tcpSocket: null, targetHost: null, targetPort: null });
    ws.send(JSON.stringify({ type: 'session', id: sessionId }));

    ws.on('message', (data) => handleMessage(sessionId, data));
    ws.on('close', () => closeSession(sessionId));
    ws.on('error', (err) => {
        console.error(`[!] WebSocket error [${sessionId}]:`, err.message);
        closeSession(sessionId);
    });
});

/**
 * Обработка входящих сообщений от браузера.
 * Протокол: JSON-команды + бинарные чанки данных.
 */
function handleMessage(sessionId, data) {
    const session = sessions.get(sessionId);
    if (!session) return;

    // Бинарные данные → пишем в TCP сокет
    if (Buffer.isBuffer(data)) {
        if (session.tcpSocket && !session.tcpSocket.destroyed) {
            session.tcpSocket.write(data);
        }
        return;
    }

    let msg;
    try {
        msg = JSON.parse(data.toString());
    } catch {
        return;
    }

    switch (msg.type) {
        case 'connect':
            // Браузер просит подключиться к хосту:порту
            createTcpConnection(sessionId, msg.host, msg.port);
            break;
        case 'ping':
            session.ws.send(JSON.stringify({ type: 'pong' }));
            break;
        default:
            console.warn(`[?] Неизвестный тип: ${msg.type}`);
    }
}

/**
 * Открываем TCP соединение к целевому хосту.
 * Данные из TCP дробим на чанки ≤ CHUNK_SIZE и отправляем браузеру.
 */
function createTcpConnection(sessionId, host, port) {
    const session = sessions.get(sessionId);
    if (!session) return;

    const tcpSocket = net.createConnection({ host, port }, () => {
        console.log(`[→] ${sessionId} → ${host}:${port}`);
        session.ws.send(JSON.stringify({ type: 'connected', host, port }));
    });

    tcpSocket.on('data', (chunk) => {
        // Дробим большие ответы на чанки (DataChannel limit)
        for (let offset = 0; offset < chunk.length; offset += CHUNK_SIZE) {
            const slice = chunk.slice(offset, offset + CHUNK_SIZE);
            if (session.ws.readyState === 1) { // OPEN
                session.ws.send(slice);
            }
        }
    });

    tcpSocket.on('close', () => {
        if (session.ws.readyState === 1) {
            session.ws.send(JSON.stringify({ type: 'disconnected' }));
        }
    });

    tcpSocket.on('error', (err) => {
        console.error(`[!] TCP error [${sessionId}]:`, err.message);
        if (session.ws.readyState === 1) {
            session.ws.send(JSON.stringify({ type: 'error', message: err.message }));
        }
    });

    session.tcpSocket = tcpSocket;
    session.targetHost = host;
    session.targetPort = port;
}

/** Закрываем сессию и все её соединения. */
function closeSession(sessionId) {
    const session = sessions.get(sessionId);
    if (!session) return;
    if (session.tcpSocket && !session.tcpSocket.destroyed) {
        session.tcpSocket.destroy();
    }
    sessions.delete(sessionId);
    console.log(`[-] Сессия закрыта: ${sessionId}`);
}

// ─── Статистика ───────────────────────────────────────────────────────────────
setInterval(() => {
    if (sessions.size > 0) {
        console.log(`[i] Активных сессий: ${sessions.size}`);
    }
}, 60_000);

// ─── Запуск ───────────────────────────────────────────────────────────────────
httpServer.listen(PORT, HOST, () => {
    console.log(`[✓] WebRTC Tunnel Server запущен на ${HOST}:${PORT}`);
    console.log(`[i] Токен: ${TOKEN === 'changeme' ? '⚠️  changeme (небезопасно!)' : '***' + TOKEN.slice(-4)}`);
    console.log('[i] Открой tunnel-client.html в браузере для подключения');
});

process.on('SIGTERM', () => {
    console.log('[i] Получен SIGTERM, закрываем сессии...');
    sessions.forEach((_, id) => closeSession(id));
    httpServer.close(() => process.exit(0));
});
