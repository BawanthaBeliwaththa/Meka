# MEKA VPS Deployment — Troubleshooting 404 Page Not Found

If `https://meka.starlight-coders.site/api/status` shows **Page Not Found (404)**, follow these 2 quick steps to fix it:

---

## 🛠️ Step 1: Force HestiaCP to Load Nginx Rules (Fixes 404)

HestiaCP requires you to trigger a reload so it detects `nginx.ssl.conf_meka`:

1. In HestiaCP File Manager, verify that `nginx.ssl.conf_meka` exists at:
   `/home/bawantha/conf/web/meka.starlight-coders.site/nginx.ssl.conf_meka`
2. Go to **HestiaCP Web Control Panel** → click **WEB** tab.
3. Hover over `meka.starlight-coders.site` and click the **✏️ Edit (Pencil)** icon.
4. Without changing anything, scroll down and click **Save**!
   *(This forces HestiaCP to include your custom Nginx file and reload Nginx).*

---

## 🛠️ Step 2: Start Python Backend & Check Log

1. In HestiaCP → **CRON** tab → click **▶ Run** on your Cron job:
   `bash /home/bawantha/web/meka.starlight-coders.site/public_html/backend/run_backend.sh`
   *(Or wait 2 minutes for Cron to run automatically).*
2. `run_backend.sh` auto-installs any missing python packages and starts `hub_server.py`.
3. Open HestiaCP File Manager and check:
   `/home/bawantha/web/meka.starlight-coders.site/public_html/backend/hub.log`
   *(It will display `MEKA IoT Hub launched successfully`).*

---

## 🌐 Test Live Endpoints
Once saved:
- **API Status**: `https://meka.starlight-coders.site/api/status` → returns `{"hub": "meka-iot-hub", ...}`
- **Phone Bridge**: `https://meka.starlight-coders.site/phone-bridge` → opens Neural Body Node UI
- **Admin Panel**: `https://meka.starlight-coders.site` → opens MEKA Control Center
