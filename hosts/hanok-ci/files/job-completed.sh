#!/usr/bin/env bash
# Runs after every job (ACTIONS_RUNNER_HOOK_JOB_COMPLETED, set in each runner's .env by add-repo.sh).
# Removes what a job left behind in Docker. Two runners share this Docker, so it only removes what nobody uses:
# stopped containers, and volumes and networks no container uses. A running container belongs to the other
# runner's job and is kept; the runner already removes its own service containers (Postgres) at the end of a job.
# Never fails the job: cleanup problems are logged and ignored.
docker container prune --force --filter "until=1m" >/dev/null 2>&1 || echo "job-completed: container prune failed"
docker volume prune --force >/dev/null 2>&1 || echo "job-completed: volume prune failed"
docker network prune --force --filter "until=1m" >/dev/null 2>&1 || echo "job-completed: network prune failed"
exit 0
