--------------------------- MODULE JWT ---------------------------
EXTENDS Naturals, Sequences, TLC, FiniteSets

CONSTANTS Users, Secrets, Claims, Issuers, Audiences, MaxTokens, MaxTime,
          Scopes, MaxTokensPerUser, MaxTokenUses

ASSUME /\ MaxTokens \in Nat
       /\ MaxTime \in Nat
       /\ MaxTokens > 0
       /\ MaxTime > 0
       /\ MaxTokensPerUser \in Nat
       /\ MaxTokensPerUser > 0
       /\ MaxTokenUses \in Nat
       /\ MaxTokenUses > 0

VARIABLES
    ActiveTokens,    \* Set of active JWTs
    TokenClaims,     \* Mapping of tokens to their claims
    TokenSignatures, \* Mapping of tokens to their signatures
    CurrentTime,     \* Current system time
    TokenExpiration, \* Mapping of tokens to their expiration time
    RevokedTokens,   \* Set of revoked token IDs
    TokenIssuers,    \* Mapping of tokens to their issuers
    TokenAudiences,  \* Mapping of tokens to their intended audiences
    TokenScopes,     \* Mapping of tokens to their scopes
    TokenUses,       \* Mapping of tokens to their use count
    UserTokens       \* Mapping of users to their tokens

vars == <<ActiveTokens, TokenClaims, TokenSignatures, CurrentTime,
          TokenExpiration, RevokedTokens, TokenIssuers, TokenAudiences,
          TokenScopes, TokenUses, UserTokens>>

\* Helper function to generate a unique token ID
GenerateTokenId(user, time) ==
    LET hash == ((CHOOSE n \in 1..1000 : TRUE) *
                 (CHOOSE prime \in {2, 3, 5, 7, 11, 13, 17, 19, 23, 29} : TRUE)) % 997
    IN  "jwt_" \o ToString(hash)

\* Type correctness invariant
TypeInvariant ==
    /\ ActiveTokens \subseteq STRING
    /\ TokenClaims \in [ActiveTokens -> [sub: Users, iat: Nat, exp: Nat]]
    /\ TokenSignatures \in [ActiveTokens -> STRING]
    /\ CurrentTime \in 0..MaxTime
    /\ TokenExpiration \in [ActiveTokens -> 0..MaxTime]
    /\ RevokedTokens \subseteq ActiveTokens
    /\ TokenIssuers \in [ActiveTokens -> Issuers]
    /\ TokenAudiences \in [ActiveTokens -> SUBSET Audiences]
    /\ TokenScopes \in [ActiveTokens -> SUBSET Scopes]
    /\ TokenUses \in [ActiveTokens -> 0..MaxTokenUses]
    /\ UserTokens \in [Users -> SUBSET ActiveTokens]
    /\ Cardinality(ActiveTokens) <= MaxTokens

\* Initial state
Init ==
    /\ ActiveTokens = {}
    /\ TokenClaims = [t \in {} |-> [sub |-> "", iat |-> 0, exp |-> 0]]
    /\ TokenSignatures = [t \in {} |-> ""]
    /\ CurrentTime = 0
    /\ TokenExpiration = [t \in {} |-> 0]
    /\ RevokedTokens = {}
    /\ TokenIssuers = [t \in {} |-> ""]
    /\ TokenAudiences = [t \in {} |-> {}]
    /\ TokenScopes = [t \in {} |-> {}]
    /\ TokenUses = [t \in {} |-> 0]
    /\ UserTokens = [u \in Users |-> {}]

\* Helper function to validate claims
ValidClaims(claims) ==
    /\ claims.sub \in Users
    /\ claims.iat <= CurrentTime
    /\ claims.exp > CurrentTime

\* Create a new JWT
CreateJWT ==
    /\ Cardinality(ActiveTokens) < MaxTokens
    /\ \E user \in Users, issuer \in Issuers, audience \in (SUBSET Audiences) \ {{}},
         scope \in (SUBSET Scopes) \ {{}}, expirationTime \in CurrentTime+2..IF CurrentTime+5 <= MaxTime THEN CurrentTime+5 ELSE MaxTime :
        /\ Cardinality(UserTokens[user]) < MaxTokensPerUser
        /\ LET newToken == GenerateTokenId(user, CurrentTime)
               claims == [
                   sub |-> user,
                   iat |-> CurrentTime,
                   exp |-> expirationTime
               ]
               signature == "sig_" \o newToken
           IN  /\ ActiveTokens' = ActiveTokens \cup {newToken}
               /\ TokenClaims' = TokenClaims @@ (newToken :> claims)
               /\ TokenSignatures' = TokenSignatures @@ (newToken :> signature)
               /\ TokenExpiration' = TokenExpiration @@ (newToken :> expirationTime)
               /\ TokenIssuers' = TokenIssuers @@ (newToken :> issuer)
               /\ TokenAudiences' = TokenAudiences @@ (newToken :> audience)
               /\ TokenScopes' = TokenScopes @@ (newToken :> scope)
               /\ TokenUses' = TokenUses @@ (newToken :> 0)
               /\ UserTokens' = UserTokens @@ (user :> UserTokens[user] \cup {newToken})
    /\ UNCHANGED <<CurrentTime, RevokedTokens>>

\* Verify a JWT
VerifyJWT(token) ==
    /\ token \in ActiveTokens
    /\ token \notin RevokedTokens
    /\ CurrentTime < TokenExpiration[token]
    /\ ValidClaims(TokenClaims[token])
    /\ TokenUses[token] < MaxTokenUses

\* Use a JWT
UseJWT ==
    \E token \in ActiveTokens, audience \in Audiences :
        /\ VerifyJWT(token)
        /\ audience \in TokenAudiences[token]
        /\ TokenUses' = TokenUses @@ (token :> TokenUses[token] + 1)
        /\ UNCHANGED <<ActiveTokens, TokenClaims, TokenSignatures, CurrentTime,
                       TokenExpiration, RevokedTokens, TokenIssuers, TokenAudiences,
                       TokenScopes, UserTokens>>

\* Revoke a JWT
RevokeJWT ==
    /\ \E token \in ActiveTokens \ RevokedTokens :
        /\ RevokedTokens' = RevokedTokens \cup {token}
        /\ \E user \in Users :
            /\ token \in UserTokens[user]
            /\ UserTokens' = UserTokens @@ (user :> UserTokens[user] \ {token})
    /\ UNCHANGED <<ActiveTokens, TokenClaims, TokenSignatures, CurrentTime,
                   TokenExpiration, TokenIssuers, TokenAudiences, TokenScopes, TokenUses>>

\* Remove expired or revoked tokens
CleanupTokens ==
    LET ExpiredTokens == {t \in ActiveTokens : CurrentTime >= TokenExpiration[t]}
        TokensToRemove == ExpiredTokens \cup RevokedTokens
    IN /\ TokensToRemove # {}
       /\ ActiveTokens' = ActiveTokens \ TokensToRemove
       /\ TokenClaims' = [t \in ActiveTokens' |-> TokenClaims[t]]
       /\ TokenSignatures' = [t \in ActiveTokens' |-> TokenSignatures[t]]
       /\ TokenExpiration' = [t \in ActiveTokens' |-> TokenExpiration[t]]
       /\ TokenIssuers' = [t \in ActiveTokens' |-> TokenIssuers[t]]
       /\ TokenAudiences' = [t \in ActiveTokens' |-> TokenAudiences[t]]
       /\ TokenScopes' = [t \in ActiveTokens' |-> TokenScopes[t]]
       /\ TokenUses' = [t \in ActiveTokens' |-> TokenUses[t]]
       /\ UserTokens' = [u \in Users |-> UserTokens[u] \ TokensToRemove]
       /\ RevokedTokens' = RevokedTokens \ TokensToRemove
       /\ UNCHANGED <<CurrentTime>>

\* Advance time
AdvanceTime ==
    /\ CurrentTime' = (CurrentTime + 1) % (MaxTime + 1)
    /\ UNCHANGED <<ActiveTokens, TokenClaims, TokenSignatures,
                   TokenExpiration, RevokedTokens, TokenIssuers, TokenAudiences,
                   TokenScopes, TokenUses, UserTokens>>

\* Next state
Next ==
    \/ CreateJWT
    \/ UseJWT
    \/ RevokeJWT
    \/ CleanupTokens
    \/ (\/ AdvanceTime
        \/ UNCHANGED vars)

\* Specification
Spec == Init /\ [][Next]_vars

\* Invariants
TokensAreValid ==
    \A token \in ActiveTokens \ RevokedTokens :
        CurrentTime < TokenExpiration[token] => VerifyJWT(token)

NoRevokedTokensAreValid ==
    \A token \in RevokedTokens : ~VerifyJWT(token)

UserTokenLimitRespected ==
    \A user \in Users : Cardinality(UserTokens[user]) <= MaxTokensPerUser

TokenUseLimitRespected ==
    \A token \in ActiveTokens : TokenUses[token] <= MaxTokenUses

\* Properties
TokenLimitRespected ==
    [](Cardinality(ActiveTokens) <= MaxTokens)

ExpiredTokensAreNotValid ==
    [][\A token \in ActiveTokens :
        CurrentTime >= TokenExpiration[token] => ~VerifyJWT(token)]_vars

\* Liveness property: It's always eventually possible to create a new token
LivenessCreateJWT ==
    [](\A user \in Users :
        Cardinality(UserTokens[user]) < MaxTokensPerUser ~>
        Cardinality(UserTokens[user]) > 0)

\* Fairness conditions
Fairness ==
    /\ WF_vars(CreateJWT)
    /\ WF_vars(UseJWT)
    /\ WF_vars(RevokeJWT)
    /\ WF_vars(CleanupTokens)
    /\ WF_vars(AdvanceTime)
    /\ SF_vars(CreateJWT)

\* The complete specification
CompleteSpec == Spec /\ Fairness

=============================================================================
