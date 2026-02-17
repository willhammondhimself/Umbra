"""Load test: 100 concurrent users, target p95 < 200ms.

Run:
    locust -f tests/performance/locustfile.py --headless \
        -u 100 -r 10 --run-time 2m \
        --host http://localhost:8000
"""

import uuid
from datetime import datetime, timezone

from locust import HttpUser, between, task


class TetherUser(HttpUser):
    """Simulates a typical Tether user workflow."""

    wait_time = between(1, 3)

    def on_start(self):
        """Each virtual user gets a fake JWT for testing.

        In a real load test, override get_current_user on the server
        or use a test-mode JWT issuer.
        """
        self.headers = {
            "Authorization": "Bearer test-load-token",
            "Content-Type": "application/json",
        }
        self.project_id = None
        self.task_ids = []
        self.session_id = None

    @task(3)
    def create_and_list_tasks(self):
        resp = self.client.post(
            "/tasks",
            json={"title": f"Load test task {uuid.uuid4().hex[:8]}", "priority": 1},
            headers=self.headers,
        )
        if resp.status_code == 201:
            self.task_ids.append(resp.json()["id"])

        self.client.get("/tasks", headers=self.headers)

    @task(2)
    def session_workflow(self):
        now = datetime.now(timezone.utc).isoformat()

        resp = self.client.post(
            "/sessions",
            json={"start_time": now},
            headers=self.headers,
        )
        if resp.status_code != 201:
            return
        sid = resp.json()["id"]

        self.client.post(
            f"/sessions/{sid}/events",
            json={
                "events": [
                    {"event_type": "START", "timestamp": now},
                    {"event_type": "DISTRACTION", "timestamp": now, "app_name": "Slack", "duration_seconds": 15},
                    {"event_type": "STOP", "timestamp": now},
                ]
            },
            headers=self.headers,
        )

        self.client.patch(
            f"/sessions/{sid}",
            json={
                "end_time": now,
                "duration_seconds": 1800,
                "focused_seconds": 1600,
                "distraction_count": 1,
                "is_complete": True,
            },
            headers=self.headers,
        )

    @task(2)
    def get_stats(self):
        self.client.get("/stats?period=weekly", headers=self.headers)

    @task(1)
    def project_workflow(self):
        resp = self.client.post(
            "/projects",
            json={"name": f"Load project {uuid.uuid4().hex[:8]}"},
            headers=self.headers,
        )
        if resp.status_code == 201:
            self.project_id = resp.json()["id"]

        self.client.get("/projects", headers=self.headers)

    @task(1)
    def health_check(self):
        self.client.get("/health")
