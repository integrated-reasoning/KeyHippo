import { KeyHippo } from "../src/index";
import { createClient, SupabaseClient } from "@supabase/supabase-js";

export interface TestSetup {
  keyHippo: KeyHippo;
  userId: string;
  supabase: SupabaseClient; // Anonymous client for test operations
  serviceSupabase: SupabaseClient; // Service client for setup operations
  adminGroupId: string;
  userGroupId: string;
  adminRoleId: string;
  userRoleId: string;
}

export async function setupTest(): Promise<TestSetup> {
  // 1. Initialize the Service Client (bypasses RLS)
  const serviceSupabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
  );

  // 2. Initialize the Anonymous Client
  const supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_ANON_KEY!,
  );

  // 3. Sign in anonymously with the Anonymous Client
  const { data, error } = await supabase.auth.signInAnonymously();
  if (error || !data.user) {
    throw new Error("Error signing in anonymously");
  }

  const userId = data.user.id;

  // 4. Initialize KeyHippo with the Anonymous Client
  const keyHippo = new KeyHippo(supabase, console);

  // 5. Use the Service Client to fetch existing groups
  const { data: groups, error: groupsError } = await serviceSupabase
    .schema("keyhippo_rbac")
    .from("groups")
    .select("id, name");

  if (groupsError) {
    throw new Error(`Error fetching groups: ${groupsError.message}`);
  }

  // 6. Define required groups
  const requiredGroups = ["Admin Group", "User Group"];
  const existingGroupNames = groups.map(group => group.name);
  const missingGroups = requiredGroups.filter(groupName => !existingGroupNames.includes(groupName));

  // 7. Create missing groups
  for (const groupName of missingGroups) {
    const { data: newGroup, error: insertGroupError } = await serviceSupabase
      .schema("keyhippo_rbac")
      .from("groups")
      .insert({ name: groupName })
      .select("id, name");

    if (insertGroupError) {
      throw new Error(`Error creating group "${groupName}": ${insertGroupError.message}`);
    }

    groups.push(newGroup![0]);
  }

  // 8. Assign group IDs
  const adminGroup = groups.find(group => group.name === 'Admin Group');
  const userGroup = groups.find(group => group.name === 'User Group');

  if (!adminGroup || !userGroup) {
    throw new Error('Required groups (Admin Group and User Group) not found');
  }

  // 9. Fetch existing roles
  const { data: roles, error: rolesError } = await serviceSupabase
    .schema("keyhippo_rbac")
    .from("roles")
    .select("id, name");

  if (rolesError) {
    throw new Error(`Error fetching roles: ${rolesError.message}`);
  }

  // 10. Define required roles
  const requiredRoles = ["Admin", "User"];
  const existingRoleNames = roles.map(role => role.name);
  const missingRoles = requiredRoles.filter(roleName => !existingRoleNames.includes(roleName));

  // 11. Create missing roles
  for (const roleName of missingRoles) {
    const { data: newRole, error: insertRoleError } = await serviceSupabase
      .schema("keyhippo_rbac")
      .from("roles")
      .insert({ name: roleName })
      .select("id, name");

    if (insertRoleError) {
      throw new Error(`Error creating role "${roleName}": ${insertRoleError.message}`);
    }

    roles.push(newRole![0]);
  }

  // 12. Assign role IDs
  const adminRole = roles.find(role => role.name === 'Admin');
  const userRole = roles.find(role => role.name === 'User');

  if (!adminRole || !userRole) {
    throw new Error('Required roles (Admin and User) not found');
  }

  return {
    keyHippo,
    userId,
    supabase, // Anonymous client
    serviceSupabase, // Service client
    adminGroupId: adminGroup.id,
    userGroupId: userGroup.id,
    adminRoleId: adminRole.id,
    userRoleId: userRole.id,
  };
}
