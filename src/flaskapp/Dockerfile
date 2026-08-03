# Use a modern, supported Python version
FROM python:3.11-slim 

# Create a non-root user and group
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Install OS-level dependencies required to build legacy MySQL packages
RUN apt-get update && apt-get install -y \
    pkg-config \
    default-libmysqlclient-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# ==========================================
# 1. INSTALL REQUIREMENTS 
# ==========================================
RUN pip install --no-cache-dir -r requirements.txt

# ==========================================
# 2. POST-INSTALL SECURITY OVERWRITE
# ==========================================
# Forcefully upgrade ALL flagged packages to their secure versions
# as the final package-management step.
RUN pip install --no-cache-dir --upgrade \
    "setuptools>=83.0.0" \
    "msgpack>=1.2.1" \
    "wheel>=0.46.2" \
    "jaraco.context>=6.1.0"
# ==========================================

# Copy the application code
COPY . /app

# Change ownership of the application directory to the non-root user
RUN chown -R appuser:appuser /app

# Switch to the non-root user before running the application
USER appuser

EXPOSE 5002

CMD ["python", "-m", "flask", "run", "--host=0.0.0.0", "--port=5002"]