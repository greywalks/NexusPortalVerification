# Microsoft Entra ID (Office 365) single sign-on

Groundwork is in `services/SsoService.cfc` and the `/auth/sso/*` routes. It is **inert until configured**; the password login is unchanged without these settings.

## Register the application (Entra admin center)

1. App registrations → New registration. Supported account types: *Accounts in this organizational directory only*.
2. Redirect URI (Web): `https://<your host>/index.cfm/auth/sso/callback`.
3. Certificates & secrets → New client secret (note the expiry and put a rotation reminder in your calendar).
4. Token configuration → add the optional claim **email** to the ID token (the code also accepts `preferred_username`).
5. API permissions: `openid`, `profile`, `email` (Microsoft Graph, delegated). Grant admin consent.

## Configure the server

```text
USSI_NEXUS_SSO_TENANT_ID=<Directory (tenant) ID>
USSI_NEXUS_SSO_CLIENT_ID=<Application (client) ID>
USSI_NEXUS_SSO_CLIENT_SECRET=<client secret>
USSI_NEXUS_SSO_REDIRECT_URI=https://nexus.example.com/index.cfm/auth/sso/callback
USSI_NEXUS_SSO_AUTO_PROVISION=0
USSI_NEXUS_SSO_ONLY=0
```

Lucee must be able to reach `https://login.microsoftonline.com` (token endpoint and signing keys).

## How sign-in maps to portal users

1. The ID token's signature is verified against the tenant's published keys; issuer, audience, tenant, expiry and nonce are checked.
2. The user is matched by Entra object id (`sso_subject`), then by email. An email match links the account permanently.
3. With `USSI_NEXUS_SSO_AUTO_PROVISION=1`, an unknown user is created with **no permissions**; an administrator grants access afterwards. Otherwise the sign-in is refused with an explanation and an `auth.sso_unlinked` audit event.
4. Add each existing user's work email under **User Management → Save email** before enabling SSO so they link on first sign-in.

Set `USSI_NEXUS_SSO_ONLY=1` only after SSO has been proven; it disables password sign-in for everyone, including the bootstrap administrator. Keep one break-glass local account documented (temporarily unset the variable to use it).

## Status

Not yet exercised against a real tenant. The CI suite only proves the routes are inert when unconfigured. First test on a non-production host with a test app registration, watching `ussi_nexus.log` and the audit log (`auth.login` with `method: sso`, `auth.sso_failed`, `auth.sso_unlinked`).
