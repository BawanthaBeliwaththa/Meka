# MEKA VPS File Upload Deployment Guide (No Terminal Required)

Hosting on: **`https://starlight-coders.site/Meka`**

Since your VPS already has an active SSL certificate (Let's Encrypt / Cloudflare SSL), Nginx will handle SSL termination at the edge, and proxy internally over HTTP (`http://127.0.0.1:5000`). Internal services do **NOT** need secondary SSL certs!

---

## 📁 Step 1: Upload Built WebApp Files
1. Open your local project folder: `d:\Projects\Meka\webapp\dist`.
2. Upload all files inside `dist` to your VPS web folder (e.g. `/var/www/meka` or `public_html/Meka`) using your VPS File Manager, cPanel, or FileZilla SFTP.

---

## ⚙️ Step 2: Update Nginx Configuration
Open your Nginx website configuration file in your VPS panel or File Manager and paste the contents of [`nginx_starlight.conf`](file:///d:/Projects/Meka/VPS-Deploy/nginx_starlight.conf):

```nginx
location /Meka {
    alias /var/www/meka;
    index index.html;
    try_files $uri $uri/ /Meka/index.html;
}

location /api/ {
    proxy_pass http://127.0.0.1:5000/api/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
}

location /phone-bridge {
    proxy_pass http://127.0.0.1:5000/phone-bridge;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
}

location /socket.io/ {
    proxy_pass http://127.0.0.1:5000/socket.io/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
}
```

---

## 🐍 Step 3: Upload IoT Hub & Python Backend
Upload the contents of `d:\Projects\Meka\Future (AI)\iot_hub` to `/var/www/meka_backend` on your VPS.

---

## 🔑 Permissions & Folder Access Checklist
- **Folder Permissions**: `755` (Read & Execute for web server).
- **File Permissions**: `644` (Read access for static files).
- **No Internal SSL Required**: The IoT Hub runs internally on port `5000` (HTTP). Nginx proxies `https://starlight-coders.site` securely.
