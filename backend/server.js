const express = require('express');
const cors = require('cors');
const http = require('http');
const { WebSocketServer } = require('ws');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// In-memory registries (Strict Zero-Knowledge Server Rule)
const userKeys = new Map(); // username -> base64_x25519_public_key
const offlineQueues = new Map(); // username -> list of E2EE message envelopes
const onlineSockets = new Map(); // username -> WebSocket
const fileMetadata = new Map(); // file_id -> { fileId, expiresAt, size }

// Persistent User Verification Registry (Reserved for future Beta v2 activation)
const VERIFICATION_FILE = path.join(__dirname, 'verification.json');
const userVerification = new Map(); // username -> { verified, verification_level, verification_metadata }

function loadVerificationRegistry() {
  if (fs.existsSync(VERIFICATION_FILE)) {
    try {
      const data = JSON.parse(fs.readFileSync(VERIFICATION_FILE, 'utf8'));
      for (const key in data) {
        userVerification.set(key, data[key]);
      }
      console.log(`[VERIFICATION] Loaded ${Object.keys(data).length} verification records from disk`);
    } catch (err) {
      console.error('[VERIFICATION] Failed to load verification file:', err.message);
    }
  }
}

function saveVerificationRegistry() {
  try {
    const obj = {};
    for (const [username, val] of userVerification.entries()) {
      obj[username] = val;
    }
    fs.writeFileSync(VERIFICATION_FILE, JSON.stringify(obj, null, 2), 'utf8');
  } catch (err) {
    console.error('[VERIFICATION] Failed to save verification registry:', err.message);
  }
}

const getVerificationData = (username) => {
  const norm = username.trim().toLowerCase();
  return userVerification.get(norm) || {
    verified: false,
    verification_level: 0,
    verification_metadata: null
  };
};

function getLevenshteinDistance(a, b) {
  const matrix = [];
  for (let i = 0; i <= b.length; i++) matrix[i] = [i];
  for (let j = 0; j <= a.length; j++) matrix[0][j] = j;

  for (let i = 1; i <= b.length; i++) {
    for (let j = 1; j <= a.length; j++) {
      if (b.charAt(i - 1) === a.charAt(j - 1)) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = Math.min(
          matrix[i - 1][j - 1] + 1, // substitution
          matrix[i][j - 1] + 1,     // insertion
          matrix[i - 1][j] + 1      // deletion
        );
      }
    }
  }
  return matrix[b.length][a.length];
}

// Ensure uploads directory exists for encrypted binary envelopes
const UPLOADS_DIR = path.join(__dirname, 'uploads');
if (!fs.existsSync(UPLOADS_DIR)) {
  fs.mkdirSync(UPLOADS_DIR);
}
loadVerificationRegistry();

// ==========================================
// 1. REST APIS
// ==========================================

// Register username and X25519 public key
app.post('/api/register', (req, res) => {
  const { username, publicKey } = req.body;
  if (!username || !publicKey) {
    return res.status(400).json({ error: 'Missing username or publicKey.' });
  }

  const normalizedUser = username.trim().toLowerCase();
  userKeys.set(normalizedUser, publicKey);
  console.log(`Registered user: ${normalizedUser} with public key: ${publicKey}`);
  return res.status(200).json({ success: true, username: normalizedUser });
});

// Fetch target user's public key for ECDH key agreement
app.get('/api/user/:username', (req, res) => {
  const normalizedUser = req.params.username.trim().toLowerCase();
  const publicKey = userKeys.get(normalizedUser);
  if (!publicKey) {
    return res.status(404).json({ error: 'User not found.' });
  }
  const isOnline = onlineSockets.has(normalizedUser);
  const vData = getVerificationData(normalizedUser);
  return res.status(200).json({ 
    username: normalizedUser, 
    publicKey, 
    status: isOnline ? 'online' : 'offline',
    verified: vData.verified,
    verification_level: vData.verification_level,
    verification_metadata: vData.verification_metadata
  });
});

// Shared Search Handler with Case-Insensitive Fuzzy Matching and Debug Logging
const handleUserSearch = (req, res) => {
  const query = (req.query.q || '').trim().toLowerCase();
  console.log(`[DEBUG] Incoming search query: "${query}"`);

  const results = [];
  
  if (query) {
    for (const [username, publicKey] of userKeys.entries()) {
      const uNameLower = username.toLowerCase();
      const qLower = query.toLowerCase();
      
      const contains = uNameLower.includes(qLower) || qLower.includes(uNameLower);
      
      let distance = 999;
      if (!contains && Math.abs(uNameLower.length - qLower.length) <= 3) {
        distance = getLevenshteinDistance(uNameLower, qLower);
      }
      
      if (contains || distance <= 2) {
        const isOnline = onlineSockets.has(username);
        const fingerprint = publicKey.substring(0, 16) + "...";
        const vData = getVerificationData(username);
        
        results.push({
          user_id: username, // Primary immutable binder
          username: username,
          fingerprint: fingerprint,
          publicKey: publicKey,
          status: isOnline ? 'online' : 'offline',
          verified: vData.verified,
          verification_level: vData.verification_level,
          verification_metadata: vData.verification_metadata
        });
      }

      if (results.length >= 100) break; // Limit candidate pool to 100 for scalability
    }
  }

  console.log(`[DEBUG] DB result count: ${results.length}`);
  const payload = { users: results };
  const payloadSize = Buffer.byteLength(JSON.stringify(payload));
  console.log(`[DEBUG] Returned payload size: ${payloadSize} bytes`);

  return res.status(200).json(payload);
};

// Bind to both standard and custom paths for absolute compatibility
app.get('/users/search', handleUserSearch);
app.get('/api/users/search', handleUserSearch);

// List all registered users to populate the chat selection screen
app.get('/api/users', (req, res) => {
  const list = Array.from(userKeys.keys());
  return res.status(200).json({ users: list });
});

// ==========================================
// INTERNAL / ADMIN VERIFICATION APIS (BETA RESERVED)
// ==========================================

const ADMIN_SECRET = process.env.ADMIN_SECRET || 'aegis-admin-secret-token-v2-key';

const authorizeAdmin = (req, res, next) => {
  const secret = req.headers['x-admin-secret'];
  if (secret !== ADMIN_SECRET) {
    return res.status(403).json({ error: 'Forbidden: Invalid or missing admin secret.' });
  }
  next();
};

// POST /admin/verify-user
app.post('/admin/verify-user', authorizeAdmin, (req, res) => {
  const { username, verificationLevel, verificationMetadata } = req.body;
  if (!username) {
    return res.status(400).json({ error: 'Missing username parameter.' });
  }
  
  const norm = username.trim().toLowerCase();
  if (!userKeys.has(norm)) {
    return res.status(404).json({ error: 'User does not exist.' });
  }

  const level = parseInt(verificationLevel, 10);
  const metadata = verificationMetadata || null;

  userVerification.set(norm, {
    verified: true,
    verification_level: isNaN(level) ? 1 : level,
    verification_metadata: metadata
  });

  saveVerificationRegistry();
  console.log(`[ADMIN] User ${norm} successfully verified at level ${level}`);
  return res.status(200).json({ 
    success: true, 
    username: norm, 
    verified: true,
    verification_level: isNaN(level) ? 1 : level,
    verification_metadata: metadata
  });
});

// POST /admin/unverify-user
app.post('/admin/unverify-user', authorizeAdmin, (req, res) => {
  const { username } = req.body;
  if (!username) {
    return res.status(400).json({ error: 'Missing username parameter.' });
  }

  const norm = username.trim().toLowerCase();
  if (!userKeys.has(norm)) {
    return res.status(404).json({ error: 'User does not exist.' });
  }

  userVerification.delete(norm);
  saveVerificationRegistry();
  console.log(`[ADMIN] User ${norm} unverified successfully`);
  return res.status(200).json({ success: true, username: norm, verified: false });
});

// ==========================================
// PWA SECURE FILE MESSAGING ENDPOINTS (ZERO-KNOWLEDGE STORAGE)
// ==========================================

// Upload Encrypted Binary Envelope (Blob)
// Employs a custom express.raw parser config up to 25MB
app.post('/api/file/upload', express.raw({ type: '*/*', limit: '25mb' }), (req, res) => {
  if (!req.body || req.body.length === 0) {
    return res.status(400).json({ error: 'Payload must be a non-empty binary envelope.' });
  }

  const fileId = crypto.randomUUID();
  const filePath = path.join(UPLOADS_DIR, fileId);

  // Direct asynchronous disk flush (preserves server RAM)
  fs.writeFile(filePath, req.body, (err) => {
    if (err) {
      console.error('[FILE UPLOAD ERROR]', err.message);
      return res.status(500).json({ error: 'System error writing E2EE payload to storage.' });
    }

    const expiresAt = Date.now() + 24 * 60 * 60 * 1000; // 24h TTL
    fileMetadata.set(fileId, {
      fileId,
      expiresAt,
      size: req.body.length
    });

    console.log(`[FILE STORAGE] Enqueued E2EE blind payload ${fileId} (${req.body.length} bytes), TTL expires in 24h`);
    return res.status(200).json({ success: true, fileId });
  });
});

// Download Encrypted Binary Envelope
app.get('/api/file/:file_id', (req, res) => {
  const fileId = req.params.file_id;
  const filePath = path.join(UPLOADS_DIR, fileId);

  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'Secure envelope not found, invalid, or expired.' });
  }

  console.log(`[FILE RETRIEVAL] Streaming E2EE envelope payload ${fileId} to recipient`);
  res.sendFile(filePath);
});

// Hourly Cron-style loop to evict expired E2EE envelopes
setInterval(() => {
  const now = Date.now();
  for (const [fileId, meta] of fileMetadata.entries()) {
    if (now > meta.expiresAt) {
      const filePath = path.join(UPLOADS_DIR, fileId);
      if (fs.existsSync(filePath)) {
        try {
          fs.unlinkSync(filePath);
          console.log(`[FILE EVICTION] Expired E2EE upload ${fileId} successfully evicted`);
        } catch (e) {
          console.error(`[FILE EVICTION ERROR] Failed to delete ${fileId}:`, e.message);
        }
      }
      fileMetadata.delete(fileId);
    }
  }
}, 3600000); // 1 hour interval

// ==========================================
// 2. WEBSOCKET MESSAGING SYSTEM
// ==========================================

const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (request, socket, head) => {
  wss.handleUpgrade(request, socket, head, (ws) => {
    wss.emit('connection', ws, request);
  });
});

wss.on('connection', (ws) => {
  let authenticatedUser = null;

  ws.on('message', (message) => {
    try {
      const packet = JSON.parse(message);

      if (packet.type === 'ping') {
        ws.send(JSON.stringify({ type: 'pong' }));
        return;
      }

      if (packet.type === 'auth') {
        const username = packet.username.trim().toLowerCase();
        authenticatedUser = username;
        onlineSockets.set(username, ws);
        console.log(`WebSocket authenticated: ${username}`);
        ws.send(JSON.stringify({ type: 'auth_ok' }));

        // Flush offline message queue
        const queue = offlineQueues.get(username) || [];
        if (queue.length > 0) {
          console.log(`Flushing ${queue.length} offline messages to ${username}`);
          queue.forEach((msg) => ws.send(JSON.stringify(msg)));
          offlineQueues.delete(username);
        }
        return;
      }

      if (!authenticatedUser) {
        ws.send(JSON.stringify({ type: 'error', message: 'Send auth packet first.' }));
        return;
      }

      if (packet.type === 'edit' || packet.type === 'delete' || packet.type === 'reaction' || packet.type === 'ack' ||
          packet.type === 'call-offer' || packet.type === 'call-answer' || packet.type === 'call-candidate' || packet.type === 'call-hangup') {
        const { recipient } = packet;
        const normalizedRecipient = recipient.trim().toLowerCase();
        const recipientSocket = onlineSockets.get(normalizedRecipient);
        if (recipientSocket && recipientSocket.readyState === 1) {
          packet.sender = authenticatedUser; // Overwrite sender for safety
          recipientSocket.send(JSON.stringify(packet));
        }
        return;
      }

      if (packet.type === 'typing') {
        const { recipient, isTyping } = packet;
        const normalizedRecipient = recipient.trim().toLowerCase();
        const recipientSocket = onlineSockets.get(normalizedRecipient);
        if (recipientSocket && recipientSocket.readyState === 1) {
          recipientSocket.send(JSON.stringify({
            type: 'typing',
            sender: authenticatedUser,
            isTyping
          }));
        }
        return;
      }

      if (packet.type === 'message') {
        const { recipient, sender, iv, ciphertext, replyTo, isFile } = packet;
        const normalizedRecipient = recipient.trim().toLowerCase();

        const envelope = {
          type: 'message',
          sender: authenticatedUser,
          iv,
          ciphertext,
          timestamp: new Date().toISOString(),
          replyTo,
          isFile
        };

        const recipientSocket = onlineSockets.get(normalizedRecipient);
        if (recipientSocket && recipientSocket.readyState === 1) {
          // Direct real-time relay (Zero-Knowledge)
          recipientSocket.send(JSON.stringify(envelope));
          console.log(`Relayed live envelope from ${authenticatedUser} to ${normalizedRecipient}`);
        } else {
          // Store in blind offline queue
          if (!offlineQueues.has(normalizedRecipient)) {
            offlineQueues.set(normalizedRecipient, []);
          }
          offlineQueues.get(normalizedRecipient).push(envelope);
          console.log(`Enqueued offline envelope from ${authenticatedUser} to ${normalizedRecipient}`);
        }
      }
    } catch (e) {
      console.error('Error handling websocket payload:', e.message);
    }
  });

  ws.on('close', () => {
    if (authenticatedUser) {
      onlineSockets.delete(authenticatedUser);
      console.log(`WebSocket disconnected: ${authenticatedUser}`);
    }
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Aegis Blind Server is running at http://localhost:${PORT}`);
});
