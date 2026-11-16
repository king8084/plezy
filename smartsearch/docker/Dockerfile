# Plezy smart search: runtime only. The application code is NOT baked in; it is
# mounted read-only from smartsearch/code so updates never require replacing
# this container (owner rule: nothing on Unraid is ever deleted).
FROM python:3.14-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONPATH=/code
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-deps --require-hashes --only-binary=:all: -r /tmp/requirements.txt
USER 99:100
EXPOSE 8787
HEALTHCHECK --interval=60s --timeout=5s --start-period=60s CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8787/v1/ping',timeout=4)"
ENTRYPOINT ["python", "-m", "plezy_search.service", "--code", "/code", "--config", "/config/service.json", "--data", "/data"]
