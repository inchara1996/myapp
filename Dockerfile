# Dockerfile
FROM python:3.11-slim

# Set working directory inside the container
WORKDIR /app

# Copy requirements first (Docker caches this layer)
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the app
COPY app.py .

# Expose the port the app runs on
EXPOSE 5000

# Command to start the app
CMD ["python", "app.py"]
