#!/usr/bin/env python3
"""
Wires django-prometheus into the vendored upstream Status-Page source
(cloned fresh at build time - see app/Dockerfile). We don't own settings.py
or urls.py, so this patches four exact, narrow anchors instead of shipping
replacement copies of those files. Each anchor must match exactly once;
if upstream changes any of them (e.g. on a version bump), this fails the
build loudly instead of silently no-opping and shipping an image with
metrics quietly missing.

Run against a checkout of statuspage/statuspage/{settings,urls}.py:
    python3 enable_prometheus_metrics.py <path-to-checkout>/statuspage/statuspage
"""
import sys
from pathlib import Path


def apply_one(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        sys.exit(
            f"enable_prometheus_metrics: expected exactly one match for "
            f"'{label}' in {path}, found {count}. Upstream source has "
            f"likely changed - update the anchor in this script."
        )
    path.write_text(text.replace(old, new, 1))


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: enable_prometheus_metrics.py <statuspage-package-dir>")

    pkg_dir = Path(sys.argv[1])
    settings_py = pkg_dir / "settings.py"
    urls_py = pkg_dir / "urls.py"

    # 1. Register the app.
    apply_one(
        settings_py,
        "INSTALLED_APPS = [\n    'django.contrib.admin',",
        "INSTALLED_APPS = [\n    'django_prometheus',\n    'django.contrib.admin',",
        "INSTALLED_APPS opening entry",
    )

    # 2. Before-middleware must be first - it starts the request timer.
    apply_one(
        settings_py,
        "MIDDLEWARE = [\n    'django.middleware.security.SecurityMiddleware',",
        "MIDDLEWARE = [\n    'django_prometheus.middleware.PrometheusBeforeMiddleware',\n"
        "    'django.middleware.security.SecurityMiddleware',",
        "MIDDLEWARE opening entry",
    )

    # 3. After-middleware must be last - it records the response and stops the timer.
    apply_one(
        settings_py,
        "    'statuspage.middleware.DynamicConfigMiddleware',\n]",
        "    'statuspage.middleware.DynamicConfigMiddleware',\n"
        "    'django_prometheus.middleware.PrometheusAfterMiddleware',\n]",
        "MIDDLEWARE closing entry",
    )

    # 4. Swap the DB backend so query counts/durations get instrumented too.
    apply_one(
        settings_py,
        "'ENGINE': 'django.db.backends.postgresql',",
        "'ENGINE': 'django_prometheus.db.backends.postgresql',",
        "DATABASES ENGINE",
    )

    # 5. Expose the collected metrics for Prometheus to scrape.
    apply_one(
        urls_py,
        "    path('media/<path:path>', serve, {'document_root': settings.MEDIA_ROOT}),\n",
        "    path('media/<path:path>', serve, {'document_root': settings.MEDIA_ROOT}),\n\n"
        "    # Scraped in-cluster by Prometheus via the chart's ServiceMonitor.\n"
        "    path('metrics/', include('django_prometheus.urls')),\n",
        "urls.py media path",
    )


if __name__ == "__main__":
    main()
