import yaml
import requests
import os
import time
import base64
import subprocess
from datetime import datetime


def get_tf_modules_folders():
    headers = {
        "Authorization": f"Bearer {GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json",
    }
    url = f"{GH_API_URL}/repos/{OWNER}/{REPO}/contents"
    params = {"ref": BASE_BRANCH}
    response = requests.get(url, headers=headers, params=params)
    contents = response.json()
    directories = [
        item["name"]
        for item in contents
        if item["type"] == "dir" and item["name"] != ".github"
    ]
    return directories


def delete_keys(data, keys_to_exclude):
    for key in keys_to_exclude:
        try:
            del data[key]
        except:
            print(f"{key} not present in convoy.yaml")
    return data


def get_artifacts_tf():
    artifacts = []
    tf_modules_folders = get_tf_modules_folders()
    print("Terraform Folders")
    for folder in tf_modules_folders:
        if ".github" in folder or len(folder) == 0:
            continue
        print(folder)
        path = f"./{folder}/convoy.yaml"
        with open(path, "r") as module_content:
            module_data = yaml.safe_load(module_content)
        tf_module = module_data.get("generates")
        for artifact_type, artifact in tf_module.items():
            for object in artifact:
                element = {}
                element["type"] = artifact_type
                element["releaseManifestKey"] = object["releaseManifestKey"]
                element["name"] = object["name"]
                element["extension"] = object["extension"]
                element["version"] = module_data.get("version")
                artifacts.append(element)
    return artifacts


def get_artifacts(generates, version):
    artifacts = []
    for artifact_type, artifact in generates.items():
        for object in artifact:
            element = {}
            element["type"] = artifact_type
            try:
                element["releaseManifestKey"] = object["releaseManifestKey"]
            except:
                print("Artifact excluded from Release Manifest")
                continue
            element["name"] = object["name"]
            element["version"] = version
            if artifact_type == "helmCharts":
                chart_path = object["chartPath"]
                with open(chart_path, "r") as chart_yaml_content:
                    data = yaml.safe_load(chart_yaml_content)
                element["version"] = data.get("version")
            try:
                element["extension"] = object["extension"]
            except:
                print("Extension Details not present")
            artifacts.append(element)
    if len(artifacts) == 0:
        return
    return artifacts

def post_request(payload):
    API_URL = os.environ.get("API_URL")
    API_KEY = os.environ.get("API_KEY")
    headers = {"x-api-key": API_KEY, "Content-Type": "application/json"}
    max_retries = 3
    retry_delay = 5

    for _ in range(max_retries):
        response = requests.post(API_URL, json=payload, headers=headers)
        if response.status_code == 200 or response.status_code == 409:
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
    return


REPO = os.environ.get("REPO")
OWNER = os.environ.get("OWNER")
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN")
GH_API_URL = os.environ.get("GH_API_URL")
COMMIT_HASH = os.environ.get("COMMIT_HASH")
USES_CUSTOM_VERSION = os.environ.get("USES_CUSTOM_VERSION")
BASE_BRANCH = os.environ.get("BASE_BRANCH")
PR_ID = os.environ.get("PR_ID")
TAG = os.environ.get("TAG")
COMMIT_MESSAGE = subprocess.check_output(
    ["git", "log", "--pretty=format:%s", "-n", "1"]
)
COMMIT_MESSAGE = COMMIT_MESSAGE.decode("utf-8")
COMMITTED_AT = os.environ.get("COMMITTED_AT")
COMMITTED_AT = datetime.strptime(COMMITTED_AT, "%Y-%m-%dT%H:%M:%SZ").strftime(
    "%Y-%m-%d %H:%M:%S"
)

try:
    with open("convoy.yaml", "r") as yaml_file:
        yaml_data = yaml.safe_load(yaml_file)
except FileNotFoundError:
    print(f"YAML file not found. Skipping this step.")
    exit(0)
APP_GROUP = yaml_data.get("appGroup")
payload = {
    "repoName": REPO,
    "appGroup": APP_GROUP,
    "commitHash": COMMIT_HASH[:7],
    "commitMessage": COMMIT_MESSAGE,
    "committedAt": COMMITTED_AT,
    "baseBranch": BASE_BRANCH,
    "usesCustomVersion": USES_CUSTOM_VERSION == "true",
    "tag": TAG,
    "pullRequestId": PR_ID,
}
generates = yaml_data.get("generates")
type = yaml_data.get("artifactType")
language = yaml_data.get("language")
if generates != None:
    version = yaml_data.get("version")
    if version == None:
        version = TAG
    payload["artifacts"] = get_artifacts(generates, version)
    if payload["artifacts"] == None:
        del payload["artifacts"]
    print(payload)
elif language == "terraform":
    payload["artifacts"] = get_artifacts_tf()
    print(payload)
elif type == None:
    print(payload)
else:
    print("Wrong convoy.yaml format. Please check.")
post_request(payload)
