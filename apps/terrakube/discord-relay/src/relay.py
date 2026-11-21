import hmac
import json
import os
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DISCORD_WEBHOOK_URL = os.environ["DISCORD_WEBHOOK_URL"]
RELAY_TOKEN = os.environ["RELAY_TOKEN"]
MAX_BODY_BYTES = 64 * 1024

STATUS_COLORS = {
    "completed": 0x2ECC71,
    "applied": 0x2ECC71,
    "planned_and_finished": 0x2ECC71,
    "errored": 0xE74C3C,
    "discarded": 0x95A5A6,
    "canceled": 0x95A5A6,
    "needs_attention": 0xF39C12,
}

DEFAULT_COLOR = 0x7289DA


def truncate(value, limit):
    if value is None:
        return None
    value = str(value)
    return value if len(value) <= limit else value[: limit - 1] + "…"


def build_discord_payload(body):
    status = body.get("status") or "unknown"
    workspace = body.get("workspace") or "unknown workspace"
    organization = body.get("organization")
    run_url = body.get("runUrl")
    commit_id = body.get("commitId")
    failure_reason = body.get("failureReason")

    fields = []
    if organization:
        fields.append({"name": "Organization", "value": truncate(organization, 1024), "inline": True})
    if commit_id:
        fields.append({"name": "Commit", "value": truncate(commit_id, 12), "inline": True})
    if failure_reason:
        fields.append({"name": "Reason", "value": truncate(failure_reason, 1024), "inline": False})

    embed = {
        "title": truncate(f"{workspace} — {status}", 256),
        "color": STATUS_COLORS.get(status, DEFAULT_COLOR),
        "fields": fields,
    }

    payload = {"embeds": [embed]}
    if run_url:
        payload["components"] = [
            {
                "type": 1,
                "components": [
                    {"type": 2, "style": 5, "label": "View Run", "url": run_url}
                ],
            }
        ]
    return payload


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if not self.path.startswith("/notify/") or not hmac.compare_digest(
            self.path[len("/notify/") :], RELAY_TOKEN
        ):
            self.send_response(404)
            self.end_headers()
            return

        length = int(self.headers.get("Content-Length", 0))
        if length > MAX_BODY_BYTES:
            self.send_response(413)
            self.end_headers()
            return
        raw_body = self.rfile.read(length) if length else b""
        try:
            body = json.loads(raw_body or b"{}")
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            return

        discord_payload = build_discord_payload(body)
        req = urllib.request.Request(
            DISCORD_WEBHOOK_URL,
            data=json.dumps(discord_payload).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                self.send_response(resp.status)
        except urllib.error.HTTPError as e:
            print(f"Discord returned {e.code}: {e.read()[:500]}", file=sys.stderr)
            self.send_response(e.code)
        except urllib.error.URLError as e:
            print(f"Failed to reach Discord: {e}", file=sys.stderr)
            self.send_response(502)
        self.end_headers()

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
