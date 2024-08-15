import { SupabaseClient } from "@supabase/supabase-js";

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

export type ApiKeyMetadata = {
  api_key_reference: string;
  name: string;
  permission: string;
  last_used: string;
  created: string;
  revoked: string;
  total_uses: number;
  success_rate: number;
  total_cost: number;
};

export type AppError = {
  _tag: "DatabaseError" | "UnauthorizedError";
  message: string;
};

export type AuthResult = {
  userId: string;
  supabase: SupabaseClient<any, "public", any>;
};
