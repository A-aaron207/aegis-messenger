import express from 'express';
import http from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import cors from 'cors';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { initDatabase, dbRun, dbGet, dbAll } from './db';
import { User, OfflineMessage, WSPacket } from './types';
import { authenticateJWT, JWT_SECRET } from './middleware/auth';

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });

app.use(cors());
app.use(express.json());

// In-memory registry of online users: userId -> WebSocket
const onlineClients = new Map<string, WebSocket>();

// ==========================================
// 1. REST ENDPOINTS (Authentication & Keys)
// ==========================================

// Register
app.post('/api/auth/register', async (req, res) => {
  const { username, passwordHash, publicKey } = req.body;

  if (!username || !passwordHash || !publicKey) {
    return res.status(400).json({ error: 'Missing username, passwordHash, or publicKey.' });
  }

  try {
    const existing = await dbGet<User>('SELECT * FROM users WHERE username = ?', [username]);
    if (existing) {
      return res.status(409).json({ error: 'Username already taken.' });
    }

    const userId = crypto.randomUUID();
    // Salt and hash the client-side password hash once more on the server for security
    const finalPasswordHash = await bcrypt.hash(passwordHash, 10);

    await dbRun(
      'INSERT INTO users (id, username, password_hash, public_key) VALUES (?, ?, ?, ?)',
      [userId, username, finalPasswordHash, publicKey]
    );

    const token = jwt.sign({ userId, username }, JWT_SECRET, { expiresIn: '30d' });

    res.status(201).json({ userId, token });
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

// Login
app.post('/api/auth/login', async (req, res) => {
  const { username, passwordHash } = req.body;

  if (!username || !passwordHash) {
    return res.status(400).json({ error: 'Missing username or passwordHash.' });
  }

  try {
    const user = await dbGet<User>('SELECT * FROM users WHERE username = ?', [username]);
    if (!user) {
      return res.status(401).json({ error: 'Invalid username or password.' });
    }

    const isValid = await bcrypt.compare(passwordHash, user.password_hash);
    if (!isValid) {
      return res.status(401).json({ error: 'Invalid username or password.' });
    }

    const token = jwt.sign({ userId: user.id, username: user.username }, JWT_SECRET, { expiresIn: '30d' });

    res.status(200).json({ userId: user.id, token });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

// Get public key by username (for adding friends)
app.get('/api/users/:username', authenticateJWT, async (req, res) => {
  const { username } = req.params;

  try {
    const user = await dbGet<User>('SELECT id, username, public_key FROM users WHERE username = ?', [username]);
    if (!user) {
      return res.status(404).json({ error: 'User not found.' });
    }

    res.status(200).json({
      userId: user.id,
      username: user.username,
      publicKey: user.public_key,
    });
  } catch (error) {
    console.error('Fetch public key error:', error);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

// ==========================================
// 2. WEBSOCKET MESSAGING SYSTEM
// ==========================================

// Upgrade HTTP to WS
server.on('upgrade', (request, socket, head) => {
  wss.handleUpgrade(request, socket, head, (ws) => {
    wss.emit('connection', ws, request);
  });
});

wss.on('connection', (ws: WebSocket) => {
  let authenticatedUserId: string | null = null;

  console.log('New connection established.');

  ws.on('message', async (data: string) => {
    try {
      const packet: WSPacket = JSON.parse(data);

      if (packet.type === 'auth') {
        const decoded = jwt.verify(packet.token, JWT_SECRET) as { userId: string; username: string };
        authenticatedUserId = decoded.userId;
        onlineClients.set(authenticatedUserId, ws);
        
        ws.send(JSON.stringify({ type: 'auth_ok' }));
        console.log(`User ${decoded.username} (${decoded.userId}) authenticated via WebSocket.`);

        // Flush offline messages queue
        await flushOfflineMessages(authenticatedUserId, ws);
        return;
      }

      if (!authenticatedUserId) {
        ws.send(JSON.stringify({ type: 'error', message: 'Unauthorized WebSocket. Send auth packet first.' }));
        ws.close();
        return;
      }

      if (packet.type === 'message') {
        const { recipientId, ephemeralPublic, iv, ciphertext } = packet;

        // Check if recipient is online
        const recipientSocket = onlineClients.get(recipientId);
        const msgId = crypto.randomUUID();

        // Get sender metadata
        const sender = await dbGet<User>('SELECT username FROM users WHERE id = ?', [authenticatedUserId]);
        const senderUsername = sender?.username || 'Unknown';

        const forwardPayload = {
          type: 'message',
          id: msgId,
          senderId: authenticatedUserId,
          senderUsername,
          ephemeralPublic,
          iv,
          ciphertext,
          timestamp: new Date().toISOString(),
        };

        if (recipientSocket && recipientSocket.readyState === WebSocket.OPEN) {
          // Deliver instantly
          recipientSocket.send(JSON.stringify(forwardPayload));
          
          // Respond back to sender with dispatch acknowledgement
          ws.send(JSON.stringify({ type: 'dispatch_ok', messageId: msgId, recipientId }));
          console.log(`Delivered real-time message from ${senderUsername} to user ID ${recipientId}`);
        } else {
          // Enqueue message offline
          await dbRun(
            'INSERT INTO offline_messages (id, sender_id, recipient_id, ephemeral_public, iv, ciphertext) VALUES (?, ?, ?, ?, ?, ?)',
            [msgId, authenticatedUserId, recipientId, ephemeralPublic, iv, ciphertext]
          );
          ws.send(JSON.stringify({ type: 'dispatch_queued', messageId: msgId, recipientId }));
          console.log(`Enqueued offline message from ${senderUsername} to user ID ${recipientId}`);
        }
      }

      if (packet.type === 'ack') {
        // Delete message from offline store once delivered & acknowledged by client
        await dbRun('DELETE FROM offline_messages WHERE id = ?', [packet.messageId]);
        console.log(`Offline message ${packet.messageId} successfully deleted after client acknowledgement.`);
      }
    } catch (err: any) {
      console.error('WebSocket message parsing error:', err.message);
      ws.send(JSON.stringify({ type: 'error', message: 'Malformed payload or token validation failed.' }));
    }
  });

  ws.on('close', () => {
    if (authenticatedUserId) {
      onlineClients.delete(authenticatedUserId);
      console.log(`User ID ${authenticatedUserId} disconnected.`);
    }
  });
});

async function flushOfflineMessages(userId: string, ws: WebSocket) {
  try {
    const pendingMessages = await dbAll<OfflineMessage>(
      `SELECT om.*, u.username as sender_username 
       FROM offline_messages om 
       JOIN users u ON om.sender_id = u.id 
       WHERE om.recipient_id = ? 
       ORDER BY om.created_at ASC`,
      [userId]
    );

    if (pendingMessages.length === 0) return;

    console.log(`Flushing ${pendingMessages.length} offline messages to user ID ${userId}`);

    for (const msg of pendingMessages) {
      ws.send(
        JSON.stringify({
          type: 'message',
          id: msg.id,
          senderId: msg.sender_id,
          senderUsername: (msg as any).sender_username || 'Unknown',
          ephemeralPublic: msg.ephemeral_public,
          iv: msg.iv,
          ciphertext: msg.ciphertext,
          timestamp: msg.created_at,
        })
      );
    }
  } catch (error) {
    console.error('Failed to flush offline messages:', error);
  }
}

// Start Server
const PORT = process.env.PORT || 3000;
initDatabase().then(() => {
  server.listen(PORT, () => {
    console.log(`Aegis secure backend is running at http://localhost:${PORT}`);
  });
});
