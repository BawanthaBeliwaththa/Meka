# MEKA VPS Deployment — meka.starlight-coders.site

Everything is packaged to upload directly into your HestiaCP `public_html` folder using your user account **`bawantha`**!

---

## 📁 Files Prepared in `VPS-Deploy` Folder
1. **`webapp_dist.zip`** — Contains all compiled React frontend files.
2. **`backend.zip`** — Contains the `backend/` folder with Python IoT Hub & `run_backend.sh`.
3. **`nginx.meka.starlight-coders.site.conf`** — Nginx reverse proxy custom directives.

---

## 🔷 Step-by-Step Deployment

### Step 1: Create Subdomain in HestiaCP
1. Log into your **HestiaCP Panel**.
2. Go to **WEB** tab → click **➕ Add Domain**.
3. Enter Domain: `meka.starlight-coders.site`
4. Check **Enable SSL (Let's Encrypt)** ✅
5. Click **Save**.

---

### Step 2: Upload Files to `public_html`
1. Open **HestiaCP File Manager**.
2. Navigate to:
   `/home/bawantha/web/meka.starlight-coders.site/public_html/`
3. Upload **`webapp_dist.zip`** and extract it directly inside `public_html/`.
4. Upload **`backend.zip`** and extract it directly inside `public_html/`.
   - Your `public_html/` folder will now look like:
     - `index.html` (React Frontend)
     - `assets/`
     - `backend/` (Python Hub Backend)

---

### Step 3: Configure Nginx Reverse Proxy (Fixed Duplicate Location Error)
1. In HestiaCP File Manager, navigate to:
   `/home/bawantha/conf/web/meka.starlight-coders.site/`
2. Create or edit the file: `nginx.ssl.conf_meka`
3. Replace its contents with the text from [nginx.meka.starlight-coders.site.conf](file:///d:/Projects/Meka/VPS-Deploy/nginx.meka.starlight-coders.site.conf).
   *(Note: `location /` has been removed to avoid duplicate location errors with HestiaCP's built-in template).*
4. Test and restart Nginx:
   ```bash
   sudo nginx -t
   sudo systemctl restart nginx
   ```

---

### Step 4: Keep Backend Running 24/7 (HestiaCP Cron)
1. In HestiaCP, click the **CRON** tab.
2. Click **➕ Add Job**.
3. Set the fields:
   - **Minute**: `*/2`
   - **Hour**: `*`
   - **Day**: `*`
   - **Month**: `*`
   - **Weekday**: `*`
   - **Command**:
     ```bash
     bash /home/bawantha/web/meka.starlight-coders.site/public_html/backend/run_backend.sh
     ```
4. Click **Add**.

---

## 🌐 Live URLs After Deployment
| Service | URL |
|---|---|
| **MEKA Admin Panel** | `https://meka.starlight-coders.site` |
| **Phone Bridge** | `https://meka.starlight-coders.site/phone-bridge` |
| **IoT Hub API** | `https://meka.starlight-coders.site/api/status` |
