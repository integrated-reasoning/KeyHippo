import { SupabaseClient } from "@supabase/supabase-js";

export interface Logger {
  info: (message: string) => void;
  warn: (message: string) => void;
  error: (message: string) => void;
  debug: (message: string) => void;
}

export type ApiKeyResponse = {
  api_key: string;
};

export type ApiKeyRecord = {
  id: string;
  description: string;
  api_key: string;
};

export type ApiKeyInfo = {
  id: string;
  description: string;
};

export interface CompleteApiKeyInfo extends ApiKeyInfo {
  apiKey: string | null;
  status: "success" | "failed";
  error?: string;
}

export interface ApiKeyResult {
  success: boolean;
  api_key?: string;
  error?: string;
  message?: string;
}

export type RotateApiKeyResult = {
  new_api_key: string;
  new_api_key_id: string;
  description?: string;
};

export type ApiKeyMetadata = {
  api_key_id: string;
  name: string;
  permission: string;
  last_used: string;
  created: string;
  revoked: string;
  total_uses: number;
  success_rate: number;
  total_cost: number;
};

export type AppError =
  | { _tag: "DatabaseError"; message: string }
  | { _tag: "UnauthorizedError"; message: string }
  | { _tag: "ValidationError"; message: string }
  | { _tag: "NetworkError"; message: string };

export type AuthResult = {
  userId: string;
  supabase: SupabaseClient<any, "public", any>;
};
