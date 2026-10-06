# End-to-end certificates: who holds which key — a recommendation for PJ

*server-web, 2026-10-06. One answer, with the reasoning; the facts are read from NullBore's
published code and the running service, not inferred.*

## The facts that decide it

1. NullBore's DNS-01 delegation (server `e0a4da2`, client v0.1.0-beta.24) validates a request
   against **the account that owns the API key**: any name under `<account>.e2e.nullbore.com`,
   leaf or wildcard. There is no per-tunnel scoping and no sub-account or scoped-key concept
   in the open-source auth model. The credential is the account.
2. Our product embeds **no** NullBore key today. "Hosted tunnel provisioned automatically for
   subscribers" is a sentence on the site and in a README; the provisioning layer does not
   exist yet. Nothing has to be un-shipped — this is a design choice we can still make right.
3. The same account key already lets its holder open, list and **delete** any tunnel under the
   account. So the impersonation problem is not new to certificates: a shared account key in
   users' hands would let any user take down or squat any other user's hostname. Certificates
   just make it visible.
4. Let's Encrypt issues at most 50 new certificates per week per registered domain. Today the
   registered domain is `nullbore.com`, shared by every NullBore user. Renewals are exempt.

## The recommendation

**Ship per-user credentials, never the account key — and get them from NullBore as
organisation-managed sub-accounts, with per-tunnel-scoped keys as the interim if sub-accounts
take longer.** Do not build a certificate-signing broker.

Why in this order:

- **Sub-accounts give the right scope by construction** (one account = one user = one set of
  names) *and* are the only shape that scales past the Let's Encrypt limit once the Public
  Suffix List entry exists (below). Administratively this is only available to us because
  NullBore and Abookify share a parent company; it would be absurd not to use that.
- **Scoped keys** (a key bound to one tunnel/leaf, which NullBore's `validateACMEChallenge`
  already takes as a parameter) are the cheaper first step: no per-user tier or billing
  question, a small change on their side. They fix the security property completely but not
  the rate-limit accounting (all Abookify names still sit under one registered domain).
- **A broker that signs or requests certificates for users is the wrong shape.** It
  centralises the impersonation capability in a service we must secure forever, it sees every
  CSR, and it is the thing an attacker would aim at. Our line this whole thread has been
  "property, not policy"; a broker is a policy ("we promise only to issue for your slug").

What we must operate either way, and disclose: **a provisioning service** that, when a
subscriber turns on the hosted relay, creates their sub-account or scoped key through
NullBore's administrative API and hands the credential to their server over the already
authenticated subscription channel. It carries no library content and never holds a private
key or a CSR. The privacy page sentence becomes: *"PJ3 Labs operates a small provisioning
service that creates your relay credentials; it never carries your books or your keys."*
That is a materially different disclosure from "a server that can read your traffic".

## PJ's own phone does not wait for any of this

PJ's server is the account owner, so running ACME DNS-01 with the account key on **his**
server is exactly the intended single-tenant use. The staging run below proves the path;
a production certificate for his hostname is one certificate against a 50/week budget and
unblocks iPhone testing immediately.

## Rate limits — the engineering shape of the volume answer

- 50 new certificates/week on `nullbore.com` is shared across *all* NullBore end-to-end users,
  so our usable budget is less than 50. One certificate per install: **the wall is reached at
  roughly 50 new Abookify installs a week, about 7 a day — any week with press.** Renewals
  don't count; re-issuing for the same name after a reinstall counts against the separate
  5-per-week "duplicate certificate" limit per name.
- **Start the Public Suffix List entry for `e2e.nullbore.com` now.** It takes weeks and we
  are pre-launch, so the lead time is free today and expensive later. With it, each
  `<account>.e2e.nullbore.com` becomes its own registered domain with its own 50/week.
  Combined with per-user sub-accounts that is effectively unlimited; combined with a single
  Abookify account it is still one 50/week bucket for all of us — which is why sub-accounts
  are the end state and scoped keys the interim.
- In parallel, NullBore should file Let's Encrypt's rate-limit adjustment request as a hosting
  provider; it is granted routinely for that shape and also takes time.
- Test against Let's Encrypt **staging** until the design is settled; do not spend production
  issuances proving a design.

## iOS versus Android, said honestly on the page

- **Android:** the app pins the server's public key (SPKI) on every network path. Property:
  the handshake must present the owner's key.
- **iOS:** the platform offers no trust override, so the guarantee is **"CA-trusted +
  CT-monitored"** — the certificate chains to a public CA and we watch Certificate
  Transparency for any certificate for our names that one of our servers did not obtain. That
  is weaker than a pin and the page will say so; it will not imply one guarantee across both.
- Whoever controls `nullbore.com` DNS can obtain a certificate for any name under it; this is
  not preventable, only detectable. NullBore disclosed this themselves.

## Certificate Transparency monitor — scope, not a hand-wave

- **Registry:** each server reports the fingerprint of the certificate it obtained to the
  provisioning service (which already knows the server's slug). ~½ day.
- **Watcher:** a daily job queries CT (crt.sh or Cert Spotter) for `%.abookify.e2e.nullbore.com`
  (later per-account names), diffs against the registry, and **alerts** (email to the ops
  address, plus a line in the session-start launch status) on any certificate we did not
  obtain. ~1 day, including the alert path and a test that injects an unknown fingerprint.
- **Response:** an unexpected certificate means a mis-issuance or a compromised zone; the
  response is to revoke via NullBore, re-pair affected devices, and say so on the page.

## What not to do this week

Do not flip `NULLBORE_E2E_PRIMARY`. Do not put the account key in any build. Do not write a
broker.
