# Relay Service

Optional paid tier that lets mobile clients reach home servers without port forwarding. Based on NullBore (pro account for custom subdomain support).

## Tunnel Infrastructure
- NullBore instance deployed on cloud VPS
- Custom subdomain assignment: `{user}.relay.abookify.com` (or similar)
- Multi-region deployment for latency
- TLS termination via Let's Encrypt
- WebSocket passthrough for real-time features
- Bandwidth monitoring per user

## Provisioning Layer
- User account management
- Tunnel allocation on subscription activation
- Custom subdomain assignment
- Server-side daemon config generation
- Subscription state sync

## Abuse and Safety
- Bandwidth rate limiting per tier
- Abuse detection (unusual traffic patterns)
- Suspension and termination mechanisms
- Content-blind -- relay never inspects payload

## Alternative Relay Support
- Documentation for Tailscale, Cloudflare Tunnel, WireGuard
- Config generators or setup guides for BYO tunnel
- Mobile app accepts arbitrary server URLs (not locked to our relay)
