import { Request } from 'express';

export interface User {
  id: string;
  username: string;
  password_hash: string;
  public_key: string;
  created_at: string;
}

export interface OfflineMessage {
  id: string;
  sender_id: string;
  recipient_id: string;
  ephemeral_public: string;
  iv: string;
  ciphertext: string;
  created_at: string;
}

export interface AuthRequest extends Request {
  userId?: string;
  username?: string;
}

export type WSPacket =
  | { type: 'auth'; token: string }
  | { type: 'message'; recipientId: string; ephemeralPublic: string; iv: string; ciphertext: string }
  | { type: 'ack'; messageId: string };
