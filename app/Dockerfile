# Builds the Status-Page (https://github.com/Status-Page/Status-Page) web/worker/scheduler
# image. All three roles (gunicorn web, rqworker, rqscheduler) share this one image -
# the Helm chart (app/helm-chart) selects the role via `command`/`args` on each Deployment.
#
# Static files are NOT served from this image. Upstream ships no whitenoise dependency
# and its own contrib/nginx.conf expects a reverse proxy in front of gunicorn - so the
# Helm chart puts an nginx:alpine sidecar in the web pod, sharing STATIC_ROOT via an
# emptyDir volume. See app/helm-chart's web deployment for that wiring.

ARG STATUS_PAGE_VERSION=v2.5.1

FROM python:3.12-slim AS builder
ARG STATUS_PAGE_VERSION

RUN apt-get update \
    && apt-get install -y --no-install-recommends git build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Pinned tag, not a floating branch - reproducible builds, no surprise upstream changes.
RUN git clone --branch "${STATUS_PAGE_VERSION}" --depth 1 \
    https://github.com/Status-Page/Status-Page.git /opt/status-page

RUN python -m venv /venv
ENV PATH="/venv/bin:${PATH}"
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /opt/status-page/requirements.txt


FROM python:3.12-slim
ARG STATUS_PAGE_VERSION
LABEL org.opencontainers.image.source="https://github.com/Status-Page/Status-Page" \
      org.opencontainers.image.version="${STATUS_PAGE_VERSION}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq5 \
    && rm -rf /var/lib/apt/lists/* \
    && addgroup --system statuspage \
    && adduser --system --ingroup statuspage --home /opt/status-page --shell /usr/sbin/nologin statuspage

COPY --from=builder /venv /venv
COPY --from=builder --chown=statuspage:statuspage /opt/status-page /opt/status-page

# Our production settings module - overwrites the upstream configuration_example.py location.
COPY --chown=statuspage:statuspage statuspage/statuspage/configuration.py \
    /opt/status-page/statuspage/statuspage/configuration.py

ENV PATH="/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /opt/status-page/statuspage

# Build-time-only env so collectstatic (no DB/Redis access needed) can import settings.py,
# which requires these attributes to exist on the configuration module. Real values are
# injected by the pod at runtime via the ExternalSecret - these placeholders never run there.
RUN SECRET_KEY=build-time-placeholder-not-used-at-runtime \
    DB_HOST=build-time-placeholder DB_PASSWORD=build-time-placeholder \
    REDIS_HOST=build-time-placeholder \
    python manage.py collectstatic --noinput

USER statuspage
EXPOSE 8001

# Matches upstream's own contrib/gunicorn.py bind address - localhost only, a proxy
# (the nginx sidecar) is expected in front. Helm chart overrides this CMD for
# worker (`manage.py rqworker high default low`) and scheduler (`manage.py rqscheduler`).
CMD ["gunicorn", "--bind", "127.0.0.1:8001", "--workers", "5", "--threads", "3", \
     "--timeout", "120", "--max-requests", "5000", "--max-requests-jitter", "500", \
     "statuspage.wsgi:application"]
