# Apache + Lucee production deployment

This application supports Apache 2.4 in front of Lucee 7/Tomcat. Apache serves static assets and forwards `.cfm`/`.cfc` requests (including `index.cfm/PATH_INFO`) to Lucee. Application routes use explicit `index.cfm/PATH_INFO` URLs, so deployment does not depend on pretty-URL rewriting.

## Required platform

- Apache HTTP Server 2.4 with `rewrite`, `proxy`, and `proxy_http`
- Lucee 7 on a supported Java runtime
- A Lucee/Tomcat HTTP connector bound to `127.0.0.1:8888`, or an existing `mod_cfml` installation
- A dedicated non-root Lucee service account
- HTTPS at Apache or a trusted upstream load balancer
- One active application instance while H2 remains the production datastore

## First deployment (Debian/Ubuntu)

Clone or update the repository into its final document root, then run:

```bash
cd /var/www/ussi-nexus
sudo bash deploy/prepare-linux.sh \
  --app-root /var/www/ussi-nexus \
  --service-user lucee \
  --service-group lucee \
  --server-name nexus.example.com \
  --install-apache
```

The script installs the pinned H2 JDBC driver after SHA-256 verification, creates the writable runtime directories, applies service-account permissions, enables the required Apache modules, renders the supplied virtual host, and runs `apache2ctl configtest`. It deliberately does not reload Apache or restart Lucee automatically.

If the server already uses `mod_cfml`, remove the `ProxyPassMatch` and `ProxyPassReverse` directives from the generated site. Keep the access-control rules; the remaining rewrite directives are security denials, not route rewriting.

## Lucee/Tomcat configuration

The Apache proxy example expects Tomcat/Lucee on `127.0.0.1:8888`. Do not expose that port publicly. The Tomcat host/context document base must point to the same application root Apache uses.

Set these variables in the Lucee/Tomcat service environment:

```text
USSI_NEXUS_ENV=production
USSI_NEXUS_BOOTSTRAP_USERNAME=matt.shaw
USSI_NEXUS_BOOTSTRAP_PASSWORD=<one-time strong bootstrap password>
LUCEE_ADMIN_PASSWORD=<strong administrative password>
```

Optionally set `USSI_NEXUS_RUNTIME_ROOT` to an absolute persistent directory. When set, `data/`, `uploads/`, and `outputs/` are created beneath that directory instead of the code checkout. Create that directory first and grant the Lucee service identity read/write access. This is recommended when releases are deployed into versioned or replaceable directories.

`USSI_NEXUS_ENV=production` enables Secure session cookies and HSTS, and makes `USSI_NEXUS_BOOTSTRAP_PASSWORD` mandatory when the user database is empty: the application refuses to start rather than create the first administrator with a built-in default password. Use the bootstrap password only for an empty database, then change it through the portal. Existing databases retain their users; password hashes are upgraded to PBKDF2 transparently on each user's next sign-in. The bootstrap username is also the account that is always kept as a superadmin.

State-changing requests must carry an `Origin` or `Referer` header whose host matches the request host. Keep `ProxyPreserveHost On` in the Apache site (as in the supplied example) so Lucee sees the public host name; without it every form submission and API call from the browser is rejected with 403.

The committed `.CFConfig.json` documents the H2 extension for CommandBox. Production does not depend on CommandBox importing it: `prepare-linux.sh` installs the verified H2 JAR directly into `lib/`, which `Application.cfc` loads through `this.javaSettings`.

### Windows Server

For Apache and Lucee/Tomcat on Windows, run PowerShell as an administrator:

```powershell
Set-Location C:\Sites\USSI-Nexus
.\deploy\prepare-windows.ps1 -AppRoot C:\Sites\USSI-Nexus -ServiceAccount "NT SERVICE\Lucee"
```

Replace the service identity with the account shown on the **Log On** tab of the Lucee/Tomcat Windows service. Copy the directives from `deploy\apache\ussi-nexus-vhost.conf.example` into Apache's virtual-host configuration, replacing the document-root and server-name placeholders. If BonCode/mod_cfml already connects Apache to Lucee, omit the manual `ProxyPassMatch` and `ProxyPassReverse` directives.

After restarting Lucee and Apache, validate with:

```powershell
.\deploy\check-deployment.ps1 -BaseUrl https://nexus.example.com
```

## HTTPS

Add a normal Apache `:443` virtual host or terminate TLS at a trusted upstream proxy. Redirect HTTP to HTTPS. When TLS terminates upstream, forward `X-Forwarded-Proto: https` and restrict direct access to Apache so clients cannot spoof forwarding headers.

## Persistent data and upgrades

Back up these paths before every release:

- `data/` — H2 database and training sign-off files
- `config/` — mutable pricing and reference-data overrides
- `outputs/` — generated reports and authorization metadata, if retention is required

Do not replace those paths with empty directories during deployment. Deploy code updates in place or restore these paths into the new release before starting Lucee. Run only one active Lucee application instance against the H2 database.

After updating code:

1. Run `sudo bash deploy/prepare-linux.sh --app-root /var/www/ussi-nexus --service-user lucee --service-group lucee`.
2. Restart Lucee/Tomcat so changed Java libraries and `Application.cfc` settings are loaded.
3. Run `apache2ctl configtest` and reload Apache.
4. Run `bash deploy/check-deployment.sh https://nexus.example.com`.
5. Sign in and test one upload/generation/download workflow.
6. Optionally run the browser regression suite from a workstation with Node.js: `npm install jsdom@24 && node tests/frontend/portal_regression.test.js`.

## Apache security behavior

The supplied virtual host and `.htaccess` deny direct access to application source, services, routes, configuration, templates, libraries, tests, deployment files, databases, uploads, and generated outputs. Downloads are served only through authenticated application routes.

The virtual-host configuration uses `AllowOverride None`, so its embedded rules are authoritative. `.htaccess` provides equivalent routing and protection for managed Apache environments where only per-directory configuration is available; those environments must permit `AllowOverride FileInfo Limit Options`.

## Validation and logs

Run:

```bash
bash deploy/check-deployment.sh https://nexus.example.com
```

Useful logs are normally:

- `/var/log/apache2/ussi-nexus-error.log`
- `/var/log/apache2/ussi-nexus-access.log`
- Lucee/Tomcat `catalina.out`
- Lucee application log `ussi_nexus.log`

The `/index.cfm/healthz` endpoint initializes the application, datasource, and services, so a successful response verifies substantially more than a static Apache response.
