import requests
import json
import os
import time
import base64
import yaml

API_URL = os.environ.get("API_URL")
API_KEY = os.environ.get("API_KEY")
REPO = os.environ.get("REPO")
COMMIT_HASH = os.environ.get("COMMIT_HASH")
BASE_BRANCH = os.environ.get("BASE_BRANCH")
STATUS = (os.environ.get("STATUS")).upper()

if not (bool(BASE_BRANCH)):
    BASE_BRANCH = os.environ.get("SOURCE_BRANCH")

OWNER = REPO.split("/")
REPO = OWNER[1]

if STATUS == "SUCCESS":
    STATUS = "SUCCESSFUL"
if STATUS == "FAILURE":
    STATUS = "FAILED"

with open("convoy.yaml", "r") as yaml_file:
    yaml_data = yaml.safe_load(yaml_file)
APP_GROUP = yaml_data.get("appGroup")
payload = {
    "repoName": REPO,
    "appGroup": APP_GROUP,
    "commitHash": COMMIT_HASH[:7],
    "baseBranch": BASE_BRANCH,
    "buildStatus": STATUS,
}
print(payload)
headers = {"Content-Type": "application/json", "x-api-key": API_KEY}

max_retries = 3
retry_delay = 20

for _ in range(max_retries):
    response = requests.post(API_URL, json=payload, headers=headers)
    if response.status_code == 200:
        print(response.status_code)
        print(response.text)
        break
    else:
        print(response.status_code)
        print(response.text)
        print(f"Retrying... ({max_retries - _} attempts left)")
        time.sleep(retry_delay)
else:
    print("API request failed after retries.")
    exit(1)
print("POST request Complete")
