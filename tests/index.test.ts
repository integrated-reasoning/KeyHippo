import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { KeyHippo } from "../src/index";
import { createClient, SupabaseClient } from "@supabase/supabase-js";

let keyHippo: KeyHippo;
let userId: string;
let supabase: SupabaseClient;

beforeAll(async () => {
  supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_ANON_KEY!,
  );
  const { data, error } = await supabase.auth.signInAnonymously();
  console.log(data, error);
  keyHippo = new KeyHippo(supabase, console);
  userId = data.user!.id;
});

afterAll(async () => {
  // Clean up: revoke all keys created during tests
  const keyInfos = await keyHippo.loadApiKeyInfo(userId);
  for (const keyInfo of keyInfos) {
    await keyHippo.revokeApiKey(userId, keyInfo.id);
  }
});

describe("KeyHippo Integration Tests", () => {
  it("should create an API key", async () => {
    const keyDescription = "Test Key";
    const result = await keyHippo.createApiKey(userId, keyDescription);
    expect(result).toHaveProperty("id");
    expect(result).toHaveProperty("description");
    expect(result).toHaveProperty("apiKey");
    expect(result.status).toBe("success");
    expect(result.description).toContain(keyDescription);
  });

  it("should load API key info", async () => {
    const keyInfos = await keyHippo.loadApiKeyInfo(userId);

    expect(Array.isArray(keyInfos)).toBe(true);
    expect(keyInfos.length).toBeGreaterThan(0);
    expect(keyInfos[0]).toHaveProperty("id");
    expect(keyInfos[0]).toHaveProperty("description");
  });

  it("should get all key metadata", async () => {
    const metadata = await keyHippo.getAllKeyMetadata(userId);

    expect(Array.isArray(metadata)).toBe(true);
    expect(metadata.length).toBeGreaterThan(0);
    expect(metadata[0]).toHaveProperty("api_key_reference");
    expect(metadata[0]).toHaveProperty("name");
    expect(metadata[0]).toHaveProperty("permission");
    expect(metadata[0]).toHaveProperty("last_used");
    expect(metadata[0]).toHaveProperty("created");
    expect(metadata[0]).toHaveProperty("revoked");
    expect(metadata[0]).toHaveProperty("total_uses");
    expect(metadata[0]).toHaveProperty("success_rate");
    expect(metadata[0]).toHaveProperty("total_cost");
  });

  it("should authenticate with an API key", async () => {
    const keyDescription = "Auth Test Key";
    const createdKey = await keyHippo.createApiKey(userId, keyDescription);

    const mockRequest = new Request("https://example.com", {
      headers: {
        Authorization: `Bearer ${createdKey.apiKey}`,
      },
    });

    const authResult = await keyHippo.authenticate(mockRequest);

    expect(authResult).toHaveProperty("userId");
    expect(authResult).toHaveProperty("supabase");
    expect(authResult.userId).toBe(userId);
  });

  it("should revoke an API key", async () => {
    const keyDescription = "Key to be revoked";
    const createdKey = await keyHippo.createApiKey(userId, keyDescription);

    await keyHippo.revokeApiKey(userId, createdKey.id);

    const keyInfos = await keyHippo.loadApiKeyInfo(userId);
    const revokedKey = keyInfos.find((key) => key.id === createdKey.id);

    expect(revokedKey).toBeUndefined();
  });

  it("should handle errors when creating an invalid API key", async () => {
    await expect(keyHippo.createApiKey("", "Invalid Key")).rejects.toThrow(
      "Error creating API key",
    );
  });

  it("should handle errors when getting metadata for non-existent user", async () => {
    await expect(
      keyHippo.getAllKeyMetadata("non-existent-user"),
    ).rejects.toThrow("Error getting API key metadata");
  });
});
