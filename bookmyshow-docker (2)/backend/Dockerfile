
FROM node:20-alpine AS deps

WORKDIR /app


COPY package.json package-lock.json* ./


RUN npm ci --only=production && npm cache clean --force


FROM node:20-alpine AS development

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

COPY . .

EXPOSE 5000
CMD ["npm", "run", "dev"]


FROM node:20-alpine AS production


RUN addgroup -g 1001 -S nodejs && \
    adduser  -S nodeuser -u 1001

WORKDIR /app


COPY --from=deps --chown=nodeuser:nodejs /app/node_modules ./node_modules


COPY --chown=nodeuser:nodejs . .


USER nodeuser

EXPOSE 5000


HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD wget -qO- http://localhost:5000/api/health || exit 1

CMD ["node", "server.js"]
