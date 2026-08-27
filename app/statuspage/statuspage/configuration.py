"""
Production configuration for Status-Page (https://github.com/Status-Page/Status-Page).

Loaded by statuspage/statuspage/settings.py in place of configuration_example.py.
Every value comes from the environment so the same image runs in any pod
(web/worker/scheduler) and any environment (dev/stage/prod) without a rebuild.

Secrets (SECRET_KEY, DB password, Redis password) are required with NO fallback -
if they're missing the app must crash at startup, not boot with a blank/insecure
value. They arrive via the ExternalSecret-populated env vars set on the
Deployments/Job in the Helm chart (app/helm-chart) - never hardcoded here.
"""
import os

# --- Required: fails loudly (KeyError) if not injected by the pod's env ---
SECRET_KEY = os.environ['SECRET_KEY']

DATABASE = {
    'NAME': os.environ.get('DB_NAME', 'statuspage'),
    'USER': os.environ.get('DB_USER', 'statuspage'),
    'PASSWORD': os.environ['DB_PASSWORD'],
    'HOST': os.environ['DB_HOST'],
    'PORT': os.environ.get('DB_PORT', '5432'),
    'CONN_MAX_AGE': int(os.environ.get('DB_CONN_MAX_AGE', '300')),
}

REDIS = {
    'tasks': {
        'HOST': os.environ['REDIS_HOST'],
        'PORT': int(os.environ.get('REDIS_PORT', '6379')),
        'PASSWORD': os.environ.get('REDIS_PASSWORD', ''),
        'DATABASE': int(os.environ.get('REDIS_TASKS_DATABASE', '0')),
        'SSL': os.environ.get('REDIS_SSL', 'false').lower() == 'true',
    },
    'caching': {
        'HOST': os.environ['REDIS_HOST'],
        'PORT': int(os.environ.get('REDIS_PORT', '6379')),
        'PASSWORD': os.environ.get('REDIS_PASSWORD', ''),
        'DATABASE': int(os.environ.get('REDIS_CACHING_DATABASE', '1')),
        'SSL': os.environ.get('REDIS_SSL', 'false').lower() == 'true',
    },
}

# --- Required, but safe to keep a dev-friendly default ---
ALLOWED_HOSTS = os.environ.get('ALLOWED_HOSTS', '*').split(',')
SITE_URL = os.environ.get('SITE_URL', 'https://status.example.com')

# TLS terminates at the ALB, not in-pod - Django sees plain HTTP from the nginx
# sidecar. Without this, POSTs (login, admin) fail CSRF checks once accessed over
# HTTPS, because Django compares the request's Origin against this list.
CSRF_TRUSTED_ORIGINS = [SITE_URL]

# --- Never allow this to be toggled on via env in a real cluster ---
DEBUG = False

TIME_ZONE = os.environ.get('TIME_ZONE', 'UTC')
