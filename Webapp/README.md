# MEKA Cybernetic Dashboard: Web UI

This repository houses the visual command center for **Project MEKA**. 

Built to defy generic web design norms, the MEKA Webapp utilizes a hyper-modern, immersive **Cyberpunk aesthetic**, characterized by deep neon glows, glassmorphism, dynamic micro-animations, and high-contrast telemetry panels.

## Core Responsibilities & Features

### 1. Live Telemetry Rendering
The application establishes a real-time WebSocket connection to the MEKA Firebase backend. As hardware sensors on the ESP32 detect changes (temperature, proximity, ambient light), the Webapp instantly reflects these metrics through animated React components without requiring a page refresh.

### 2. Dual-Layered Interface
- **User Panel (`UserPanel.jsx`):** A streamlined interface allowing standard users to view MEKA's current status, read the latest conversational outputs, and interact with basic settings.
- **Admin Panel (`AdminPanel.jsx`):** A secure, advanced dashboard for system administrators. It grants access to low-level hardware overrides, API key management, and direct database manipulations.

### 3. Responsive & Immersive UI
Every interactive element is designed to provide immediate visual feedback. Hover states, routing transitions, and status toggles are accompanied by subtle CSS animations to ensure the interface feels alive and responsive.

## Technical Stack
- **Core Framework:** React 18+ 
- **Build Tool:** Vite (for blazing fast HMR and optimized production bundling)
- **State & Cloud:** Firebase Web SDK (`firebase/app`, `firebase/database`)
- **Styling:** Vanilla CSS3 emphasizing CSS Variables for strict design token management (neon colors, blur filters, custom fonts).
