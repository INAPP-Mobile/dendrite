# Dendrite

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.com/deploy/dendrite?utm_campaign=dendrite)

Dendrite is a second-generation Matrix homeserver written in Go — a
lightweight, single-process alternative to Synapse for running your own
private Matrix server. This template wraps the official
`matrixdotorg/dendrite-monolith` image (v0.15.2, the maintained
[element-hq/dendrite](https://github.com/element-hq/dendrite) continuation)
for one-click deploys on Railway: one service, embedded SQLite, no
companion databases, all state on a single persistent volume.

Point any Matrix client (Element Web, Element Desktop, FluffyChat, Nheko,
Fractal) at your Railway URL and sign in as the admin account created on
first boot.

## Deploy and Host

Click **Deploy on Railway** above. The deploy form shows one pre-filled
field: the generated admin password — **save it before clicking Deploy**.
On first boot the wrapper generates the server's Matrix signing key, builds
the config, and creates the admin account `@admin:{your domain}`. Wait
about a minute after the deployment turns green, then log in.

No companion services: Dendrite is a single Go process with embedded
SQLite databases and an embedded NATS JetStream. Point any Matrix client
at your Railway domain and chat.

## Why Deploy

- **Your own homeserver, not someone else's account.** Your messages live
  in your SQLite databases on your volume — no third-party server, no
  phone number, no account on matrix.org required.
- **Lightweight by design.** One Go binary, ~60 MB image, SQLite instead of
  Postgres, no Redis, no workers. It fits comfortably on Railway's
  smallest tiers for a private server, and it idles cheaply.
- **Real Matrix, not a toy.** Full client-server API: rooms, direct
  messages, end-to-end encryption, media uploads, spaces, threads. Any
  spec-compliant client works against it.
- **Federation-ready (with one manual step).** Outbound federation works
  out of the box. Inbound federation needs a custom domain whose
  `.well-known/matrix/server` points at this deployment's domain on port
  443 — see "Federation" below.

## Common Use Cases

- A private family or team chat server that nobody else operates.
- A self-hosted backend for a community that wants Matrix without
  running Synapse + Postgres.
- A personal homeserver for bridging experiments and bots (any Matrix
  bot or appservice can register against it).
- A quiet corner of the federation: join rooms on other servers from
  your own domain once federation is delegated.

## Configuration

The wrapper consumes exactly these variables. Dendrite itself takes no
environment variables — its settings live in the config file the wrapper
generates on every boot under `/data/dendrite.yaml` (server_name and
signing key pinned from first boot; everything else regenerated from the
running image's defaults).

| Variable | Default | What it does |
| --- | --- | --- |
| `DENDRITE_ADMIN_PASSWORD` | `${{secret(32)}}` (generated per install) | Password for the admin account `@admin:{your domain}`. Shown in the deploy form — save it. Minimum 8 characters (Dendrite enforces this). If left empty, the entrypoint generates one and prints it once in the deploy logs. |
| `DENDRITE_ADMIN_USER` | `admin` (baked into the image) | Localpart of the admin account. Changing it after first boot does nothing — the account is created once. |
| `PORT` | injected by Railway | Port Dendrite binds via `--http-bind-address`. Never set this yourself; Railway sets it. |
| `RAILWAY_PUBLIC_DOMAIN` | injected by Railway | Becomes the Matrix `server_name` at first boot and is pinned forever. Matrix user IDs are `@user:server_name`, so the domain must not change after first boot or every account is orphaned. |

Upstream settings that apply to this deployment (all baked into the
generated config, not user-settable here): SQLite databases per component
under `/data/dendrite_*.db`, media uploads under `/data/media`, embedded
NATS JetStream under `/data`, full-text search index under
`/data/searchindex`, logs to stdout, healthcheck
`GET /_matrix/client/versions` (unauthenticated), registration disabled,
federation enabled.

## First steps

1. Deploy, save the admin password from the form, wait for green.
2. Open [Element Web](https://app.element.io), click "Edit" next to the
   homeserver, enter your Railway URL (`https://{your domain}`), and sign
   in as `admin` with the saved password. (Your user ID will be
   `@admin:{your domain}`.)
3. Create a room, send a message, invite people from other Matrix
   servers by their full `@user:server` IDs.

## Federation

Dendrite's HTTP listener serves the full API, including federation
routes, and Railway terminates TLS at the edge — so inbound federation
works if you delegate to it:

1. Own a domain, e.g. `matrix.example.com`.
2. Serve `https://matrix.example.com/.well-known/matrix/server` with
   `{"m.server": "{your-railway-domain}:443"}` from that domain (any
   static host works; Railway cannot serve this file for you).
3. Remote servers will then reach this deployment on port 443, and your
   `server_name` stays your Railway domain — user IDs do not change.

Without that delegation, the server still works fully for its own admin
account; it just cannot receive federation traffic initiated by other
servers. Outbound federation (your server contacting other servers)
works regardless.

## Honest limitations

- **One admin account, no open registration.** Dendrite refuses to start
  with open registration and no captcha, and the open-registration flag
  is code-only (not settable from a config file). This template therefore
  ships registration disabled and a single admin account. Additional
  local accounts can only be created with Dendrite's `create-account`
  tool, which needs container access Railway does not offer. If you need
  many local users, Synapse (with `enable_registration`) fits better.
- **server_name is forever.** It is pinned at first boot from
  `RAILWAY_PUBLIC_DOMAIN`. If you later attach a different domain, user
  IDs stay on the original domain. To change it, delete the volume and
  redeploy fresh (which wipes all accounts and rooms).
- **Backups are your volume.** Everything lives in `/data`. Railway
  volumes persist across redeploys, but there is no automatic off-site
  backup in this template — snapshot the volume before risky changes.

### Deployment Dependencies

- Railway plan with persistent volumes (any paid tier; the server idles
  on a fraction of a vCPU and a few hundred MB of RAM for a private
  server — media uploads and large rooms grow the volume, not the RAM).
- One volume (`dendrite-data`, mounted at `/data`). No databases, no
  Redis, no workers.
- A public domain (Railway-provided is fine) so clients can reach it and
  `server_name` has a stable value at first boot.
