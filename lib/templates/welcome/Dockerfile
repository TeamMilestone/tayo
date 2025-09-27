FROM nginx:alpine

# Nginx 설정
RUN echo 'server { listen 80; root /usr/share/nginx/html; index index.html; location / { try_files $uri $uri/ =404; } }' > /etc/nginx/conf.d/default.conf

# HTML 파일 복사
COPY index.html /usr/share/nginx/html/

# 헬스체크
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3   CMD wget --no-verbose --tries=1 --spider http://localhost || exit 1

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
