# ---- Global build arguments ----
# NODE:           Base Node.js image (pinned for reproducible builds)
# NGINX:          Nginx image for serving the static Vite build output
# APP_UID/GID:    Non-root user/group IDs for container security
# APP_USERNAME:   Non-root username inside the container
# APP_GROUPNAME:  Non-root group name inside the container
# APP_DIR:        Working directory for all stages
# PORT:           Port the Nginx server listens on (also used in nginx.conf.template)
ARG NODE=node:24.14-alpine3.23
ARG NGINX=nginx:1.28.2-alpine3.23
ARG APP_UID=1001
ARG APP_GID=1001
ARG APP_USERNAME=container-user
ARG APP_GROUPNAME=container-group
ARG APP_DIR=/app
ARG PORT=3000

# ---- Base ----
# Shared Alpine + Node foundation. All dependency/build stages inherit from here
# so that OS-level packages (tzdata) are only installed once.
# The non-root user is created here so /etc/passwd and /etc/group can be copied
# into prod images that may not have `adduser`/`addgroup` (e.g. hardened images).
FROM ${NODE} AS base
ARG APP_DIR
ARG APP_UID
ARG APP_GID
ARG APP_USERNAME
ARG APP_GROUPNAME

WORKDIR ${APP_DIR}

RUN apk add --no-cache tzdata \
    && apk upgrade --no-cache \
    && cp /usr/share/zoneinfo/Asia/Singapore /etc/localtime \
    && echo "Asia/Singapore" > /etc/timezone \
    && addgroup -g ${APP_GID} ${APP_GROUPNAME} \
    && adduser -S -u ${APP_UID} -h ${APP_DIR} -s /sbin/nologin -G ${APP_GROUPNAME} ${APP_USERNAME}

# ---- Dependencies ----
# Installs ALL dependencies (including devDependencies like vite, typescript,
# postcss, etc.) which are required for the build step. Uses the auto-detected
# package manager based on which lockfile is present.
FROM base AS deps
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* .npmrc* ./
RUN \
  if [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm i --frozen-lockfile; \
  elif [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  else echo "Lockfile not found." && exit 1; \
  fi

# ---- Builder ----
# Copies source code and runs the Vite build. The output lands in dist/ which
# is the only artifact carried into the production image.
FROM deps AS builder
ENV NODE_OPTIONS=--max-old-space-size=4096
COPY ./ ./
RUN \
  if [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm run build; \
  elif [ -f yarn.lock ]; then yarn run build; \
  elif [ -f package-lock.json ]; then npm run build; \
  else echo "Lockfile not found." && exit 1; \
  fi

# ---- Development ----
# Full Node environment with all deps + source for local dev (hot reload).
# Uses docker-entrypoint.sh to auto-detect the package manager and run "dev".
FROM deps AS dev
ENV NODE_ENV="development"
COPY ./ ./
RUN apk add --no-cache curl
RUN chmod +x docker-entrypoint.sh
ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["dev"]

# ---- Production ----
# Minimal Nginx image that serves the static dist/ output. No Node.js runtime
# is present — this image only contains the built HTML/JS/CSS assets.
FROM ${NGINX} AS prod
ARG APP_UID
ARG APP_GID
ARG APP_USERNAME
ARG APP_GROUPNAME
ARG APP_DIR
ARG PORT

ENV PORT=${PORT}

RUN apk upgrade --no-cache \
    && mkdir -p /run \
    && addgroup -g ${APP_GID} ${APP_GROUPNAME} \
    && adduser -S -u ${APP_UID} -s /sbin/nologin -G ${APP_GROUPNAME} ${APP_USERNAME} \
    && chown -R ${APP_UID}:${APP_GID} /run /var/cache/nginx /etc/nginx \
    && chmod -R 755 /run /var/cache/nginx /etc/nginx \
    && rm /etc/nginx/conf.d/default.conf

COPY --chown=${APP_UID}:${APP_GID} --from=builder ${APP_DIR}/dist /usr/share/nginx/html
COPY --chown=${APP_UID}:${APP_GID} ./nginx.conf.template /etc/nginx/templates/nginx.conf.template

EXPOSE ${PORT}
USER ${APP_UID}

CMD ["nginx", "-g", "daemon off;"]
