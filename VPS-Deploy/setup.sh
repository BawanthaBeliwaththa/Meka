#!/bin/bash
set -e

echo "🤖 Project MEKA - VPS Auto-Deployment Script"
echo "==========================================="

# Check for git
if ! command -v git &> /dev/null; then
    echo "Installing git..."
    sudo apt-get update && sudo apt-get install -y git
fi

# Check for docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
fi

echo "Cloning MEKA Server Repositories..."
git clone https://gitlab.com/project-meka/Future-AI.git || true
git clone https://gitlab.com/project-meka/Webapp.git || true
git clone https://gitlab.com/project-meka/Telegram.git || true

echo "Setting up environment template..."
if [ ! -f .env ]; then
    cat <<EOT >> .env
# MEKA Global Environment Variables
TELEGRAM_BOT_TOKEN=your_telegram_bot_token_here
ADMIN_TELEGRAM_ID=your_telegram_user_id
VITE_FIREBASE_API_KEY=your_firebase_api_key
EOT
    echo "Created .env template."
fi

if [ ! -f ./Telegram/firebase-adminsdk.json ]; then
    echo "{}" > ./Telegram/firebase-adminsdk.json
    echo "Created blank firebase-adminsdk.json template. Please paste your actual service account keys here."
fi

echo ""
echo "✅ Setup Complete!"
echo "Before starting the server, please edit:"
echo "  1. .env (Add your tokens)"
echo "  2. Telegram/firebase-adminsdk.json (Add your Firebase service account key)"
echo ""
echo "Once configured, start MEKA by running:"
echo "  docker compose up -d --build"
