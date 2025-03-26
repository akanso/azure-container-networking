FROM python:3.9-slim
WORKDIR /app
COPY appinsights.py /appinsights.py
RUN pip install opencensus-ext-azure
CMD ["python3", "/appinsights.py"]
