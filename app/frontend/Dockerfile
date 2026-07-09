# nginx-unprivileged listens on 8080 and runs as uid 101 out of the box, so
# runAsNonRoot: true in deployment-frontend.yaml is real, not a workaround.
FROM nginxinc/nginx-unprivileged:1.25-alpine

RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY public/ /usr/share/nginx/html/

EXPOSE 8080
