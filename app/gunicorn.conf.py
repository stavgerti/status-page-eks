from prometheus_client import multiprocess


def child_exit(server, worker):
    # gunicorn recycles workers via --max-requests. Without this, each
    # recycled worker's metrics file is left behind in
    # PROMETHEUS_MULTIPROC_DIR forever, and the /metrics scrape keeps
    # aggregating dead workers alongside live ones.
    multiprocess.mark_process_dead(worker.pid)
