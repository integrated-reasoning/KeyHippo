--------------------------- MODULE KeyHippo ---------------------------
EXTENDS Naturals, Sequences, TLC, FiniteSets

CONSTANTS Users, APIKeys, Permissions, EncryptedData,
          MaxUsers, MaxKeys, MaxUsage, MaxAuditLen

ASSUME /\ MaxUsers <= Cardinality(Users)
       /\ MaxKeys <= Cardinality(APIKeys)
       /\ MaxUsage \in Nat
       /\ MaxAuditLen \in Nat

VARIABLES
    UserSet, KeySet, PermissionSet, AuditLog, UsageMetrics, LastUsed, EncryptedStorage

vars == <<UserSet, KeySet, PermissionSet, AuditLog, UsageMetrics, LastUsed, EncryptedStorage>>

IsValidPermission(perm) == perm \in Permissions

Init ==
    /\ UserSet = {}
    /\ KeySet = {}
    /\ PermissionSet = [k \in {} |-> {}]
    /\ AuditLog = <<>>
    /\ UsageMetrics = [k \in {} |-> 0]
    /\ LastUsed = [k \in {} |-> 0]
    /\ EncryptedStorage = [e \in EncryptedData |-> FALSE]

AddUser(id) ==
    /\ id \in Users
    /\ id \notin UserSet
    /\ Cardinality(UserSet) < MaxUsers
    /\ UserSet' = UserSet \cup {id}
    /\ AuditLog' = IF Len(AuditLog) < MaxAuditLen
                   THEN Append(AuditLog, <<id, "AddUser">>)
                   ELSE Tail(Append(AuditLog, <<id, "AddUser">>))
    /\ UNCHANGED <<KeySet, PermissionSet, UsageMetrics, LastUsed, EncryptedStorage>>

RemoveUser(id) ==
    /\ id \in UserSet
    /\ UserSet' = UserSet \ {id}
    /\ AuditLog' = IF Len(AuditLog) < MaxAuditLen
                   THEN Append(AuditLog, <<id, "RemoveUser">>)
                   ELSE Tail(Append(AuditLog, <<id, "RemoveUser">>))
    /\ UNCHANGED <<KeySet, PermissionSet, UsageMetrics, LastUsed, EncryptedStorage>>

CreateAPIKey(id, api_key, permission) ==
    /\ id \in UserSet
    /\ api_key \in APIKeys
    /\ IsValidPermission(permission)
    /\ api_key \notin KeySet
    /\ Cardinality(KeySet) < MaxKeys
    /\ KeySet' = KeySet \cup {api_key}
    /\ PermissionSet' = PermissionSet @@ (api_key :> permission)
    /\ UsageMetrics' = UsageMetrics @@ (api_key :> 0)
    /\ LastUsed' = LastUsed @@ (api_key :> 0)
    /\ AuditLog' = IF Len(AuditLog) < MaxAuditLen
                   THEN Append(AuditLog, <<id, "CreateAPIKey", api_key, permission>>)
                   ELSE Tail(Append(AuditLog, <<id, "CreateAPIKey", api_key, permission>>))
    /\ UNCHANGED <<UserSet, EncryptedStorage>>

RemoveAPIKey(api_key) ==
    /\ api_key \in KeySet
    /\ KeySet' = KeySet \ {api_key}
    /\ PermissionSet' = [k \in KeySet' |-> PermissionSet[k]]
    /\ UsageMetrics' = [k \in KeySet' |-> UsageMetrics[k]]
    /\ LastUsed' = [k \in KeySet' |-> LastUsed[k]]
    /\ AuditLog' = IF Len(AuditLog) < MaxAuditLen
                   THEN Append(AuditLog, <<api_key, "RemoveAPIKey">>)
                   ELSE Tail(Append(AuditLog, <<api_key, "RemoveAPIKey">>))
    /\ UNCHANGED <<UserSet, EncryptedStorage>>

UseAPIKey(api_key) ==
    /\ api_key \in KeySet
    /\ UsageMetrics[api_key] < MaxUsage
    /\ UsageMetrics' = [UsageMetrics EXCEPT ![api_key] = @ + 1]
    /\ LastUsed' = [LastUsed EXCEPT ![api_key] =
                    IF @ < MaxUsage THEN @ + 1 ELSE @]
    /\ AuditLog' = IF Len(AuditLog) < MaxAuditLen
                   THEN Append(AuditLog, <<api_key, "UseAPIKey">>)
                   ELSE Tail(Append(AuditLog, <<api_key, "UseAPIKey">>))
    /\ UNCHANGED <<UserSet, KeySet, PermissionSet, EncryptedStorage>>

ResetUsageMetrics(api_key) ==
    /\ api_key \in KeySet
    /\ UsageMetrics' = [UsageMetrics EXCEPT ![api_key] = 0]
    /\ AuditLog' = IF Len(AuditLog) < MaxAuditLen
                   THEN Append(AuditLog, <<api_key, "ResetUsageMetrics">>)
                   ELSE Tail(Append(AuditLog, <<api_key, "ResetUsageMetrics">>))
    /\ UNCHANGED <<UserSet, KeySet, PermissionSet, LastUsed, EncryptedStorage>>

EncryptData(data) ==
    /\ data \in EncryptedData
    /\ ~EncryptedStorage[data]
    /\ EncryptedStorage' = [EncryptedStorage EXCEPT ![data] = TRUE]
    /\ AuditLog' = IF Len(AuditLog) < MaxAuditLen
                   THEN Append(AuditLog, <<data, "EncryptData">>)
                   ELSE Tail(Append(AuditLog, <<data, "EncryptData">>))
    /\ UNCHANGED <<UserSet, KeySet, PermissionSet, UsageMetrics, LastUsed>>

DecryptData(data) ==
    /\ data \in EncryptedData
    /\ EncryptedStorage[data]
    /\ EncryptedStorage' = [EncryptedStorage EXCEPT ![data] = FALSE]
    /\ AuditLog' = IF Len(AuditLog) < MaxAuditLen
                   THEN Append(AuditLog, <<data, "DecryptData">>)
                   ELSE Tail(Append(AuditLog, <<data, "DecryptData">>))
    /\ UNCHANGED <<UserSet, KeySet, PermissionSet, UsageMetrics, LastUsed>>

Next ==
    \/ \E id \in Users : AddUser(id)
    \/ \E id \in Users : RemoveUser(id)
    \/ \E id \in Users, api_key \in APIKeys, permission \in Permissions :
        CreateAPIKey(id, api_key, permission)
    \/ \E api_key \in APIKeys : RemoveAPIKey(api_key)
    \/ \E api_key \in APIKeys : UseAPIKey(api_key)
    \/ \E api_key \in APIKeys : ResetUsageMetrics(api_key)
    \/ \E data \in EncryptedData : EncryptData(data)
    \/ \E data \in EncryptedData : DecryptData(data)

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

TypeInvariant ==
    /\ UserSet \subseteq Users
    /\ KeySet \subseteq APIKeys
    /\ Cardinality(UserSet) <= MaxUsers
    /\ Cardinality(KeySet) <= MaxKeys
    /\ DOMAIN PermissionSet = KeySet
    /\ DOMAIN UsageMetrics = KeySet
    /\ DOMAIN LastUsed = KeySet
    /\ \A api_key \in KeySet :
        /\ PermissionSet[api_key] \in Permissions
        /\ UsageMetrics[api_key] \in 0..MaxUsage
        /\ LastUsed[api_key] \in 0..MaxUsage
    /\ \A data \in EncryptedData : EncryptedStorage[data] \in BOOLEAN
    /\ Len(AuditLog) <= MaxAuditLen

NoUnauthorizedAccess ==
    \A api_key \in APIKeys :
        (api_key \in DOMAIN UsageMetrics /\ UsageMetrics[api_key] > 0) => api_key \in KeySet

DeadlockFree ==
    \/ \E id \in Users : id \notin UserSet /\ Cardinality(UserSet) < MaxUsers
    \/ \E id \in UserSet : TRUE  \* Can always remove a user if one exists
    \/ \E id \in UserSet, api_key \in APIKeys :
        api_key \notin KeySet /\ Cardinality(KeySet) < MaxKeys
    \/ \E api_key \in KeySet : TRUE  \* Can always remove a key if one exists
    \/ \E api_key \in KeySet : UsageMetrics[api_key] < MaxUsage
    \/ \E api_key \in KeySet : UsageMetrics[api_key] > 0
    \/ \E data \in EncryptedData : ~EncryptedStorage[data]
    \/ \E data \in EncryptedData : EncryptedStorage[data]

THEOREM Spec => []DeadlockFree

=============================================================================
