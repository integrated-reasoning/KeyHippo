import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { KeyHippo } from "../src/index";
import { setupTest, TestSetup } from "./testSetup";
import { createClient } from "@supabase/supabase-js";

let testSetup: TestSetup;

beforeAll(async () => {
  testSetup = await setupTest();
});

const teardown = async () => {
  try {
    const keyInfos = await testSetup.keyHippo.loadApiKeySummaries();
    for (const keyInfo of keyInfos) {
      await testSetup.keyHippo.revokeApiKey(keyInfo.id);
    }
  } catch (error) {
    console.error("Cleanup failed", error);
  }
};

afterAll(teardown);

describe("KeyHippo Client Tests", () => {
  it("should create an API key", async () => {
    const keyDescription = "Test Key";
    const result = await testSetup.keyHippo.createApiKey(keyDescription);
    expect(result).toHaveProperty("id");
    expect(result).toHaveProperty("description");
    expect(result).toHaveProperty("apiKey");
    expect(result.description).toEqual(keyDescription);
  });

  it("should load API key summaries", async () => {
    const keyDescription = "Summary Test Key";
    await testSetup.keyHippo.createApiKey(keyDescription);

    const keySummaries = await testSetup.keyHippo.loadApiKeySummaries();

    expect(Array.isArray(keySummaries)).toBe(true);
    expect(keySummaries.length).toBeGreaterThan(0);
    expect(keySummaries[0]).toHaveProperty("id");
    expect(keySummaries[0]).toHaveProperty("description");
    expect(keySummaries.some((key) => key.description === keyDescription)).toBe(
      true,
    );
  });

  it("should authenticate with an API key", async () => {
    const keyDescription = "Auth Test Key";
    const createdKeyInfo =
      await testSetup.keyHippo.createApiKey(keyDescription);
    const createdKey = createdKeyInfo.apiKey;
    const mockHeaders = new Headers({
      Authorization: `Bearer ${createdKey}`,
    });
    const { userId, supabase } =
      await testSetup.keyHippo.authenticate(mockHeaders);

    expect(userId).toBe(testSetup.userId);
    expect(supabase).toBeDefined();

    const { data: obtainedUserId, error: _ } = await supabase
      .schema("keyhippo")
      .rpc("verify_api_key", { api_key: createdKey });

    expect(obtainedUserId).toBe(userId);
  });

  it("should revoke an API key", async () => {
    const keyDescription = "Key to be revoked";
    const createdKeyInfo =
      await testSetup.keyHippo.createApiKey(keyDescription);

    await testSetup.keyHippo.revokeApiKey(createdKeyInfo.id);

    const keySummaries = await testSetup.keyHippo.loadApiKeySummaries();
    const revokedKey = keySummaries.find((key) => key.id === createdKeyInfo.id);

    expect(revokedKey).toBeUndefined();
  });

  it("should handle errors when creating an invalid API key", async () => {
    await expect(
      testSetup.keyHippo.createApiKey("Invalid Key Description !@#$%^&*()"),
    ).rejects.toThrow("[KeyHippo] Invalid key description");
  });

  it("should rotate an API key", async () => {
    const keyDescription = "Key to Rotate";
    const createdKeyInfo =
      await testSetup.keyHippo.createApiKey(keyDescription);

    const rotatedKeyInfo = await testSetup.keyHippo.rotateApiKey(
      createdKeyInfo.id,
    );

    expect(rotatedKeyInfo).toHaveProperty("apiKey");
    expect(rotatedKeyInfo).toHaveProperty("id");
    expect(rotatedKeyInfo.status).toBe("success");
    expect(rotatedKeyInfo.id).not.toBe(createdKeyInfo.id);

    // Verify the old API key is revoked
    const keySummaries = await testSetup.keyHippo.loadApiKeySummaries();
    const oldKeyExists = keySummaries.some(
      (key) => key.id === createdKeyInfo.id,
    );
    expect(oldKeyExists).toBe(false);

    // Verify the new API key works
    const mockHeaders = new Headers({
      Authorization: `Bearer ${rotatedKeyInfo.apiKey}`,
    });
    const { userId, supabase } =
      await testSetup.keyHippo.authenticate(mockHeaders);

    expect(userId).toBe(testSetup.userId);
    expect(supabase).toBeDefined();
  });

  it("should handle errors when rotating a non-existent API key", async () => {
    await expect(
      testSetup.keyHippo.rotateApiKey("invalid-api-key-id"),
    ).rejects.toThrow("Failed to rotate API key");
  });

  it("should not rotate an API key owned by another user", async () => {
    // Create another user and API key with a separate Supabase client
    const supabase = createClient(
      process.env.SUPABASE_URL!,
      process.env.SUPABASE_ANON_KEY!,
    );
    const { data: newUserData, error: signInError } =
      await supabase.auth.signInAnonymously();

    if (signInError || !newUserData.user) {
      throw new Error(`Error signing in as new user: ${signInError?.message}`);
    }

    const newUserKeyHippo = new KeyHippo(supabase, console);
    const newUserKeyInfo = await newUserKeyHippo.createApiKey("Other Key");

    // Use the original user's KeyHippo client
    const originalUserKeyHippo = testSetup.keyHippo;

    // Attempt to rotate the new user's API key as the original user
    await expect(
      originalUserKeyHippo.rotateApiKey(newUserKeyInfo.id),
    ).rejects.toThrow("Failed to rotate API key");

    // Clean up
    await newUserKeyHippo.revokeApiKey(newUserKeyInfo.id);
  });

  it("should retrieve the correct API key summary after rotation", async () => {
    const keyDescription = "Key to Rotate";

    // Create an API key
    const createdKeyInfo =
      await testSetup.keyHippo.createApiKey(keyDescription);

    // Rotate the API key
    const rotatedKeyInfo = await testSetup.keyHippo.rotateApiKey(
      createdKeyInfo.id,
    );

    // Verify that the old key is no longer retrievable
    const keySummaries = await testSetup.keyHippo.loadApiKeySummaries();
    const oldKeyExists = keySummaries.some(
      (key) => key.id === createdKeyInfo.id,
    );
    expect(oldKeyExists).toBe(false);

    // Verify that the new key info is present
    const newKeyExists = keySummaries.some(
      (key) => key.id === rotatedKeyInfo.id,
    );
    expect(newKeyExists).toBe(true);

    // Verify that the description is maintained
    const newKeySummary = keySummaries.find(
      (key) => key.id === rotatedKeyInfo.id,
    );
    expect(newKeySummary?.description).toBe(keyDescription);
  });

  it("should handle creating an API key with a duplicate description", async () => {
    const keyDescription = "Duplicate Key Description";

    // Create first API key
    const firstKey = await testSetup.keyHippo.createApiKey(keyDescription);
    expect(firstKey).toHaveProperty("id");

    // Create second API key with the same description
    const secondKey = await testSetup.keyHippo.createApiKey(keyDescription);
    expect(secondKey).toHaveProperty("id");
    expect(secondKey.id).not.toBe(firstKey.id); // Ensure the IDs are different
  });

  it("should not authenticate with a revoked API key", async () => {
    const keyDescription = "Revokable Key";
    // Create and revoke the API key
    const keyInfo = await testSetup.keyHippo.createApiKey(keyDescription);
    await testSetup.keyHippo.revokeApiKey(keyInfo.id);

    // Attempt to authenticate using the revoked key
    const mockHeaders = new Headers({
      Authorization: `Bearer ${keyInfo.apiKey}`,
    });
    await expect(testSetup.keyHippo.authenticate(mockHeaders)).rejects.toThrow(
      "API key does not correspond to any user.",
    );
  });

  it("should not return revoked API keys in key summaries", async () => {
    const keyDescription = "Key to be Revoked";

    // Create an API key and then revoke it
    const createdKeyInfo =
      await testSetup.keyHippo.createApiKey(keyDescription);
    await testSetup.keyHippo.revokeApiKey(createdKeyInfo.id);

    // Load API key summaries and ensure revoked key is not present
    const keySummaries = await testSetup.keyHippo.loadApiKeySummaries();
    const revokedKey = keySummaries.find((key) => key.id === createdKeyInfo.id);

    expect(revokedKey).toBeUndefined();
  });

  it("should prevent SQL injection when creating an API key", async () => {
    const validDescription = "Valid Test Key";
    const attackDescription =
      "Attack Key'; UPDATE keyhippo.api_key_metadata SET description = 'Attacked';--";

    // Create the first valid API key
    const validKeyInfo =
      await testSetup.keyHippo.createApiKey(validDescription);

    expect(validKeyInfo).toHaveProperty("id");
    expect(validKeyInfo.description).toEqual(validDescription);

    // Attempt to create the second API key (target for the SQL injection attack)
    await expect(
      testSetup.keyHippo.createApiKey(attackDescription),
    ).rejects.toThrow("[KeyHippo] Invalid key description");

    // Load the API key summaries and verify the malicious query didn't succeed
    const keySummaries = await testSetup.keyHippo.loadApiKeySummaries();

    // Ensure the valid key remains intact
    const validKey = keySummaries.find(
      (key) => key.description === validDescription,
    );
    expect(validKey).toBeDefined();
    expect(validKey!.description).toEqual(validDescription);

    // Ensure the attack key was not created
    const attackedKey = keySummaries.find(
      (key) => key.description === attackDescription,
    );
    expect(attackedKey).toBeUndefined();

    // Additional verification: Ensure the total number of keys remains unchanged (should be at least 1)
    expect(keySummaries.length).toBeGreaterThanOrEqual(1);
  });
});
