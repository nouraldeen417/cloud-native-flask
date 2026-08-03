# Use a modern, supported Python version to eliminate Trivy vulnerabilities
FROM python:3.11-slim 

# Create a non-root user and group
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Install OS-level dependencies required to build the old MySQL Python packages
RUN apt-get update && apt-get install -y \
    pkg-config \
    default-libmysqlclient-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy the requirements file
COPY requirements.txt .

# ==========================================
# THE FIX: ENFORCE CONSTRAINTS IN A SINGLE LAYER
# ==========================================
# 1. Create a constraints file with the secure versions
# 2. Upgrade pip
# 3. Install requirements using the constraints file so vulnerable versions are never downloaded
RUN echo "setuptools>=78.1.1" > constraints.txt && \
    echo "msgpack>=1.2.1" >> constraints.txt && \
    echo "wheel>=0.46.2" >> constraints.txt && \
    echo "jaraco.context>=6.1.0" >> constraints.txt && \
    pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -c constraints.txt -r requirements.txt
# ==========================================

# Copy the application code
COPY . /app

# Change ownership of the application directory to the non-root user
RUN chown -R appuser:appuser /app

# Switch to the non-root user before running the application
USER appuser

EXPOSE 5002

CMD ["python", "-m", "flask", "run", "--host=0.0.0.0", "--port=5002"]