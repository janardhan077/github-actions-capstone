# ─── Stage 1: Build (if using a bundler, extend here) ────────────────────────
# For this project the frontend is plain HTML/CSS/JS, so no build step needed.
# If you add React/Vite later, add the npm build stage here.

# ─── Stage 2: Serve with Nginx ────────────────────────────────────────────────
FROM nginx:1.25-alpine

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom nginx site config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy static frontend files
COPY index.html /usr/share/nginx/html/index.html

# Non-root: nginx worker already runs as nginx user by default in Alpine image

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
