# 🚀 Meka: Video Script, Play Store Publishing & Monetization Guide

This guide provides everything you need to showcase Meka to the world, publish it to the Google Play Store, and maximize adoption and sales.

---

## 🎬 90-Second Promotional Video Script
*Target: YouTube Shorts / TikTok / Reels / GitHub Project Showcase*

**Tone:** Cinematic, futuristic, high-energy, premium (like a Marvel or tech product launch).
**Music:** Synthesizer-heavy, upbeat electronic, or cinematic orchestral (similar to Hans Zimmer or Tron Legacy).

| Time | Visual Scene | Audio Voiceover (VO) / Action |
|:---|:---|:---|
| **0:00 - 0:10** | Open with a dramatic close-up of an Android phone screen in dark mode. The glowing cyan Siri-style waveform is pulsing smoothly. | **VO:** "Meet the Android answer to Siri. A fully customizable, open-source AI companion that puts a personal JARVIS right in your pocket." |
| **0:10 - 0:20** | Cut to a user saying: *"Hey Meka, turn on the studio lights."* Fast transition to a physical desk setup where a relay clicks and LED light panels turn on instantly. | **VO:** "This is Meka. An advanced AI personal assistant built with Flutter, powered by Google Gemini, and integrated with physical hardware." |
| **0:20 - 0:35** | Screen recording showing the home screen chat interface with custom typography, glowing HUD elements, and fast response times. Show voice transcription happening in real-time. | **VO:** "Unlike standard assistant utilities, Meka has contextual conversation memory, deep device integration, and a completely offline fallback mode that keeps working even when your internet drops." |
| **0:35 - 0:50** | Zoom in on an ESP32 microchip sitting on a breadboard. Show a wiring schematic graphic overlay, then show the Meka Settings screen testing connection to `meka.local` (green ONLINE badge). | **VO:** "But here is the real superpower. Meka communicates directly with ESP32 microcontrollers over local WiFi. Control relays, servos, analog sensors, and RGB light strips with simple voice commands." |
| **0:50 - 1:10** | Show rapid montage of voice control features: <br>1. Calling a contact<br>2. Reading text files<br>3. Adjusting device volume<br>4. Moving a servo motor | **VO:** "From raw system APIs like making calls and setting alarms, to reading system files and executing physical commands, Meka bridges the gap between digital AI and the physical world." |
| **1:10 - 1:20** | Text overlay on screen: *100% Secure. Private API Keys. Fully Open Source.* Show the GitHub repository page with stars popping up. | **VO:** "Your data, your control. Meka stores your Gemini API key locally on your device. No third-party servers. Complete security." |
| **1:20 - 1:30** | Call to action screen showing the GitHub URL and a Play Store Mockup. | **VO:** "Ready to upgrade your Android experience? Star the project on GitHub, download the app, and start building your own JARVIS today." |

---

## 📱 Google Play Store Publishing Guide

To publish Meka on the Google Play Store, you need to sign the app with a secure production key and generate an Android App Bundle (`.aab`) instead of an APK.

### Step 1: Create a Google Play Console Account
1. Visit the [Google Play Console](https://play.google.com/console/signup).
2. Register as a developer (requires a one-time $25 USD registration fee).
3. Complete your identity verification.

### Step 2: Generate a Secure Upload Keystore
Run the following command in your terminal to generate a secure keystore file:

```powershell
keytool -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias key
```
> [!IMPORTANT]
> Save the password you choose. Keep the `upload-keystore.jks` file secure and **never** commit it to public version control (it is already ignored in `.gitignore`).

### Step 3: Configure Flutter signing
Create a file named `android/key.properties` on your local machine containing:

```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=key
storeFile=upload-keystore.jks
```

Update your `android/app/build.gradle` to load this file and sign the build:

```groovy
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    ...
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

### Step 4: Build the Android App Bundle
Run this command to build the production `.aab` file:
```bash
flutter build appbundle --release
```
The output file will be saved to:
`build/app/outputs/bundle/release/app-release.aab`

### Step 5: Complete Play Console Tasks
1. Set up your Store Listing: Upload high-res screenshots (using the ones we generated!), custom icon, and write an SEO-optimized description emphasizing the Gemini AI and ESP32 home automation.
2. Complete the **Content Rating** questionnaire.
3. Upload a **Privacy Policy** (required because the app requests microphone and call permissions).
4. Upload your `.aab` file to a testing track (Internal or Closed testing) first, recruit testers, then promote to production.

---

## 📈 Monetization & Sales Strategy

Since Meka is open-source, here are the most effective ways to drive revenue and maximize "sales" (both downloads and monetary income):

### 1. The "Freemium" Model (App Store)
*   **Free Version:** Includes standard offline voice commands, basic device skills, and standard chat.
*   **Pro Upgrade ($2.99 - $4.99):** Unlock premium features:
    *   Unlimited Gemini API requests (using your host key instead of requiring their own).
    *   Advanced ESP32 widgets and layout customizations.
    *   Voice voiceprints (voice recognition security) to make sure only the owner can trigger physical devices.

### 2. Sell Pre-built Hardware Kits (The Big Money Maker)
Most IoT enthusiasts love the idea of voice control but don't want to wire up breadboards themselves.
*   **Package a "Meka Smart Node":** Sell an elegant, 3D-printed enclosure containing an ESP32 pre-soldered to a relay bank and status LEDs.
*   **Pricing:** A $5 ESP32 + $5 relay module inside a nice $2 plastic shell can easily be sold for **$29.99 - $39.99** as a plug-and-play Meka Smart Home kit.
*   Link to your store directly from the app's Settings page!

### 3. SEO Optimization for App Store Visibility
Maximize search engine discovery with these targeted keywords in your store metadata:
*   **Title:** Meka: JARVIS AI Assistant
*   **Subtitle:** Android Siri Alternative, Smart Home Voice Control
*   **Description focus:**
    *   *“A powerful open-source Siri alternative for Android devices.”*
    *   *“Control your smart home without cloud dependency using ESP32 integration.”*
    *   *“Bring your own Gemini API key for complete local privacy.”*

### 4. Sponsor & Donation Tiers
*   Add a **"Buy Me a Coffee"** or **GitHub Sponsors** button on the Settings screen.
*   Acknowledge sponsors in the repository's README.md file.
