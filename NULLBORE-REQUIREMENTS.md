# End-to-end encryption through the NullBore relay — a requirement from Abookify

*From: PJ3 Labs Inc. (Abookify). Written 2026-10-04. Audience: NullBore engineering.*

Abookify is a self-hosted audiobook/ebook server that people run on their own
machines; our phone app reaches it from outside the home through a tunnel, and
the default tunnel we ship is NullBore (`<slug>.abookify.nullbore.com`). Our
product's promise to users is "your content, your hardware". We checked whether
the relay path keeps that promise, and this document states what we found, what
we need, and how we will verify it. It is an architectural observation about a
relay that works exactly as designed, not a report of a fault.

## 1. What we observed (reproducible, 2026-10-04)

1. `<slug>.abookify.nullbore.com` resolves to Cloudflare (`172.64.80.1`,
   `2606:4700:…`); responses carry `server: cloudflare` and `cf-ray`. The
   certificate presented to a client is a Let's Encrypt certificate for
   `abookify.nullbore.com` / `*.abookify.nullbore.com`. The private key for that
   certificate is not on the tunnel owner's machine.
2. The tunnel client (`nullbore/nullbore-client`, `internal/tunnel/tunnel.go`)
   holds no certificate or key. It opens control and data WebSockets to
   `tunnel.nullbore.com:443` and pipes each data WebSocket to a plain TCP
   connection on the owner's host (`net.DialTimeout("tcp", localAddr)`).
3. The relay server (`nullbore/nullbore-server`, `internal/api/server.go`)
   terminates TLS on its own listener (`ListenAndServeTLS`, ACME or a cert
   file), parses the HTTP request, routes by the `Host` header, applies
   per-tunnel auth, rate and body limits, reads the request body in full
   (`io.ReadAll(io.LimitReader(r.Body, bodyLimit))`), re-serialises the request
   with `Host: localhost`, and writes it into the data WebSocket, then pipes
   bytes both ways while sniffing the response status line. When the tunnel
   owner enables inspection, method, path, headers and the first 4 KB of body
   are stored in `request_log`.
4. The Abookify server speaks plain HTTP only (it has no TLS code).

**Consequence.** On this path the user's TLS session ends at Cloudflare's edge,
and the relay handles the request in plaintext. Two parties other than the user
and their own server can read the payload in transit: Cloudflare and NullBore.
Whether either party *does* read or retain it is a matter of policy; that it
*can* is a property of the architecture. Our privacy policy and store
disclosures now say exactly this, and they will keep saying it until the
property changes, independent of any assurance.

## 2. What would resolve it, ranked

The requirement in one sentence: **a mode in which the private key that
terminates the user's TLS session lives only on the tunnel owner's machine, so
that the relay (and anything in front of it) forwards ciphertext it cannot
read.**

1. **TLS passthrough by SNI (preferred).** A listener that reads the TLS
   ClientHello's server name without terminating, maps `<slug>.<base>` to the
   tunnel, and pipes the raw TCP bytes into the existing data WebSocket. The
   existing data path (`RelayConn` → `pipe`/`io.Copy`) already carries opaque
   bytes; what is new is the front: an SNI peek instead of `http.Server`, and
   a per-tunnel flag (`mode: "tls-passthrough"`) that routes the hostname to
   it. For that tunnel the relay keeps TTL, connection rate limits and byte
   counting, and gives up HTTP-level features it cannot have without the
   plaintext (basic auth, path logging, body limits, status sniffing). We
   accept that trade.
2. **Raw TCP passthrough** (a port or hostname that forwards bytes with no
   HTTP parsing) is equivalent for us if it can be addressed by hostname.
3. **The Cloudflare layer must be covered, or (1) and (2) solve nothing.**
   Today the tunnel hostnames are Cloudflare-proxied, so the ClientHello never
   reaches the relay intact. For passthrough tunnels either the hostname must
   be DNS-only (not proxied), or Cloudflare must run in a TCP mode that does
   not terminate TLS (Spectrum-style). A passthrough mode *behind* an HTTP
   proxy is not passthrough.
4. **Optional, for browser clients:** a way for the tunnel owner to obtain a
   publicly trusted certificate for `<slug>.<base>` without the key leaving
   their machine — e.g. an authenticated API that sets
   `_acme-challenge.<slug>.<base>` TXT records so the owner's own ACME client
   can complete DNS-01. Not required for our app: at pairing, our QR code can
   carry the server's self-signed certificate fingerprint and the app can pin
   it, which needs nothing from the relay beyond passthrough.

If the "direct handoff" mode noted in your README (`mode: "direct"`, planned
for v3) carries the TLS session from client to owner's machine with the relay
acting only as a rendezvous, that satisfies the requirement too.

## 3. How we will verify it — this is the requirement, not the mode name

We will treat the capability as delivered only when this check passes, and we
will re-run it on a schedule and after any relay change:

1. Our server holds private key *K* and certificate *C* (fingerprint
   `F = sha256(C)`), and listens with TLS.
2. From a network outside the owner's LAN, complete a full TLS handshake and an
   application request against the public hostname:

       openssl s_client -connect <slug>.abookify.nullbore.com:443 \
         -servername <slug>.abookify.nullbore.com </dev/null 2>/dev/null \
         | openssl x509 -noout -fingerprint -sha256
       curl --pinnedpubkey "sha256//<base64 SPKI of C>" https://<slug>.abookify.nullbore.com/api/info

3. **Pass:** the presented fingerprint equals *F* **and** the pinned request
   returns our server's response. A completed handshake with our certificate
   proves the peer holds *K*; only our machine does, so no intermediary
   terminated the session. Serving the same *certificate* without *K* cannot
   pass this test.
4. Informational, not a pass condition: the hostname resolves to NullBore's
   own address rather than a proxy, and `server:`/`cf-*` headers are absent.

This check is cheap, needs no cooperation from anyone, and cannot be satisfied
by policy. That is the point: a property we can verify beats any assurance,
including from people we trust.

## 4. What we do meanwhile

- Our privacy page states, and will keep stating, that the default relay path
  is not end-to-end and that Cloudflare and NullBore can read traffic in
  transit; the LAN path is unencrypted HTTP; Tailscale and WireGuard are
  documented as the end-to-end options. This stays true regardless of the
  answer here, because our store attestations describe what is technically
  possible, not whom we trust.
- Nothing above asks NullBore to change its policy, its logging defaults, or
  its terms. It asks for a mode whose privacy property we can measure.

*Contact: hi@abookify.com. Evidence and commands available on request.*

---

## Addendum, 2026-10-06 — passthrough verified by us; one more requirement for iOS

**Verified on our own path today** (`<slug>-e2e.abookify.e2e.nullbore.com`, mode
`tls-passthrough`, tier pro): the hostname resolves directly to `209.38.3.94`; the
certificate a client receives is our server's own self-signed one; the presented
SPKI SHA-256 equals the one our server reports locally; a key-pinned request
(`curl --pinnedpubkey`) returns our server's response; no `server:`/`cf-*`
headers. Section 3 passes as written. Thank you — this was shipped faster than we
had any right to expect, and the Cloudflare point was handled exactly.

**What we learned on the client side.** Our Android stack can pin a self-signed
key (every network path is OkHttp). **iOS cannot:** AVPlayer, which plays the
audio, offers no server-trust override for HTTPS, and neither do the WebSocket
and image stacks we use. A self-signed leaf therefore fails chain validation
before any pin applies, and the only in-app workaround is a loopback TLS proxy
(weeks of work, and fragile). So for the end-to-end path to be usable on iPhone,
the certificate the server presents must be **publicly trusted** — while the
private key still lives only on the tunnel owner's machine.

**The requirement (previously §2 item 4, optional; now required):** a way for the
tunnel owner to obtain a publicly trusted certificate for
`<slug>.<account>.e2e.nullbore.com` without the key leaving their machine. The
natural shape is **ACME DNS-01 delegation**: an authenticated API call by the
tunnel owner that sets (and later clears) the TXT record
`_acme-challenge.<slug>.<account>.e2e.nullbore.com`, so the owner's own ACME
client (we would embed one in our server) completes a Let's Encrypt order
locally. The relay never sees a key. Section 3 is unchanged: the handshake must
present the owner's key; our app keeps pinning the SPKI as the proof.

Alternatives we can live with: an `_acme-challenge` CNAME delegation to a zone
the owner controls (standard "DNS alias" mode), or passthrough routing for a
hostname we control under our own domain (then we run the DNS-01 side). What
does not work: the relay obtaining the certificate — that puts the key on the
relay and defeats the mode.

Until one of these exists, our apps keep using the proxied path by default, and
our privacy page says so.
