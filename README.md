# Aegis — Privacy-First Encrypted Messaging MVP

Aegis is an end-to-end encrypted (E2EE) messaging application designed for absolute privacy and zero trust. The backend acts as a blind delivery queue and registration service; it never sees plaintext message contents, social graphs, or private key materials.

---

## 🛠️ Technology Stack

* **Frontend**: Flutter (Cross-platform: Android, iOS, Web, macOS, Windows, Linux)
* **Backend**: Node.js + Express + WebSockets (`ws` library)
* **Database**: SQLite3 (Promise-wrapped local storage file)
* **Encryption**: 
  * **X25519** (Diffie-Hellman Key Exchange)
  * **HKDF-SHA256** (Symmetric Key Derivation)
  * **AES-256-GCM** (Authenticated Message Encryption)

---

## 🚀 Getting Started Locally

Follow these quick steps to boot up your local Aegis secure network.

### Prerequisites
* [Node.js](https://nodejs.org/) (version 18 or higher)
* [Flutter SDK](https://docs.flutter.dev/get-started/install)

---

### 1. Backend Server Setup

Navigate to the `backend` directory, install packages, and launch the server:

```bash
cd backend
npm install
npm run dev
```

The secure server will initialize its local SQLite database and spin up at:
* **REST APIs**: `http://localhost:3000`
* **WebSocket**: `ws://localhost:3000`

---

### 2. Frontend Client Setup

Navigate to the `frontend` directory, pull down the packages, and run the client:

```bash
cd frontend
flutter pub get
flutter run
```

*Note: For Android emulators trying to access the host's localhost, the loopback IP is mapped to `http://10.0.2.2:3000` inside `lib/main.dart`.*

---

## 🧪 Testing the E2EE Mechanics

To fully test Aegis's real-time and offline capabilities, run two client instances simultaneously (e.g., one on your mobile emulator and one in Chrome web):

### 1. Register Alice & Bob
* Open Client A, register a user named `alice` with password `password123`.
* Open Client B, register a user named `bob` with password `password123`.
* *(During registration, their device generates a unique X25519 identity keypair, saves the private key securely in their local device secure vault, and registers the public key on the backend).*

### 2. Connect as Friends
* On Bob's device, navigate to the **Add Friends** screen and view the QR code.
* On Alice's device, go to **Add Friends** -> **Enter Invite**, type `bob`, and click **Lookup & Add Friend** (or paste Bob's QR json payload in the Simulator QR scanner tool to bypass camera requirements).
* Alice has now saved Bob's username and public identity key locally. Repeat the process in reverse so Bob adds Alice.

### 3. Real-Time Chat
* Open the chat thread between Alice and Bob on both screens.
* Send messages. They are encrypted client-side using a derived AES-256-GCM key from an ephemeral ECDH exchange, and dispatched over the WebSocket tunnel.
* Observe instant receipt, local decryption, and reactive UI updating.

### 4. Offline Message Queuing
* Close Client B (Bob) so he is offline.
* On Client A (Alice), send Bob two messages: `"Are you there?"` and `"This is an offline test."`.
* Alice's client notices Bob is offline and the backend automatically enqueues these encrypted envelopes into the SQLite `offline_messages` queue.
* Open Client B (Bob). Immediately upon connecting and authenticating, the server flushes the pending messages down the WebSocket. Bob's client automatically decrypts them, saves them, and notifies the user!

---

## ☁️ Zero-Cost Cloud Deployment

Deploy the Aegis ecosystem completely for free using these standard developer services:

### 1. Deploying the Backend (Render.com)
1. Commit the `backend` folder to a public or private GitHub repository.
2. Log in to [Render](https://render.com/) and create a new **Web Service**.
3. Link your GitHub repository.
4. Set the following build configs:
   * **Runtime**: `Node`
   * **Build Command**: `npm install && npm run build`
   * **Start Command**: `npm start`
5. Click **Add Environment Variable**:
   * `JWT_SECRET` = `a_very_long_random_secure_secret_keyphrase`
6. Click **Deploy**. Render will provide a free public URL (e.g. `https://aegis-backend.onrender.com`).
7. Update the `baseUrl` in Flutter's `lib/main.dart` to your new URL (with HTTP for API, and WS for WebSocket).

### 2. Host the Flutter Web Client (Netlify / Vercel / GitHub Pages)
To quickly share or run the app on the web:
1. Build the Flutter web application:
   ```bash
   flutter build web
   ```
2. Navigate to `build/web`.
3. Drop this folder directly into [Netlify Drop](https://app.netlify.com/drop) or configure a git deployment via Vercel pointing to the web folder for free instant hosting!
