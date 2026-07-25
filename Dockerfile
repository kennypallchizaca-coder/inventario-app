# Etapa 1: instalar dependencias y ejecutar pruebas
FROM node:22-alpine AS build-test

WORKDIR /app

COPY package*.json ./

RUN npm ci

COPY server.js ./
COPY db.js ./
COPY server.test.js ./
COPY public ./public
COPY data ./data

RUN npm test


# Etapa 2: imagen final
FROM node:22-alpine AS runtime

ENV NODE_ENV=production
ENV PORT=3000
ENV APP_VERSION=v1
ENV APP_COLOR=blue

WORKDIR /app

COPY --from=build-test --chown=node:node /app/node_modules ./node_modules
COPY --from=build-test --chown=node:node /app/package*.json ./
COPY --from=build-test --chown=node:node /app/server.js ./
COPY --from=build-test --chown=node:node /app/db.js ./
COPY --from=build-test --chown=node:node /app/public ./public

RUN mkdir -p /app/data && chown -R node:node /app

USER node

EXPOSE 3000

CMD ["node", "server.js"]