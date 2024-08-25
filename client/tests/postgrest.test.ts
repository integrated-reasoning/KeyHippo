import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { v4 as uuidv4 } from "uuid";
import { setupTest, TestSetup } from "./testSetup";

let testSetup: TestSetup;
let testAccountId: string;
let apiKey: string;

const headers = () => ({
  apikey: process.env.SUPABASE_ANON_KEY!,
  Authorization: `Bearer ${process.env.SUPABASE_ANON_KEY!}`,
  "x-kh-api-key": apiKey,
});

const fetchData = async (url: string, options: RequestInit = {}) => {
  const response = await fetch(url, {
    ...options,
    headers: { ...headers(), ...options.headers },
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

  const keyDescription = "Test Key for x-kh-api-key";
  const result = await testSetup.keyHippo.createApiKey(
    testSetup.userId,
    keyDescription,
  );
  apiKey = result.apiKey!;

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
    const keyInfos = await testSetup.keyHippo.loadApiKeyInfo(testSetup.userId);
    for (const keyInfo of keyInfos) {
      await testSetup.keyHippo.revokeApiKey(testSetup.userId, keyInfo.id);
    }

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
      newUserId,
      "Test Key for New User",
    );
    const newUserApiKey = newUserKeyResult.apiKey!;

    const data = await fetchData(
      `${process.env.SUPABASE_URL}/rest/v1/test_accounts?user_id=eq.${testSetup.userId}`,
      {
        method: "GET",
        headers: { "x-kh-api-key": newUserApiKey },
      },
    );

    expect(Array.isArray(data)).toBe(true);
    expect(data.length).toBe(0);

    await testSetup.keyHippo.revokeApiKey(newUserId, newUserKeyResult.id);
  });
});
