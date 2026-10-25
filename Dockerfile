# Dendrite (element-hq) monolith wrapper for Railway.
#
# Why each non-default setting exists:
# - FROM pins the official monolith image by tag AND digest (amd64):
#   matrixdotorg/dendrite-monolith v0.15.2, the maintained element-hq
#   continuation of the archived matrix-org repo. Never :latest: a moving
#   tag would change the server binary under existing SQLite databases,
#   and Dendrite bumps its schema between versions.
# - USER root: Railway mounts persistent volumes root-owned; the Alpine
#   base already runs as root, and this keeps it explicit so the entrypoint
#   can write keys, config, SQLite databases, media and JetStream state to
#   /data without EACCES crash loops.
# - The image's own ENTRYPOINT (/usr/bin/dendrite with no config) is
#   replaced by entrypoint.sh, which generates the config, the signing key
#   and the first admin account on first boot. See entrypoint.sh for the
#   full rationale (registration must stay disabled: Dendrite refuses to
#   start with open registration and no captcha).
# - No HEALTHCHECK: the base image has curl, but Railway's external
#   healthcheckPath (/_matrix/client/versions) is the check that matters;
#   an in-container HEALTHCHECK would only duplicate it.
# - No EXPOSE: the server binds Railway's injected PORT via
#   --http-bind-address, so a static port declaration would be a lie.
# - No CMD: entrypoint.sh execs the server itself; nothing depends on the
#   image CMD.
FROM matrixdotorg/dendrite-monolith:v0.15.2@sha256:e9a93fe88ab6c3716af5a495e021201e9aee30a8509dadb4a7ebd7d859880144
USER root
# Default admin username. The password comes from the template variable
# DENDRITE_ADMIN_PASSWORD (generated per install); overriding the username
# post-deploy has no effect because the account is created on first boot.
ENV DENDRITE_ADMIN_USER=admin
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
LABEL org.opencontainers.image.source="https://github.com/mc9max/dendrite"
LABEL org.opencontainers.image.title="Dendrite"
LABEL org.opencontainers.image.description="Dendrite Matrix homeserver (element-hq) wrapped for one-click Railway deploys"
