import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { setupTest, TestSetup } from "./testSetup";

let testSetup: TestSetup;

beforeAll(async () => {
  testSetup = await setupTest();
});

const teardown = async () => {
  try {
    const keyInfos = await testSetup.keyHippo.loadApiKeyInfo(testSetup.userId);
    for (const keyInfo of keyInfos) {
      await testSetup.keyHippo.revokeApiKey(testSetup.userId, keyInfo.id);
    }
  } catch (error) {
    console.error("Cleanup failed", error);
  }
};

afterAll(teardown);

describe("KeyHippo Client Tests", () => {
  it("should create an API key", async () => {
    const keyDescription = "Test Key";
    const result = await testSetup.keyHippo.createApiKey(
      testSetup.userId,
      keyDescription,
    );
    expect(result).toHaveProperty("id");
    expect(result).toHaveProperty("description");
    expect(result).toHaveProperty("apiKey");
    expect(result.status).toBe("success");
    expect(result.description).toContain(keyDescription);
  });

  it("should load API key info", async () => {
    const keyInfos = await testSetup.keyHippo.loadApiKeyInfo(testSetup.userId);

    expect(Array.isArray(keyInfos)).toBe(true);
    expect(keyInfos.length).toBeGreaterThan(0);
    expect(keyInfos[0]).toHaveProperty("id");
    expect(keyInfos[0]).toHaveProperty("description");
  });

  it("should get all key metadata", async () => {
    const metadata = await testSetup.keyHippo.getAllKeyMetadata(
      testSetup.userId,
    );

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
    const createdKey = await testSetup.keyHippo.createApiKey(
      testSetup.userId,
      keyDescription,
    );

    const mockRequest = new Request("https://example.com", {
      headers: {
        Authorization: `Bearer ${createdKey.apiKey}`,
      },
    });

    const authResult = await testSetup.keyHippo.authenticate(mockRequest);

    expect(authResult).toHaveProperty("userId");
    expect(authResult).toHaveProperty("supabase");
    expect(authResult.userId).toBe(testSetup.userId);
  });

  it("should revoke an API key", async () => {
    const keyDescription = "Key to be revoked";
    const createdKey = await testSetup.keyHippo.createApiKey(
      testSetup.userId,
      keyDescription,
    );

    await testSetup.keyHippo.revokeApiKey(testSetup.userId, createdKey.id);

    const keyInfos = await testSetup.keyHippo.loadApiKeyInfo(testSetup.userId);
    const revokedKey = keyInfos.find((key) => key.id === createdKey.id);

    expect(revokedKey).toBeUndefined();
  });

  it("should handle errors when creating an invalid API key", async () => {
    await expect(
      testSetup.keyHippo.createApiKey("", "Invalid Key"),
    ).rejects.toThrow("Error creating API key");
  });

  it("should handle errors when getting metadata for non-existent user", async () => {
    await expect(
      testSetup.keyHippo.getAllKeyMetadata("non-existent-user"),
    ).rejects.toThrow("Error getting API key metadata");
  });
});
