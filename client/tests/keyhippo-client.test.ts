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
    expect(createdKeyInfo.id).toBeDefined();

    // Rotate the API key
    const rotatedKeyInfo = await testSetup.keyHippo.rotateApiKey(
      createdKeyInfo.id,
    );
    console.log("Rotated Key Info:", rotatedKeyInfo);

    if ("status" in rotatedKeyInfo && rotatedKeyInfo.status === "failed") {
      expect.fail(
        `API key rotation failed: ${(rotatedKeyInfo as any).message}`,
      );
    }

    expect(rotatedKeyInfo.id).toBeDefined();
    expect(rotatedKeyInfo.apiKey).toBeDefined();

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
    console.log("Key Summaries:", keySummaries);
    console.log("Rotated Key ID:", rotatedKeyInfo.id);
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

  /*
  it("should reject API keys that exceed the maximum allowed size", async () => {
    // TODO: Write similar tests for all text fields including RBAC, ABAC metadata
    const oversizedKeyDescription = "A".repeat(5000); // Simulating an oversized key

    // Attempt to create an oversized API key
    await expect(
      testSetup.keyHippo.createApiKey(
        testSetup.userId,
        oversizedKeyDescription,
      ),
    ).rejects.toThrow("API key size exceeds the allowed limit");
  });

  it("should reject tampered API keys", async () => {
    const keyDescription = "Tampered Key";

    // Create an API key
    const createdKeyInfo = await testSetup.keyHippo.createApiKey(
      testSetup.userId,
      keyDescription,
    );

    // Tamper with the key
    const tamperedKey = createdKeyInfo.apiKey!.slice(0, -1) + "X"; // Modify the last character

    // Attempt to authenticate using the tampered key
    const mockHeaders = new Headers({ Authorization: `Bearer ${tamperedKey}` });
    await expect(testSetup.keyHippo.authenticate(mockHeaders)).rejects.toThrow(
      "Invalid API key",
    );
  });

  it("should prevent creating API keys for other users without authorization", async () => {
    const unauthorizedUserId = "99999999-9999-9999-9999-999999999999";

    // Attempt to create an API key for another user
    await expect(
      testSetup.keyHippo.createApiKey(unauthorizedUserId, "Unauthorized Key"),
    ).rejects.toThrow("Unauthorized to create key for user");
  });

  it("should not log API keys in plaintext", async () => {
    const keyDescription = "Log Leakage Test Key";

    // Create an API key and check the logs
    const createdKeyInfo = await testSetup.keyHippo.createApiKey(
      testSetup.userId,
      keyDescription,
    );

    // Check the log output for accidental leakage
    const logs = await testSetup.getLogs();

    expect(logs).not.toContain(createdKeyInfo.apiKey);
  });

  it("should prevent privilege escalation using API key", async () => {
    const keyDescription = "Privilege Escalation Key";

    // Create a low-privileged API key
    const lowPrivKey = await testSetup.keyHippo.createApiKey(
      testSetup.userId,
      keyDescription,
      { privilegeLevel: "low" },
    );

    // Attempt to perform a high-privilege action
    await expect(
      testSetup.keyHippo.performAdminAction(lowPrivKey.apiKey),
    ).rejects.toThrow("Insufficient privileges");
  });

  it("should prevent replaying API key creation requests", async () => {
    const keyDescription = "Replay Attack Test Key";

    // Record the request details
    const request = {
      userId: testSetup.userId,
      description: keyDescription,
    };

    // Create the API key
    const keyInfo = await testSetup.keyHippo.createApiKey(
      request.userId,
      request.description,
    );
    expect(keyInfo).toHaveProperty("id");

    // Attempt to replay the same request
    await expect(
      testSetup.keyHippo.createApiKey(request.userId, request.description),
    ).rejects.toThrow("Duplicate request detected");
  });

  it("should enforce rate limiting on API key creation", async () => {
    const keyDescription = "Rate Limiting Test Key";

    // Try to create multiple API keys in quick succession
    for (let i = 0; i < 10; i++) {
      await testSetup.keyHippo.createApiKey(
        testSetup.userId,
        `${keyDescription} ${i}`,
      );
    }

    // Expect rate limit error on the 11th attempt
    await expect(
      testSetup.keyHippo.createApiKey(testSetup.userId, "Excess Key"),
    ).rejects.toThrow("Rate limit exceeded");
  });

  it("should reject access to API keys without Authorization header", async () => {
    const keyDescription = "Unauthorized Access Key";

    const createdKeyInfo = await testSetup.keyHippo.createApiKey(
      testSetup.userId,
      keyDescription,
    );

    // Attempt to authenticate without Authorization header
    await expect(
      testSetup.keyHippo.authenticate(new Headers({})),
    ).rejects.toThrow("Unauthorized");
  });

  it("should not authenticate with an expired API key", async () => {
    const keyDescription = "Expiring Key";

    // Create an API key with an expiration time of 1 second
    const createdKeyInfo = await testSetup.keyHippo.createApiKey(
      testSetup.userId,
      keyDescription,
      { expiresIn: 1 }, // TODO: make this configurable
    );

    // Wait for the key to expire
    await new Promise((resolve) => setTimeout(resolve, 2000));

    // Attempt to authenticate using the expired key
    const mockHeaders = new Headers({
      Authorization: `Bearer ${createdKeyInfo.apiKey}`,
    });
    await expect(testSetup.keyHippo.authenticate(mockHeaders)).rejects.toThrow(
      "Unauthorized",
    );
  });

  it("should fail to create more API keys if the user exceeds the maximum limit", async () => {
    const maxKeys = 5; // TODO implement this as a constraint

    // Create the maximum number of API keys
    for (let i = 0; i < maxKeys; i++) {
      await testSetup.keyHippo.createApiKey(testSetup.userId, `Test Key ${i}`);
    }

    // Attempt to create one more key
    await expect(
      testSetup.keyHippo.createApiKey(testSetup.userId, "Excess Key"),
    ).rejects.toThrow("API key limit exceeded");
  });
  */

 /*
  describe("KeyHippo Client RBAC and ABAC Tests", () => {
    it("should add user to a group with a role (RBAC)", async () => {
      const groupId = testSetup.adminGroupId;
      const roleName = "Admin";

      // Add user to a group with a role
      await testSetup.keyHippo.addUserToGroup(
        testSetup.userId,
        groupId,
        roleName,
      );

      // Query claims cache directly to verify
      const claimsCacheResult = await testSetup.serviceSupabase
        .schema("keyhippo_rbac")
        .from("claims_cache")
        .select("rbac_claims")
        .eq("user_id", testSetup.userId)
        .single();

      console.log("RBAC Claims:", claimsCacheResult.data!.rbac_claims);

      expect(claimsCacheResult.data).toBeDefined();
      expect(claimsCacheResult.data!.rbac_claims).toBeDefined();
      expect(
        claimsCacheResult.data!.rbac_claims[testSetup.adminGroupId],
      ).toContain(roleName);
    });

    it("should set parent role in RBAC hierarchy", async () => {
      const childRoleId = testSetup.userRoleId;
      const parentRoleId = testSetup.adminRoleId;

      await testSetup.keyHippo.setParentRole(childRoleId, parentRoleId);

      // Instead of checking the returned data, verify the role hierarchy directly
      const roleHierarchy = await testSetup.serviceSupabase
        .schema("keyhippo_rbac")
        .from("roles")
        .select("parent_role_id")
        .eq("id", childRoleId)
        .single();

      expect(roleHierarchy.data).toBeDefined();
      expect(roleHierarchy.data!.parent_role_id).toBe(parentRoleId);
    });

    it("should assign a parent role to a child role", async () => {
      const childRoleId = testSetup.userRoleId; // 'User' role
      const parentRoleId = testSetup.adminRoleId; // 'Admin' role

      // Assign the parent role
      await testSetup.keyHippo.setParentRole(childRoleId, parentRoleId);

      // Verify the parent role assignment
      const parentRoleResult = await testSetup.serviceSupabase
        .schema("keyhippo_rbac")
        .from("roles")
        .select("parent_role_id")
        .eq("id", childRoleId)
        .single();

      expect(parentRoleResult.data).toBeDefined();
      expect(parentRoleResult.data!.parent_role_id).toBe(parentRoleId);
    });
    */

    /*
    it("should not rotate an API key if the user does not have the right role", async () => {
      const keyDescription = "Key to Rotate with Role Check";

      // Create API key
      const createdKeyInfo = await testSetup.keyHippo.createApiKey(
        testSetup.userId,
        keyDescription,
      );

      // Assign a role that doesn't have permission to rotate keys
      await testSetup.keyHippo.addUserToGroup(
        testSetup.userId,
        testSetup.userGroupId,
        "LimitedUser",
      );

      // Attempt to rotate the API key
      await expect(
        testSetup.keyHippo.rotateApiKey(testSetup.userId, createdKeyInfo.id),
      ).rejects.toThrow("Unauthorized");
    });

    it("should prevent circular role hierarchies", async () => {
      const childRoleId = testSetup.userRoleId;
      const parentRoleId = testSetup.adminRoleId;

      // Set parent role once
      await testSetup.keyHippo.setParentRole(childRoleId, parentRoleId);

      // Attempt to set circular parent (childRoleId becomes parent of parentRoleId)
      await expect(
        testSetup.keyHippo.setParentRole(parentRoleId, childRoleId),
      ).rejects.toThrow("Circular role hierarchy detected");
    });

    it("should ensure a role without a parent does not inherit higher privileges", async () => {
      const roleName = "Test Role Without Parent";
      const childRoleId = await testSetup.keyHippo.createRole(roleName);

      // Attempt to evaluate permissions for a role without a parent
      const rolePermissions =
        await testSetup.keyHippo.getRolePermissions(childRoleId);

      expect(rolePermissions).toBeDefined();
      expect(rolePermissions.length).toBe(0); // No permissions should be inherited
    });

    it("should allow multiple role assignments without conflict", async () => {
      const groupId = testSetup.adminGroupId;
      const roles = ["Admin", "User"];

      for (const role of roles) {
        await testSetup.keyHippo.addUserToGroup(
          testSetup.userId,
          groupId,
          role,
        );
      }

      const claimsCacheResult = await testSetup.serviceSupabase
        .schema("keyhippo_rbac")
        .from("claims_cache")
        .select("rbac_claims")
        .eq("user_id", testSetup.userId)
        .single();

      expect(claimsCacheResult.data).toBeDefined();
      for (const role of roles) {
        expect(
          claimsCacheResult.data!.rbac_claims[testSetup.adminGroupId],
        ).toContain(role);
      }
    });
    */

   /*
    it("should create an ABAC policy", async () => {
      const policyName = "test-policy";
      const description = "Test Policy Description";
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "engineering",
      };

      await testSetup.keyHippo.createPolicy(policyName, description, policy);

      // Verify the policy creation in the database
      const createdPolicy = await testSetup.serviceSupabase
        .schema("keyhippo_abac")
        .from("policies")
        .select("*")
        .eq("name", policyName)
        .single();

      expect(createdPolicy.data).toBeDefined();
      expect(createdPolicy.data.description).toBe(description);
      expect(JSON.parse(createdPolicy.data.policy)).toEqual(policy);
    });

    it("should create and retrieve a policy (ABAC)", async () => {
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "IT",
      };
      const description = "Test Policy";

      // Create the ABAC policy
      await testSetup.keyHippo.createPolicy("Test Policy", description, policy);

      // Verify the policy was created
      const createdPolicy = await testSetup.serviceSupabase
        .schema("keyhippo_abac")
        .from("policies")
        .select("description, policy")
        .eq("name", "Test Policy")
        .single();

      console.log("Created Policy:", createdPolicy.data!.policy);

      expect(createdPolicy.data).toBeDefined();
      expect(createdPolicy.data!.description).toBe(description);
      expect(JSON.parse(createdPolicy.data!.policy)).toEqual(policy);
    });

    it("should evaluate ABAC policies for a user", async () => {
      const userId = testSetup.userId;
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "engineering",
      };

      // Create the policy
      await testSetup.keyHippo.createPolicy(
        "Test Policy",
        "Test Policy Description",
        policy,
      );

      // Set the user's attribute
      await testSetup.keyHippo.setUserAttribute(
        userId,
        "department",
        "engineering",
      );

      // Evaluate the policies
      const result = await testSetup.keyHippo.evaluatePolicies(userId);

      console.log("Policy evaluation result:", result);
      expect(result).toBe(true);
    });

    it("should retrieve user attributes (ABAC)", async () => {
      const attribute = "department";
      const expectedValue = "engineering";

      // Ensure the user has the attribute set
      await testSetup.keyHippo.setUserAttribute(
        testSetup.userId,
        attribute,
        expectedValue,
      );

      const attributeValue = await testSetup.keyHippo.getUserAttribute(
        testSetup.userId,
        attribute,
      );

      expect(attributeValue).toEqual(expectedValue);
    });
    */

    /*
    it("should evaluate policies with multiple attributes correctly", async () => {
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "engineering",
      };

      const locationPolicy = {
        type: "attribute_equals",
        attribute: "location",
        value: "HQ",
      };

      // Create two policies
      await testSetup.keyHippo.createPolicy(
        "Engineering Policy",
        "Department Policy",
        policy,
      );
      await testSetup.keyHippo.createPolicy(
        "Location Policy",
        "Location Policy",
        locationPolicy,
      );

      // Set user attributes
      await testSetup.keyHippo.setUserAttribute(
        testSetup.userId,
        "department",
        "engineering",
      );
      await testSetup.keyHippo.setUserAttribute(
        testSetup.userId,
        "location",
        "HQ",
      );

      // Evaluate the policies
      const result = await testSetup.keyHippo.evaluatePolicies(
        testSetup.userId,
      );
      expect(result).toBe(true); // Both policies should be satisfied
    });
   */

  /*
    it("should fail when creating a duplicate policy", async () => {
      const policyName = "duplicate-policy";
      const description = "Duplicate Policy";
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "engineering",
      };

      // Create the policy once
      await testSetup.keyHippo.createPolicy(policyName, description, policy);

      // Try creating the same policy again, expecting no error due to ON CONFLICT DO NOTHING
      await testSetup.keyHippo.createPolicy(policyName, description, policy);

      // Verify that only one policy exists
      const policies = await testSetup.serviceSupabase
        .schema("keyhippo_abac")
        .from("policies")
        .select("*")
        .eq("name", policyName);

      expect(policies.data?.length).toBe(1);
    });

    it("should fail policy evaluation if an attribute is missing", async () => {
      const policy = {
        type: "attribute_equals",
        attribute: "location",
        value: "HQ",
      };

      // Create the policy
      await testSetup.keyHippo.createPolicy(
        "Location Policy",
        "Location Policy",
        policy,
      );

      // Ensure the user has no 'location' attribute
      const result = await testSetup.keyHippo.evaluatePolicies(
        testSetup.userId,
      );

      expect(result).toBe(false); // Should fail as the 'location' attribute is missing
    });

    it("should fail policy evaluation for user with missing attributes", async () => {
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "engineering",
      };

      // Create the policy
      await testSetup.keyHippo.createPolicy(
        "Engineering Access",
        "Access restricted to engineering department",
        policy,
      );

      // User doesn't have the 'department' attribute set
      await expect(
        testSetup.keyHippo.evaluatePolicies(testSetup.userId),
      ).resolves.toBe(false); // Expect the policy evaluation to fail
    });

    it("should evaluate policies with multiple attributes", async () => {
      const multiAttributePolicy = {
        type: "attribute_equals",
        attribute: "role",
        value: "manager",
      };

      await testSetup.keyHippo.createPolicy(
        "Multi-Attribute Policy",
        "Requires role and department",
        multiAttributePolicy,
      );

      // Assign a different attribute to the user
      await testSetup.keyHippo.setUserAttribute(
        testSetup.userId,
        "role",
        "developer",
      );

      // Expect policy evaluation to fail
      const result = await testSetup.keyHippo.evaluatePolicies(
        testSetup.userId,
      );
      expect(result).toBe(false);
    });

    it("should fail policy evaluation when user has no attributes", async () => {
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "engineering",
      };

      await testSetup.keyHippo.createPolicy(
        "No Attribute Policy",
        "Requires department",
        policy,
      );

      // Ensure the user has no attributes
      await testSetup.keyHippo.setUserAttribute(
        testSetup.userId,
        "department",
        null,
      );

      const result = await testSetup.keyHippo.evaluatePolicies(
        testSetup.userId,
      );
      expect(result).toBe(false);
    });

    it("should allow assigning multiple roles to the same user", async () => {
      const adminRoleId = testSetup.adminRoleId;
      const userRoleId = testSetup.userRoleId;

      // Assign both Admin and User roles to the same user
      await testSetup.keyHippo.addUserToGroup(
        testSetup.userId,
        testSetup.adminGroupId,
        "Admin",
      );
      await testSetup.keyHippo.addUserToGroup(
        testSetup.userId,
        testSetup.userGroupId,
        "User",
      );

      // Query claims cache directly to verify
      const claimsCache = await testSetup.serviceSupabase
        .schema("keyhippo_rbac")
        .from("claims_cache")
        .select("rbac_claims")
        .eq("user_id", testSetup.userId)
        .single();

      expect(claimsCache.data!.rbac_claims[testSetup.adminGroupId]).toContain(
        "Admin",
      );
      expect(claimsCache.data!.rbac_claims[testSetup.userGroupId]).toContain(
        "User",
      );
    });

    it("should fail policy evaluation after required attribute is removed", async () => {
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "engineering",
      };

      await testSetup.keyHippo.createPolicy(
        "Engineering Access",
        "Access restricted to engineering",
        policy,
      );

      // Set the attribute
      await testSetup.keyHippo.setUserAttribute(
        testSetup.userId,
        "department",
        "engineering",
      );

      // Remove the 'department' attribute
      await testSetup.keyHippo.setUserAttribute(
        testSetup.userId,
        "department",
        null,
      );

      // Policy evaluation should now fail
      const result = await testSetup.keyHippo.evaluatePolicies(
        testSetup.userId,
      );
      expect(result).toBe(false);
    });
    */

    /*
    it("should fail policy evaluation after revoking group attributes", async () => {
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "sales",
      };

      await testSetup.keyHippo.createPolicy(
        "Revoked Group Attribute Policy",
        "Sales Group Access",
        policy,
      );

      // Set group attributes for the user's group
      await testSetup.keyHippo.setGroupAttribute(
        testSetup.userGroupId,
        "department",
        "sales",
      );

      // Revoke the group attribute
      await testSetup.keyHippo.setGroupAttribute(
        testSetup.userGroupId,
        "department",
        null,
      );

      // Ensure policy evaluation fails
      const result = await testSetup.keyHippo.evaluatePolicies(
        testSetup.userId,
      );
      expect(result).toBe(false);
    });

    it("should evaluate policies against group attributes", async () => {
      const policy = {
        type: "attribute_equals",
        attribute: "department",
        value: "sales",
      };

      await testSetup.keyHippo.createPolicy(
        "Group Attribute Policy",
        "Sales Group Access",
        policy,
      );

      // Set group attributes for the user's group
      await testSetup.keyHippo.setGroupAttribute(
        testSetup.userGroupId,
        "department",
        "sales",
      );

      // Ensure the user inherits attributes from the group
      const result = await testSetup.keyHippo.evaluatePolicies(
        testSetup.userId,
      );
      expect(result).toBe(true);
    });

    it("should evaluate policies based on multiple attributes", async () => {
      const multiAttributePolicy = {
        type: "and",
        conditions: [
          {
            type: "attribute_equals",
            attribute: "department",
            value: "engineering",
          },
          { type: "attribute_equals", attribute: "location", value: "HQ" },
        ],
      };

      await testSetup.keyHippo.createPolicy(
        "Multi-Attribute Policy",
        "Engineering at HQ",
        multiAttributePolicy,
      );

      // Set the user's attributes
      await testSetup.keyHippo.setUserAttribute(
        testSetup.userId,
        "department",
        "engineering",
      );
      await testSetup.keyHippo.setUserAttribute(
        testSetup.userId,
        "location",
        "HQ",
      );

      const result = await testSetup.keyHippo.evaluatePolicies(
        testSetup.userId,
      );
      expect(result).toBe(true);
    });

    it("should update claims cache after role reassignment", async () => {
      const oldRoleId = testSetup.userRoleId;
      const newRoleId = testSetup.adminRoleId;

      // Assign the old role
      await testSetup.keyHippo.addUserToGroup(
        testSetup.userId,
        testSetup.userGroupId,
        "User",
      );

      // Switch to the new role (Admin)
      await testSetup.keyHippo.setParentRole(testSetup.userRoleId, newRoleId);

      // Check that the claims cache reflects the new role
      const claimsCache = await testSetup.serviceSupabase
        .schema("keyhippo_rbac")
        .from("claims_cache")
        .select("rbac_claims")
        .eq("user_id", testSetup.userId)
        .single();

      expect(claimsCache.data!.rbac_claims[testSetup.adminGroupId]).toContain(
        "Admin",
      );
      expect(
        claimsCache.data!.rbac_claims[testSetup.userGroupId],
      ).toBeUndefined();
    });

    it("should evaluate policies with 'or' conditions", async () => {
      const orConditionPolicy = {
        type: "or",
        conditions: [
          {
            type: "attribute_equals",
            attribute: "department",
            value: "engineering",
          },
          { type: "attribute_equals", attribute: "role", value: "admin" },
        ],
      };

      await testSetup.keyHippo.createPolicy(
        "Or Condition Policy",
        "Engineering or Admin",
        orConditionPolicy,
      );

      // Set the user's attribute to 'role: admin' (should pass the policy)
      await testSetup.keyHippo.setUserAttribute(
        testSetup.userId,
        "role",
        "admin",
      );

      const result = await testSetup.keyHippo.evaluatePolicies(
        testSetup.userId,
      );
      expect(result).toBe(true);
    });

    it("should reject role assignment to a non-existent group", async () => {
      const nonExistentGroupId = "99999999-9999-9999-9999-999999999999"; // Invalid group ID

      await expect(
        testSetup.keyHippo.addUserToGroup(
          testSetup.userId,
          nonExistentGroupId,
          "Admin",
        ),
      ).rejects.toThrow("Group not found");
    });

    it("should revoke multiple roles from a user", async () => {
      const adminRoleId = testSetup.adminRoleId;
      const userRoleId = testSetup.userRoleId;

      // Assign Admin and User roles to the user
      await testSetup.keyHippo.addUserToGroup(
        testSetup.userId,
        testSetup.adminGroupId,
        "Admin",
      );
      await testSetup.keyHippo.addUserToGroup(
        testSetup.userId,
        testSetup.userGroupId,
        "User",
      );

      // Revoke both roles
      await testSetup.keyHippo.setParentRole(userRoleId, "");
      await testSetup.keyHippo.setParentRole(adminRoleId, "");

      // Verify both roles are revoked
      const claimsCache = await testSetup.serviceSupabase
        .schema("keyhippo_rbac")
        .from("claims_cache")
        .select("rbac_claims")
        .eq("user_id", testSetup.userId)
        .single();

      expect(claimsCache.data!.rbac_claims).toBeUndefined();
    });

    it("should inherit permissions from parent role in hierarchy", async () => {
      const childRoleId = testSetup.userRoleId;
      const parentRoleId = testSetup.adminRoleId;

      // Set Admin as the parent of User
      await testSetup.keyHippo.setParentRole(childRoleId, parentRoleId);

      // Verify the child role inherits the permissions of the parent role
      const claimsCache = await testSetup.serviceSupabase
        .schema("keyhippo_rbac")
        .from("claims_cache")
        .select("rbac_claims")
        .eq("user_id", testSetup.userId)
        .single();

      expect(claimsCache.data!.rbac_claims[testSetup.adminGroupId]).toContain(
        "Admin",
      );
    });

    it("should update claims cache on role revocation", async () => {
      const roleId = testSetup.adminRoleId; // Admin role

      // Assign the role
      await testSetup.keyHippo.addUserToGroup(
        testSetup.userId,
        testSetup.adminGroupId,
        "Admin",
      );

      // Revoke the role
      await testSetup.keyHippo.setParentRole(testSetup.adminRoleId, "");

      // Check that the claims cache no longer contains the Admin role
      const claimsCache = await testSetup.serviceSupabase
        .schema("keyhippo_rbac")
        .from("claims_cache")
        .select("rbac_claims")
        .eq("user_id", testSetup.userId)
        .single();

      expect(
        claimsCache.data!.rbac_claims[testSetup.adminGroupId],
      ).toBeUndefined();
    });

    it("should evaluate nested policies correctly", async () => {
      const complexPolicy = {
        type: "and",
        conditions: [
          {
            type: "attribute_equals",
            attribute: "department",
            value: "engineering",
          },
          { type: "attribute_equals", attribute: "location", value: "HQ" },
        ],
      };

      await testSetup.keyHippo.createPolicy(
        "Complex Policy",
        "Multiple conditions",
        complexPolicy,
      );

      // Set the user's attributes
      await testSetup.keyHippo.setUserAttribute(
        testSetup.userId,
        "department",
        "engineering",
      );
      await testSetup.keyHippo.setUserAttribute(
        testSetup.userId,
        "location",
        "HQ",
      );

      const result = await testSetup.keyHippo.evaluatePolicies(
        testSetup.userId,
      );
      expect(result).toBe(true);
    });

    it("should reject recursive role assignment", async () => {
      const childRoleId = testSetup.userRoleId; // 'User' role
      const parentRoleId = testSetup.adminRoleId; // 'Admin' role

      // Assign parent role
      await testSetup.keyHippo.setParentRole(childRoleId, parentRoleId);

      // Attempt to assign 'User' role as the parent of 'Admin', creating a circular reference
      await expect(
        testSetup.keyHippo.setParentRole(parentRoleId, childRoleId),
      ).rejects.toThrow("Circular role hierarchy detected");
    });

    it("should reject removing non-existent role", async () => {
      const invalidRoleId = "99999999-9999-9999-9999-999999999999"; // Invalid role ID

      await expect(
        testSetup.keyHippo.setParentRole(invalidRoleId, testSetup.adminRoleId),
      ).rejects.toThrow("Role not found");
    });

    it("should reject role assignment to non-existent user", async () => {
      const nonExistentUserId = "99999999-9999-9999-9999-999999999999"; // Invalid user ID
      const roleName = "Admin";

      await expect(
        testSetup.keyHippo.addUserToGroup(
          nonExistentUserId,
          testSetup.adminGroupId,
          roleName,
        ),
      ).rejects.toThrow("User does not exist");
    });

    it("should reject policy creation with invalid data types", async () => {
      const invalidDataTypePolicy = {
        type: "attribute_equals",
        attribute: "department",
        value: 123, // Invalid type, should be a string
      };

      await expect(
        testSetup.keyHippo.createPolicy(
          "Invalid Data Type Policy",
          "Invalid value type",
          invalidDataTypePolicy,
        ),
      ).rejects.toThrow("Invalid policy format");
    });

    it("should reject policy creation with missing fields", async () => {
      const incompletePolicy = {
        type: "attribute_equals", // Missing 'attribute' and 'value'
      };

      await expect(
        testSetup.keyHippo.createPolicy(
          "Incomplete Policy",
          "Missing fields",
          incompletePolicy,
        ),
      ).rejects.toThrow("Invalid policy format");
    });

    it("should reject invalid policy formats", async () => {
      const invalidPolicy = {
        type: "invalid_type",
        attribute: "department",
        value: "engineering",
      };

      // Attempt to create an invalid policy
      await expect(
        testSetup.keyHippo.createPolicy(
          "Invalid Policy",
          "Invalid Policy Description",
          invalidPolicy,
        ),
      ).rejects.toThrow("Invalid policy format");
    });
  });
  */
});
