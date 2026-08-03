# Use a modern, supported Python version to eliminate Trivy vulnerabilities
FROM python:3.11-slim 

# Create a non-root user and group
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Copy the requirements file and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code
COPY . /app

# Change ownership of the application directory to the non-root user
RUN chown -R appuser:appuser /app

# Switch to the non-root user before running the application
USER appuser

EXPOSE 5002

CMD ["python", "-m", "flask", "run", "--host=0.0.0.0", "--port=5002"]