FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
RUN useradd --uid 1000 --create-home appuser
USER appuser
EXPOSE 5000
CMD ["python", "app.py"]
