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
# THIS FIXES THE LAST 2 TRIVY VULNERABILITIES
# ==========================================
# Force the upgrade of vulnerable build dependencies before installing requirements
RUN pip install --no-cache-dir --upgrade wheel>=0.46.2 jaraco.context>=6.1.0
# ==========================================

# Install application dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code
COPY . /app

# Change ownership of the application directory to the non-root user
RUN chown -R appuser:appuser /app

# Switch to the non-root user before running the application
USER appuser

EXPOSE 5002

CMD ["python", "-m", "flask", "run", "--host=0.0.0.0", "--port=5002"]