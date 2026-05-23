# abookify-relay

Optional remote-access layer for an Abookify server. **You don't need this** if your devices can reach your server directly (LAN, VPN, port forward). It exists for the case where your mobile app is out in the world and your server is at home behind a NAT.

## Pick your own tunnel

Abookify is tunnel-agnostic. The mobile app accepts any reachable URL — you choose how the bits get from your phone to your server. This repo documents the options.

| Option | Best for | Setup |
|---|---|---|
| **NullBore** | Wants it to just work; willing to use a hosted service | This repo; one-line `start.sh` after server is running |
| **Cloudflare Tunnel** | Already on Cloudflare; comfortable with their dashboard | See [docs/cloudflare-tunnel.md](docs/cloudflare-tunnel.md) (planned) |
| **Tailscale** | Already on Tailscale; phone is on the same tailnet | Add the server, point the app at the tailnet IP. No code required. |
| **WireGuard** | Wants raw control; comfortable hand-rolling | Documentation only — Abookify doesn't care |
| **Port forward + DDNS** | Has a static-ish IP and is fine with router config | Documentation only — Abookify doesn't care |
| **Self-hosted NullBore** | Wants the NullBore UX without the NullBore service | NullBore is open source — run your own from [github.com/nullbore](https://github.com/nullbore) |

Nothing in Abookify pins you to any specific tunnel. The `Connect` screen in the mobile app just takes a URL.

## The NullBore path (what this repo automates)

[NullBore](https://nullbore.com) is an open-source tunnel ([nullbore/nullbore-client](https://github.com/nullbore/nullbore-client), [nullbore/nullbore-server](https://github.com/nullbore/nullbore-server)). The Abookify project runs a hosted NullBore instance at `*.abookify.nullbore.com` and offers it as an optional convenience tier for app subscribers.

This repo contains:

- `start.sh` — reads your server's install UUID and starts a NullBore tunnel pointed at it
- `client/` — vendored NullBore client source (retains its own upstream licence)
- Setup notes

### Quickstart

```bash
# 1. Get a NullBore API key (paid app subscribers get one provisioned automatically;
#    self-hosters can sign up directly at nullbore.com).
echo 'NULLBORE_API_KEY=nbk_…' > .env

# 2. Start the abookify server first.
cd ../server && docker compose up server -d

# 3. Start the tunnel.
cd ../relay && ./start.sh
# → tunneling https://<your-server-uuid>.abookify.nullbore.com → local :7654
```

That URL is what you paste into the Connect screen of the mobile app.

## What this repo is not

- **Not a hosted relay service.** The hosted relay tier (free for app subscribers) is operated by PJ3 Labs Inc. and provisioned automatically — you wouldn't touch this repo for that.
- **Not a fork of NullBore.** We use NullBore as-is; the `client/` directory is a vendored snapshot pinned for reproducibility.
- **Not required.** Abookify works perfectly fine with no tunnel at all if your server is reachable on its own.

## Licence

The wrapper code and documentation in this repo are released under [AGPL-3.0](LICENSE), matching `abookify-server`. The vendored NullBore client in `client/` is governed by its own upstream licence (see `client/LICENSE`).
