[![Deploy on Railway](https://railway.app/button.svg)](https://railway.com/deploy/dendrite?utm_campaign=dendrite)

# Deploy and Host

Dendrite is a second-generation Matrix homeserver written in Go — a
lightweight, single-process alternative to Synapse for running your own
private Matrix server. Deploy it on Railway in one click: one service,
embedded SQLite, no companion databases, all state on a single
persistent volume. Point any Matrix client (Element Web, Element Desktop,
FluffyChat, Nheko, Fractal) at your Railway URL and sign in as the admin
account created on first boot.

## About Hosting

Hosting Dendrite on Railway means the server runs as a single Go process
on Railway's infrastructure, with its SQLite databases, media uploads,
and embedded NATS JetStream state on a persistent volume. There are no
companion services to babysit: no Postgres to tune, no Redis to feed, no
workers to scale. The wrapper generates Dendrite's config on every boot
from the running image's own defaults, pins the Matrix server name and
signing key from first boot, and creates the admin account automatically.
Railway terminates TLS at the edge, and Dendrite's plain HTTP listener
serves the full API — including federation routes — so a custom domain
with a `.well-known` delegation can federate with the wider Matrix
network.

## Why Deploy

- **Your own homeserver, not someone else's account.** Messages live in
  your SQLite databases on your volume — no third-party server, no phone
  number, no matrix.org account required.
- **Lightweight by design.** One Go binary, ~60 MB image, SQLite instead
  of Postgres, no Redis, no workers. It fits Railway's smallest tiers
  for a private server and idles cheaply.
- **Real Matrix, not a toy.** Full client-server API: rooms, direct
  messages, end-to-end encryption, media uploads, spaces, threads. Any
  spec-compliant client works against it.
- **Federation-ready (with one manual step).** Outbound federation works
  out of the box; inbound federation needs a custom domain whose
  `.well-known/matrix/server` points at this deployment's domain:443.

## Common Use Cases

- A private family or team chat server that nobody else operates.
- A self-hosted backend for a community that wants Matrix without
  running Synapse + Postgres.
- A personal homeserver for bridging experiments and bots.
- A quiet corner of the federation: join rooms on other servers from
  your own domain once federation is delegated.

## Dependencies for

Dendrite on Railway depends on one persistent volume and a public
domain. Everything else — config generation, signing keys, admin
account creation, healthchecks — is handled by the wrapper at boot.

### Deployment Dependencies

- Railway plan with persistent volumes (any paid tier; a private server
  idles on a fraction of a vCPU and a few hundred MB of RAM — media
  uploads and large rooms grow the volume, not the RAM).
- One volume (`dendrite-data`, mounted at `/data`). No databases, no
  Redis, no workers.
- A public domain (Railway-provided is fine) so clients can reach it and
  `server_name` has a stable value at first boot.

## Configuration

| Variable | Default | What it does |
| --- | --- | --- |
| `DENDRITE_ADMIN_PASSWORD` | `${{secret(32)}}` (generated per install) | Password for `@admin:<your domain>`. Shown in the deploy form — save it. Minimum 8 characters. |
| `DENDRITE_ADMIN_USER` | `admin` (baked into the image) | Localpart of the admin account; set once at first boot. |
| `PORT` | injected by Railway | Port Dendrite binds via `--http-bind-address`. |
| `RAILWAY_PUBLIC_DOMAIN` | injected by Railway | Becomes the Matrix `server_name` at first boot, pinned forever. |

Upstream settings baked into the generated config: SQLite databases per
component under `/data/dendrite_*.db`, media under `/data/media`,
embedded NATS JetStream under `/data`, search index under
`/data/searchindex`, logs to stdout, healthcheck
`GET /_matrix/client/versions`, registration disabled, federation enabled.

## Honest limitations

- **One admin account, no open registration.** Dendrite refuses to start
  with open registration and no captcha, and its open-registration flag
  is code-only (not settable from a config file). Additional local
  accounts need Dendrite's `create-account` tool, which requires
  container access Railway does not offer.
- **server_name is forever.** Pinned at first boot from
  `RAILWAY_PUBLIC_DOMAIN`; changing domains later does not change user
  IDs. To change it, delete the volume and redeploy fresh.
- **Backups are your volume.** Everything lives in `/data` with no
  automatic off-site backup in this template.
