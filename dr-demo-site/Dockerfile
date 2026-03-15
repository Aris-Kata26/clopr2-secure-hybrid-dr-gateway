FROM nginx:1.27-alpine

# Remove default nginx page
RUN rm -rf /usr/share/nginx/html/*

# Copy site files
COPY site/ /usr/share/nginx/html/

# Minimal nginx config: serve index.html, no unnecessary modules
RUN printf 'server {\n\
    listen 80;\n\
    server_name localhost;\n\
    root /usr/share/nginx/html;\n\
    index index.html;\n\
    charset utf-8;\n\
    add_header Cache-Control "no-cache, no-store, must-revalidate";\n\
    location / {\n\
        try_files $uri $uri/ /index.html;\n\
    }\n\
    location ~* \\.(html|css|js)$ {\n\
        expires -1;\n\
    }\n\
}\n' > /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -q --spider http://localhost/ || exit 1
