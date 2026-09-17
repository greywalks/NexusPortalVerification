component output=false {
    // Microsoft Entra ID (Office 365) sign-in via OpenID Connect authorization
    // code flow with PKCE. Enabled only when every USSI_NEXUS_SSO_* setting is
    // present, so a deployment without them behaves exactly as before.
    //
    //   USSI_NEXUS_SSO_TENANT_ID      directory (tenant) ID, or "organizations"
    //   USSI_NEXUS_SSO_CLIENT_ID      application (client) ID
    //   USSI_NEXUS_SSO_CLIENT_SECRET  client secret
    //   USSI_NEXUS_SSO_REDIRECT_URI   e.g. https://nexus.example.com/index.cfm/auth/sso/callback
    //   USSI_NEXUS_SSO_AUTO_PROVISION 1 to create a portal user (no permissions) on first sign-in
    //   USSI_NEXUS_SSO_ONLY           1 to disable password sign-in once SSO is proven
    function init() {
        variables.system = createObject("java", "java.lang.System");
        variables.tenant = env("USSI_NEXUS_SSO_TENANT_ID");
        variables.clientId = env("USSI_NEXUS_SSO_CLIENT_ID");
        variables.clientSecret = env("USSI_NEXUS_SSO_CLIENT_SECRET");
        variables.redirectUri = env("USSI_NEXUS_SSO_REDIRECT_URI");
        variables.autoProvision = listFindNoCase("1,true,yes,on", env("USSI_NEXUS_SSO_AUTO_PROVISION")) > 0;
        variables.ssoOnly = listFindNoCase("1,true,yes,on", env("USSI_NEXUS_SSO_ONLY")) > 0;
        variables.authority = "https://login.microsoftonline.com/" & variables.tenant & "/";
        variables.jwks = {keys:[], fetched:createDateTime(2000,1,1,0,0,0)};
        return this;
    }
    private string function env(required string name) { var v = variables.system.getenv(arguments.name); return isNull(v) ? "" : trim(v & ""); }

    boolean function enabled() { return len(variables.tenant) && len(variables.clientId) && len(variables.clientSecret) && len(variables.redirectUri); }
    boolean function passwordLoginAllowed() { return !(enabled() && variables.ssoOnly); }
    boolean function autoProvision() { return variables.autoProvision; }

    private string function base64Url(required binary bytes) { return replace(replace(replace(binaryEncode(arguments.bytes, "base64"), "+", "-", "all"), "/", "_", "all"), "=", "", "all"); }
    private binary function fromBase64Url(required string s) { var t = replace(replace(arguments.s, "-", "+", "all"), "_", "/", "all"); while (len(t) mod 4 != 0) t &= "="; return binaryDecode(t, "base64"); }
    private string function randomToken(numeric bytes=32) { var b = createObject("java", "java.security.SecureRandom").init().generateSeed(javaCast("int", arguments.bytes)); return base64Url(b); }

    // Returns {url, state, nonce, verifier}; the caller keeps state/nonce/verifier in the session.
    struct function beginLogin() {
        var state = randomToken(24); var nonce = randomToken(24); var verifier = randomToken(48);
        var digest = createObject("java", "java.security.MessageDigest").getInstance("SHA-256");
        var challenge = base64Url(digest.digest(charsetDecode(verifier, "utf-8")));
        var params = ["client_id=" & urlEncodedFormat(variables.clientId), "response_type=code", "redirect_uri=" & urlEncodedFormat(variables.redirectUri), "response_mode=query", "scope=" & urlEncodedFormat("openid profile email"), "state=" & urlEncodedFormat(state), "nonce=" & urlEncodedFormat(nonce), "code_challenge=" & urlEncodedFormat(challenge), "code_challenge_method=S256"];
        return {url:variables.authority & "oauth2/v2.0/authorize?" & arrayToList(params, "&"), state:state, nonce:nonce, verifier:verifier};
    }

    // Exchanges the code and returns validated identity claims, or throws Logicore.Sso.
    struct function completeLogin(required string code, required string verifier, required string expectedNonce) {
        var res = "";
        cfhttp(url=variables.authority & "oauth2/v2.0/token", method="post", result="res", timeout="20", charset="utf-8") {
            cfhttpparam(type="formfield", name="client_id", value=variables.clientId);
            cfhttpparam(type="formfield", name="client_secret", value=variables.clientSecret);
            cfhttpparam(type="formfield", name="grant_type", value="authorization_code");
            cfhttpparam(type="formfield", name="code", value=arguments.code);
            cfhttpparam(type="formfield", name="redirect_uri", value=variables.redirectUri);
            cfhttpparam(type="formfield", name="code_verifier", value=arguments.verifier);
        }
        if (!isJson(res.fileContent ?: "")) throw(type="Logicore.Sso", message="The identity provider returned an unexpected response (HTTP " & (res.statusCode ?: "?") & ").");
        var body = deserializeJson(res.fileContent);
        if (structKeyExists(body, "error")) throw(type="Logicore.Sso", message="Token exchange failed: " & (body.error_description ?: body.error));
        if (!len(body.id_token ?: "")) throw(type="Logicore.Sso", message="No ID token was returned.");
        var claims = verifyIdToken(body.id_token);
        if ((claims.nonce ?: "") != arguments.expectedNonce) throw(type="Logicore.Sso", message="ID token nonce mismatch.");
        var email = lCase(trim(claims.email ?: claims.preferred_username ?: ""));
        return {subject:claims.oid ?: claims.sub, tenant:claims.tid ?: "", email:email, name:claims.name ?: "", upn:lCase(trim(claims.preferred_username ?: "")), claims:claims};
    }

    // RS256 signature check against the tenant's published keys plus issuer,
    // audience, tenant and expiry checks.
    private struct function verifyIdToken(required string token) {
        var parts = listToArray(arguments.token, ".", true);
        if (arrayLen(parts) != 3) throw(type="Logicore.Sso", message="Malformed ID token.");
        var header = deserializeJson(charsetEncode(fromBase64Url(parts[1]), "utf-8"));
        var claims = deserializeJson(charsetEncode(fromBase64Url(parts[2]), "utf-8"));
        if ((header.alg ?: "") != "RS256") throw(type="Logicore.Sso", message="Unsupported ID token algorithm " & (header.alg ?: ""));
        var key = publicKey(header.kid ?: "");
        var sig = createObject("java", "java.security.Signature").getInstance("SHA256withRSA");
        sig.initVerify(key);
        sig.update(charsetDecode(parts[1] & "." & parts[2], "utf-8"));
        if (!sig.verify(fromBase64Url(parts[3]))) throw(type="Logicore.Sso", message="ID token signature is invalid.");
        var nowEpoch = int(getTickCount() / 1000);
        if (val(claims.exp ?: 0) < nowEpoch - 60) throw(type="Logicore.Sso", message="ID token has expired.");
        if (val(claims.nbf ?: 0) > nowEpoch + 300) throw(type="Logicore.Sso", message="ID token is not yet valid.");
        if ((claims.aud ?: "") != variables.clientId) throw(type="Logicore.Sso", message="ID token audience mismatch.");
        var iss = claims.iss ?: "";
        if (!reFindNoCase("^https://login\.microsoftonline\.com/[^/]+/v2\.0/?$", iss)) throw(type="Logicore.Sso", message="ID token issuer is not Microsoft Entra ID.");
        if (variables.tenant != "organizations" && variables.tenant != "common" && (claims.tid ?: "") != variables.tenant) throw(type="Logicore.Sso", message="ID token was issued for a different tenant.");
        return claims;
    }

    private any function publicKey(required string kid) {
        if (dateDiff("n", variables.jwks.fetched, now()) > 60 || !arrayLen(variables.jwks.keys)) refreshJwks();
        var match = findKey(arguments.kid);
        if (!structCount(match)) { refreshJwks(); match = findKey(arguments.kid); }
        if (!structCount(match)) throw(type="Logicore.Sso", message="Signing key " & arguments.kid & " is not published by the identity provider.");
        var bigInt = createObject("java", "java.math.BigInteger");
        var n = bigInt.init(javaCast("int", 1), fromBase64Url(match.n));
        var e = bigInt.init(javaCast("int", 1), fromBase64Url(match.e));
        var spec = createObject("java", "java.security.spec.RSAPublicKeySpec").init(n, e);
        return createObject("java", "java.security.KeyFactory").getInstance("RSA").generatePublic(spec);
    }
    private struct function findKey(required string kid) { for (var k in variables.jwks.keys) if ((k.kid ?: "") == arguments.kid && (k.kty ?: "") == "RSA") return k; return {}; }
    private void function refreshJwks() {
        var res = "";
        cfhttp(url=variables.authority & "discovery/v2.0/keys", method="get", result="res", timeout="20", charset="utf-8");
        if (!isJson(res.fileContent ?: "")) throw(type="Logicore.Sso", message="Could not download the identity provider's signing keys.");
        var body = deserializeJson(res.fileContent);
        variables.jwks = {keys:body.keys ?: [], fetched:now()};
    }
}
