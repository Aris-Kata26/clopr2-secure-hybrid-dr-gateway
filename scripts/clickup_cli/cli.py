import argparse
import json
import os
import sys
from datetime import datetime
from typing import Any, Dict, Optional

try:
    import requests
except ImportError as exc:
    raise SystemExit(
        "Missing dependency 'requests'. Run: pip install -r requirements.txt"
    ) from exc

try:
    from dotenv import load_dotenv
except ImportError as exc:
    raise SystemExit(
        "Missing dependency 'python-dotenv'. Run: pip install -r requirements.txt"
    ) from exc

DEFAULT_BASE_URL = "https://api.clickup.com/api/v2"


def parse_json(value: Optional[str]) -> Optional[Dict[str, Any]]:
    if not value:
        return None
    return json.loads(value)


def parse_csv_list(value: Optional[str]) -> Optional[list]:
    if not value:
        return None
    return [item.strip() for item in value.split(",") if item.strip()]


def parse_date_or_ms(value: Optional[str]) -> Optional[int]:
    if not value:
        return None
    if value.isdigit():
        return int(value)
    parsed = datetime.fromisoformat(value)
    return int(parsed.timestamp() * 1000)


class ClickUpClient:
    def __init__(self, token: str, base_url: str = DEFAULT_BASE_URL) -> None:
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": token,
                "Content-Type": "application/json",
            }
        )

    def request(
        self,
        method: str,
        path: str,
        params: Optional[Dict[str, Any]] = None,
        body: Optional[Dict[str, Any]] = None,
    ) -> requests.Response:
        url = f"{self.base_url}/{path.lstrip('/')}"
        return self.session.request(method, url, params=params, json=body, timeout=60)


def ensure_token() -> str:
    token = os.getenv("CLICKUP_API_TOKEN")
    if not token:
        raise SystemExit("CLICKUP_API_TOKEN is not set.")
    return token


def load_env_files() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    load_dotenv(os.path.join(script_dir, ".env"))
    load_dotenv(os.path.join(os.getcwd(), ".env"))


def render_response(response: requests.Response, output_path: Optional[str]) -> None:
    try:
        payload = response.json()
    except ValueError:
        payload = {"raw": response.text}

    if not response.ok:
        payload = {
            "status": response.status_code,
            "error": payload,
        }

    data = json.dumps(payload, indent=2)
    if output_path:
        with open(output_path, "w", encoding="utf-8") as handle:
            handle.write(data)
        print(f"Wrote {output_path}")
    else:
        print(data)

    if not response.ok:
        raise SystemExit(1)


def cmd_request(client: ClickUpClient, args: argparse.Namespace) -> None:
    params = parse_json(args.params_json)
    body = parse_json(args.body_json)
    response = client.request(args.method, args.path, params=params, body=body)
    render_response(response, args.out)


def cmd_list_teams(client: ClickUpClient, args: argparse.Namespace) -> None:
    response = client.request("GET", "team")
    render_response(response, args.out)


def cmd_list_spaces(client: ClickUpClient, args: argparse.Namespace) -> None:
    response = client.request("GET", f"team/{args.team_id}/space")
    render_response(response, args.out)


def cmd_list_folders(client: ClickUpClient, args: argparse.Namespace) -> None:
    response = client.request("GET", f"space/{args.space_id}/folder")
    render_response(response, args.out)


def cmd_list_lists(client: ClickUpClient, args: argparse.Namespace) -> None:
    if args.folder_id:
        path = f"folder/{args.folder_id}/list"
    else:
        path = f"space/{args.space_id}/list"
    response = client.request("GET", path)
    render_response(response, args.out)


def cmd_list_tasks(client: ClickUpClient, args: argparse.Namespace) -> None:
    params = {"include_closed": str(args.include_closed).lower()}
    response = client.request("GET", f"list/{args.list_id}/task", params=params)
    render_response(response, args.out)


def cmd_get_task(client: ClickUpClient, args: argparse.Namespace) -> None:
    response = client.request("GET", f"task/{args.task_id}")
    render_response(response, args.out)


def build_task_payload(args: argparse.Namespace) -> Dict[str, Any]:
    payload: Dict[str, Any] = {"name": args.name}
    if args.description:
        payload["description"] = args.description
    if args.status:
        payload["status"] = args.status
    assignees = parse_csv_list(args.assignees)
    if assignees:
        payload["assignees"] = assignees
    tags = parse_csv_list(args.tags)
    if tags:
        payload["tags"] = tags
    custom_fields = parse_json(args.custom_fields_json)
    if custom_fields:
        payload["custom_fields"] = custom_fields
    return payload


def cmd_create_task(client: ClickUpClient, args: argparse.Namespace) -> None:
    payload = build_task_payload(args)
    response = client.request("POST", f"list/{args.list_id}/task", body=payload)
    render_response(response, args.out)


def cmd_update_task(client: ClickUpClient, args: argparse.Namespace) -> None:
    payload = build_task_payload(args)
    response = client.request("PUT", f"task/{args.task_id}", body=payload)
    render_response(response, args.out)


def cmd_delete_task(client: ClickUpClient, args: argparse.Namespace) -> None:
    response = client.request("DELETE", f"task/{args.task_id}")
    render_response(response, args.out)


def cmd_list_time_entries(client: ClickUpClient, args: argparse.Namespace) -> None:
    params = {
        "start_date": parse_date_or_ms(args.start),
        "end_date": parse_date_or_ms(args.end),
    }
    response = client.request("GET", f"team/{args.team_id}/time_entries", params=params)
    render_response(response, args.out)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="ClickUp API CLI")
    parser.add_argument(
        "--base-url",
        default=os.getenv("CLICKUP_API_BASE_URL", DEFAULT_BASE_URL),
        help="Override ClickUp API base URL",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    request = subparsers.add_parser("request", help="Call any ClickUp endpoint")
    request.add_argument("method", choices=["GET", "POST", "PUT", "PATCH", "DELETE"])
    request.add_argument("path", help="Path like team/123/space")
    request.add_argument("--params-json", help="Query params as JSON")
    request.add_argument("--body-json", help="Body as JSON")
    request.add_argument("--out", help="Write response to file")
    request.set_defaults(func=cmd_request)

    list_teams = subparsers.add_parser("list-teams", help="List teams")
    list_teams.add_argument("--out", help="Write response to file")
    list_teams.set_defaults(func=cmd_list_teams)

    list_spaces = subparsers.add_parser("list-spaces", help="List spaces")
    list_spaces.add_argument("--team-id", required=True)
    list_spaces.add_argument("--out", help="Write response to file")
    list_spaces.set_defaults(func=cmd_list_spaces)

    list_folders = subparsers.add_parser("list-folders", help="List folders")
    list_folders.add_argument("--space-id", required=True)
    list_folders.add_argument("--out", help="Write response to file")
    list_folders.set_defaults(func=cmd_list_folders)

    list_lists = subparsers.add_parser("list-lists", help="List lists")
    list_lists_group = list_lists.add_mutually_exclusive_group(required=True)
    list_lists_group.add_argument("--folder-id")
    list_lists_group.add_argument("--space-id")
    list_lists.add_argument("--out", help="Write response to file")
    list_lists.set_defaults(func=cmd_list_lists)

    list_tasks = subparsers.add_parser("list-tasks", help="List tasks")
    list_tasks.add_argument("--list-id", required=True)
    list_tasks.add_argument("--include-closed", action="store_true")
    list_tasks.add_argument("--out", help="Write response to file")
    list_tasks.set_defaults(func=cmd_list_tasks)

    get_task = subparsers.add_parser("get-task", help="Get a task")
    get_task.add_argument("--task-id", required=True)
    get_task.add_argument("--out", help="Write response to file")
    get_task.set_defaults(func=cmd_get_task)

    create_task = subparsers.add_parser("create-task", help="Create a task")
    create_task.add_argument("--list-id", required=True)
    create_task.add_argument("--name", required=True)
    create_task.add_argument("--description")
    create_task.add_argument("--status")
    create_task.add_argument("--assignees", help="Comma-separated user IDs")
    create_task.add_argument("--tags", help="Comma-separated tags")
    create_task.add_argument("--custom-fields-json")
    create_task.add_argument("--out", help="Write response to file")
    create_task.set_defaults(func=cmd_create_task)

    update_task = subparsers.add_parser("update-task", help="Update a task")
    update_task.add_argument("--task-id", required=True)
    update_task.add_argument("--name", required=True)
    update_task.add_argument("--description")
    update_task.add_argument("--status")
    update_task.add_argument("--assignees", help="Comma-separated user IDs")
    update_task.add_argument("--tags", help="Comma-separated tags")
    update_task.add_argument("--custom-fields-json")
    update_task.add_argument("--out", help="Write response to file")
    update_task.set_defaults(func=cmd_update_task)

    delete_task = subparsers.add_parser("delete-task", help="Delete a task")
    delete_task.add_argument("--task-id", required=True)
    delete_task.add_argument("--out", help="Write response to file")
    delete_task.set_defaults(func=cmd_delete_task)

    time_entries = subparsers.add_parser("list-time-entries", help="List time entries")
    time_entries.add_argument("--team-id", required=True)
    time_entries.add_argument("--start", help="ISO date or epoch ms")
    time_entries.add_argument("--end", help="ISO date or epoch ms")
    time_entries.add_argument("--out", help="Write response to file")
    time_entries.set_defaults(func=cmd_list_time_entries)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    load_env_files()
    token = ensure_token()
    client = ClickUpClient(token, base_url=args.base_url)
    args.func(client, args)


if __name__ == "__main__":
    main()
