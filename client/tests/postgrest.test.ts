import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { v4 as uuidv4 } from "uuid";
import { setupTest, TestSetup } from "./testSetup";

let testSetup: TestSetup;
let testAccountId: string;
let apiKey: string;
let apiKeyId: string;

const headers = () => ({
  apikey: process.env.SUPABASE_ANON_KEY!,
  Authorization: `Bearer ${process.env.SUPABASE_ANON_KEY!}`,
  "x-api-key": apiKey,
});

const fetchData = async (
  url: string,
  options: RequestInit = {},
  additionalHeaders: Record<string, string> = {},
) => {
  const response = await fetch(url, {
    ...options,
    headers: { ...headers(), ...additionalHeaders, ...options.headers },
  });
  const responseBody = await response.text();
  const data = responseBody ? JSON.parse(responseBody) : null;
  if (!response.ok) {
    console.error("Error Response Body:", data);
    throw new Error(`Error: ${response.statusText}`);
  }
  return data;
};

beforeAll(async () => {
  testSetup = await setupTest();

  const keyDescription = "Test Key for x-api-key";
  const result = await testSetup.keyHippo.createApiKey(keyDescription);
  apiKey = result.apiKey!;
  apiKeyId = result.id;

  const uniqueEmail = `testuser+${uuidv4()}@example.com`;

  const responseBody = await fetchData(
    `${process.env.SUPABASE_URL}/rest/v1/test_accounts`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Prefer: "return=representation",
      },
      body: JSON.stringify({
        user_id: testSetup.userId,
        name: "Test User",
        email: uniqueEmail,
      }),
    },
  );

  testAccountId = responseBody[0].id;
});

afterAll(async () => {
  try {
    await testSetup.keyHippo.revokeApiKey(apiKeyId);

    await fetchData(
      `${process.env.SUPABASE_URL}/rest/v1/test_accounts?user_id=eq.${testSetup.userId}`,
      { method: "DELETE" },
    );
  } catch (error) {
    console.error("Cleanup failed", error);
  }
});

describe("PostgREST Integration Tests", () => {
  const testColumns = ["id", "user_id", "name", "email", "created_at"];

  testColumns.forEach((column) => {
    it(`should read the '${column}' column of the test account`, async () => {
      const data = await fetchData(
        `${process.env.SUPABASE_URL}/rest/v1/test_accounts?select=${column}`,
        { method: "GET" },
      );

      expect(Array.isArray(data)).toBe(true);
      expect(data.length).toBeGreaterThan(0);
      expect(data[0]).toHaveProperty(column);
    });
  });

  it("should read all columns of the test account", async () => {
    const data = await fetchData(
      `${process.env.SUPABASE_URL}/rest/v1/test_accounts?select=*`,
      { method: "GET" },
    );

    expect(Array.isArray(data)).toBe(true);
    expect(data.length).toBeGreaterThan(0);
    testColumns.forEach((column) => expect(data[0]).toHaveProperty(column));
  });

  it("should update the 'name' of the test account", async () => {
    const newName = "Updated Test User";
    await fetchData(
      `${process.env.SUPABASE_URL}/rest/v1/test_accounts?id=eq.${testAccountId}`,
      {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: newName }),
      },
    );

    const data = await fetchData(
      `${process.env.SUPABASE_URL}/rest/v1/test_accounts?id=eq.${testAccountId}`,
      { method: "GET" },
    );

    expect(data[0].name).toBe(newName);
  });

  it("should delete the test account", async () => {
    await fetchData(
      `${process.env.SUPABASE_URL}/rest/v1/test_accounts?id=eq.${testAccountId}`,
      { method: "DELETE" },
    );

    const data = await fetchData(
      `${process.env.SUPABASE_URL}/rest/v1/test_accounts?id=eq.${testAccountId}`,
      { method: "GET" },
    );

    expect(data.length).toBe(0);
  });

  it("should insert a new test account", async () => {
    const newAccountId = uuidv4();
    const newEmail = `newuser+${newAccountId}@example.com`;
    const data = await fetchData(
      `${process.env.SUPABASE_URL}/rest/v1/test_accounts`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Prefer: "return=representation",
        },
        body: JSON.stringify({
          id: newAccountId,
          user_id: testSetup.userId,
          name: "New Test User",
          email: newEmail,
        }),
      },
    );

    expect(data[0]).toHaveProperty("id", newAccountId);
    expect(data[0]).toHaveProperty("email", newEmail);
  });

  it("should not return results when accessing with only the anon key", async () => {
    const response = await fetch(
      `${process.env.SUPABASE_URL}/rest/v1/test_accounts?select=*`,
      {
        method: "GET",
        headers: {
          apikey: process.env.SUPABASE_ANON_KEY!,
          Authorization: `Bearer ${process.env.SUPABASE_ANON_KEY!}`,
        },
      },
    );

    const data = await response.json();
    expect(Array.isArray(data)).toBe(true);
    expect(data.length).toBe(0);
  });

  it("should fail when accessing a user's data with a valid key for a different user", async () => {
    const { data: newUserData } =
      await testSetup.supabase.auth.signInAnonymously();
    const newUserId = newUserData.user!.id;
    const newUserKeyResult = await testSetup.keyHippo.createApiKey(
      "Test Key for New User",
    );
    const newUserApiKey = newUserKeyResult.apiKey!;

    const data = await fetchData(
      `${process.env.SUPABASE_URL}/rest/v1/test_accounts?user_id=eq.${testSetup.userId}`,
      {
        method: "GET",
        headers: { "x-api-key": newUserApiKey },
      },
    );

    expect(Array.isArray(data)).toBe(true);
    expect(data.length).toBe(0);

    await testSetup.keyHippo.revokeApiKey(newUserKeyResult.id);
  });

  describe("KeyHippo Schema Tests", () => {
    let testApiKey: string;
    let testApiKeyId: string;

    beforeAll(async () => {
      const keyDescription = "Test Key for Schema Test";
      const result = await testSetup.keyHippo.createApiKey(keyDescription);
      testApiKey = result.apiKey!;
      testApiKeyId = result.id;
    });

    afterAll(async () => {
      if (testApiKeyId) {
        await testSetup.keyHippo.revokeApiKey(testApiKeyId);
      }
    });

    it("should access the user's own api_key_metadata in keyhippo schema", async () => {
      const keyhippoHeaders = {
        "Accept-Profile": "keyhippo",
        Accept: "application/json",
        "x-api-key": testApiKey,
      };

      const response = await fetch(
        `${process.env.SUPABASE_URL}/rest/v1/api_key_metadata?select=*`,
        {
          method: "GET",
          headers: {
            ...headers(),
            ...keyhippoHeaders,
          },
        },
      );

      if (!response.ok) {
        console.error("Response status:", response.status);
        console.error("Response headers:", response.headers);
        const errorBody = await response.text();
        console.error("Error body:", errorBody);
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const data = await response.json();

      expect(Array.isArray(data)).toBe(true);
      expect(data.length).toBeGreaterThan(0);

      const expectedProperties = [
        "id",
        "user_id",
        "description",
        "created_at",
        "last_used_at",
        "expires_at",
        "is_revoked",
      ];

      expectedProperties.forEach((prop) => {
        expect(data[0]).toHaveProperty(prop);
      });

      // Verify that the test API key is in the returned data
      const testKey = data.find((key) => key.id === testApiKeyId);
      expect(testKey).toBeDefined();
      expect(testKey!.description).toBe("Test Key for Schema Test");
    });

    it("should not access the api_key_secrets table in keyhippo schema", async () => {
      const response = await fetch(
        `${process.env.SUPABASE_URL}/rest/v1/api_key_secrets?select=*`,
        {
          method: "GET",
          headers: {
            ...headers(),
            "x-api-key": testApiKey,
          },
        },
      );

      expect(response.status).toBe(401); // Unauthorized or 403 Forbidden
    });
  });
});
