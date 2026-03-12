# ClickUp CLI

Simple Python CLI to read/write ClickUp data. Uses the ClickUp API v2 and an API token provided via environment variable or .env file.

## Setup

1. Create and activate a Python environment.
2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Create a .env file (auto-loaded by the CLI):

```bash
cp .env.example .env
```

4. Set your token and IDs in .env or export them in your shell:

```bash
export CLICKUP_API_TOKEN="your-token"
```

On Windows PowerShell:

```powershell
$env:CLICKUP_API_TOKEN = "your-token"
```

## Common commands

List teams:

```bash
python3 cli.py list-teams
```

List spaces for a team:

```bash
python3 cli.py list-spaces --team-id 123
```

List folders in a space:

```bash
python3 cli.py list-folders --space-id 456
```

List lists in a folder:

```bash
python3 cli.py list-lists --folder-id 789
```

List lists directly in a space:

```bash
python3 cli.py list-lists --space-id 456
```

List tasks in a list:

```bash
python3 cli.py list-tasks --list-id 555 --include-closed
```

Create a task:

```bash
python3 cli.py create-task --list-id 555 --name "New Task" --description "Details" --status "to do"
```

Update a task:

```bash
python3 cli.py update-task --task-id abc123 --name "Updated" --status "in progress"
```

Delete a task:

```bash
python3 cli.py delete-task --task-id abc123
```

List time entries:

```bash
python3 cli.py list-time-entries --team-id 123 --start 2026-02-01 --end 2026-02-26
```

## Full access with request

Use the generic request command for anything not covered, including sprints, docs, custom fields, or advanced filters.

```bash
python3 cli.py request GET team/123/space
python3 cli.py request GET list/555/task --params-json '{"include_closed": true}'
python3 cli.py request POST list/555/task --body-json '{"name": "Task from raw"}'
```

You can also set a custom API base URL:

```bash
export CLICKUP_API_BASE_URL="https://api.clickup.com/api/v2"
```
