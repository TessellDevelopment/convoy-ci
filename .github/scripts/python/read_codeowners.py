import os
import sys


def extract_team_names(team_names):
    return [team.replace(f"@{owner}/", "") for team in team_names]


team_patterns = {}
with open(".github/CODEOWNERS", "r") as pattern_file:
    lines = pattern_file.readlines()

for line in lines:
    line = line.strip()
    if not line or line.startswith("#"):
        continue

    parts = line.split()
    file_pattern = parts[0]
    team_names = parts[1:]

    team_names_cleaned = extract_team_names(team_names)
    team_patterns[file_pattern] = team_names_cleaned

changed_files = os.environ.get("changed-files")
owner = os.environ.get("OWNER")
changed_files_list = changed_files.split()
changed_teams = set()
for file_path in changed_files_list:
    for pattern, team_name in team_patterns.items():
        if (
            file_path.startswith(pattern) or file_path.startswith(pattern[:-2])
        ) and pattern != "*":
            changed_teams.update(team_name)
            break
    else:
        changed_teams.update(team_patterns["*"])

required_teams = ""
for team in changed_teams:
    required_teams = required_teams + team + " "
required_teams.strip()
print(required_teams)
sys.stdout.write(f"::set-output name=teams::{required_teams}\n")
