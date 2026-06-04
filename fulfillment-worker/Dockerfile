FROM python:3.9-slim
WORKDIR /app

# Install procps for liveness probe (ps command)
RUN apt-get update && apt-get install -y procps && rm -rf /var/lib/apt/lists/* 
#propcps:Linux software package providing essential command-line utilities for monitoring system processes, memory, and performance, such as ps, top, free, kill, and vmstat

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .

EXPOSE 8002

CMD ["python", "-u", "main.py"]