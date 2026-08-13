FROM python:3.10-slim

WORKDIR /app

# Install system dependencies needed for OpenCV, Bleak, etc.
RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1-mesa-glx \
    bluez \
    && rm -rf /var/lib/apt/lists/*

COPY iot_hub/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY iot_hub/ .

# Expose the Flask port
EXPOSE 5000

# Run the Hub Server
CMD ["python", "hub_server.py"]
