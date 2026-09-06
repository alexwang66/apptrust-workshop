# Follows jfrog-sample/apptrust-sample: Node HTTP service, port 3000.
FROM alpine:3.22 AS jars
RUN apk add --no-cache curl
WORKDIR /jars
RUN set -eu; for artifact in log4j-api log4j-core; do \
      name="$artifact-2.24.1.jar"; \
      url="https://repo.maven.apache.org/maven2/org/apache/logging/log4j/$artifact/2.24.1/$name"; \
      curl -fsSLo "$name" "$url"; \
      curl -fsSLo "$name.sha512" "$url.sha512"; \
      printf '%s  %s\n' "$(cat "$name.sha512")" "$name" | sha512sum -c -; \
    done
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
ARG APP_VERSION=local
ENV APP_VERSION=$APP_VERSION
COPY --chown=node:node app/ ./app/
COPY --from=jars /jars/*.jar /app/lib/
USER node
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD wget --spider -q http://127.0.0.1:3000/healthz || exit 1
CMD ["node", "app/server.js"]
