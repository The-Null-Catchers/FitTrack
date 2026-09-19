# Security

## Reporting

Please report vulnerabilities privately through GitHub's security advisories
rather than opening a public issue.

## What the platform does

### Authentication

- bcrypt at cost 12. A password over 72 bytes is rejected rather than silently
  truncated.
- A sign-in attempt for an unknown address verifies against a real hash, so the
  endpoint takes the same time whether or not the account exists.
- Access tokens last 15 minutes; refresh tokens rotate on every use.
- **Replaying a rotated refresh token revokes every session for that account.**
- Password reset revokes all sessions. Reset and verification tokens are stored
  hashed and are single use.
- Suspending an account revokes its sessions immediately.

### Authorisation

Ownership is checked in the service layer, not the router, so every path into a
resource is covered. Progress photos are private from administrators too — the
admin API exposes counts, never content.

### Uploads

- MIME type allow-list and a size cap, checked before anything is written.
- Images are re-encoded server-side, which strips EXIF including GPS.
- Keys are namespaced and random; a crafted filename cannot escape the prefix.
- Private objects are served only through short-lived signed URLs. In local
  development the same HMAC-signed path is enforced, so the access-control code
  is exercised in every environment.

### Transport and headers

`X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`,
`Permissions-Policy` and — in production — HSTS. CORS is an explicit origin
list; `*` is never a valid value.

### Rate limiting

Per-user or per-IP fixed windows in Redis, with tighter limits on auth, uploads
and AI. The limiter fails **open**: a degraded cache should not take the product
down.

### Data handling

- SQL goes through the ORM; no string-built queries.
- Logs are redacted at the formatter — passwords, tokens, signed URLs and API
  keys never reach the log stream, regardless of the call site.
- Every authentication event and administrative change is written to an
  append-only audit log.
- Account deletion is immediate from the user's side; a background job hard-
  deletes the rows and stored objects 30 days later.

### Configuration

No secret is committed. `.env.example` documents every variable with a
placeholder or a safe local default. `JWT_SECRET` must be set to a real random
value in production; the development default is obviously named as such.

### Mobile

Tokens live in the Keychain / EncryptedSharedPreferences, never in
`SharedPreferences` or the local database. Signing out clears the local database
including any unsynced work, because that work belongs to the account leaving
the device.
