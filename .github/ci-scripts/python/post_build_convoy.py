import requests
import json
import os
import time
import base64
import yaml


def get_tf_modules_folders():
    headers = {
        'Authorization': f'Bearer {GITHUB_TOKEN}',
        'Accept': 'application/vnd.github.v3+json',
    }
    url = f'{GH_API_URL}/repos/{OWNER}/{REPO}/contents'
    params = {'ref': BASE_BRANCH}
    response = requests.get(url, headers=headers, params=params)
    contents = response.json()
    directories = [item['name'] for item in contents if item['type'] == 'dir' and item['name'] != '.github']
    return directories


def get_artifacts_tf():
    artifacts = []
    SKIP_FOLDERS = [".github", "docs", "scripts"]
    tf_modules_folders = get_tf_modules_folders()
    print("Terraform Folders")
    for folder in tf_modules_folders:
        if any(s in folder for s in SKIP_FOLDERS) or len(folder) == 0:
            continue
        print(folder)
        path = f'./{folder}/convoy.yaml'
        with open(path, 'r') as module_content:
            module_data = yaml.safe_load(module_content)
        tf_module = module_data.get('generates')
        for artifact_type, artifact in tf_module.items():
            for object in artifact:
                element = {}
                element["type"] = artifact_type
                element["releaseManifestKey"] = object["releaseManifestKey"]
                element["name"] = object["name"]
                if APP_GROUP != "tessell":
                    element["name"] = f"{APP_GROUP}-{object['name']}"
                element["extension"] = object["extension"]
                element["version"] = module_data.get('version')
                version = module_data.get('version')
                element["path"] = f"tessell-artifacts/{LABEL}/{element['name']}/{element['name']}-{version}.{object['extension']}"
                artifacts.append(element)
    return artifacts


def get_artifacts(generates, version):
    artifacts = []
    for artifact_type, artifact in generates.items():
        for object in artifact:
            if object.get("excludeFromReleaseManifest"):
                print("Artifact excluded from Release Manifest")
                continue
            element = {}
            element["type"] = artifact_type
            element["releaseManifestKey"] = object["releaseManifestKey"]
            element["name"] = object["name"]
            element["version"] = version
            if object.get("consumes"):
                element["consumes"] = object["consumes"]
            try:
                element["extension"] = f".{object['extension']}" if 'extension' in object and object['extension'] else ""
            except:
                print("Extension Details not present")
            if artifact_type == 'artifacts':
                element["path"] = f"tessell-artifacts/{LABEL}/{object['name']}/{object['name']}-{version}{element['extension']}"
            artifacts.append(element)
    if len(artifacts) == 0:
        return
    return artifacts


def post_request(payload):
    headers = {
        'Content-Type': 'application/json',
        'x-api-key': API_KEY
    }
    max_retries = 3
    retry_delay = 5

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


def get_software_def_url(payload, api_url):
    if STATUS == 'SUCCESSFUL':
        api_url = os.environ.get('API_URL_REPLICATE')
        payload.pop("buildStatus")
    return payload, api_url


API_URL = os.environ.get('API_URL')
API_KEY = os.environ.get('API_KEY')
GH_API_URL = os.environ.get('GH_API_URL')
ARTIFACT_CHECKSUMS = os.environ.get('ARTIFACT_CHECKSUMS')
IS_ANY_ARTIFACT_GENERATED = os.environ.get('IS_ANY_ARTIFACT_GENERATED')
REPO = os.environ.get('REPO')
COMMIT_HASH = os.environ.get('COMMIT_HASH')
BASE_BRANCH = os.environ.get('BASE_BRANCH')
GITHUB_TOKEN = os.environ.get('GITHUB_TOKEN')
LABEL = os.environ.get('LABEL')
STATUS = (os.environ.get('STATUS')).upper()
TAG = os.environ.get('TAG')
OWNER = os.environ.get('OWNER')

if not(bool(BASE_BRANCH)):
    BASE_BRANCH = os.environ.get('SOURCE_BRANCH')

if STATUS == 'SUCCESS':
    STATUS = 'SUCCESSFUL'
if STATUS == 'FAILURE':
    STATUS = 'FAILED'
    IS_ANY_ARTIFACT_GENERATED = "false"

with open('convoy.yaml', 'r') as yaml_file:
    yaml_data = yaml.safe_load(yaml_file)
APP_GROUP = yaml_data.get('appGroup')
payload = {
    "repoName": REPO,
    "appGroup": APP_GROUP,
    "commitHash": COMMIT_HASH[:7],
    "baseBranch": BASE_BRANCH,
    "buildStatus": STATUS,
    "artifactGenerated": IS_ANY_ARTIFACT_GENERATED == "true",
}

if IS_ANY_ARTIFACT_GENERATED == 'true':
    generated_artifacts = os.environ.get('GENERATED_ARTIFACTS')
    if generated_artifacts and generated_artifacts.strip():
        payload["artifacts"] = json.loads(generated_artifacts)
    else:
        generates = yaml_data.get('generates')
        language = yaml_data.get('language')
        if generates != None:
            version = yaml_data.get('version')
            if version == None:
                version = TAG
            payload["artifacts"] = get_artifacts(generates, version)
            if payload["artifacts"] == None:
                del payload["artifacts"]
        elif language == 'terraform':
            payload["artifacts"] = get_artifacts_tf()
        elif generates == None:
            print("No artifact generated in the repo.")
        else:
            print(f"Not able to build payload for API call. Please check convoy.yaml content")
            exit(1)

        if generates and "artifacts" in generates and "buildFunction" in generates["artifacts"][0] and generates["artifacts"][0]["buildFunction"] == "softwareDefBuild":
            payload, API_URL = get_software_def_url(payload, API_URL)

        if ARTIFACT_CHECKSUMS and payload.get("artifacts"):
            checksum_map = {}
            parts = ARTIFACT_CHECKSUMS.strip('%').split('%')
            for part in parts:
                if part:
                    key, value = part.split(':', 1)
                    checksum_map[key] = value

            for artifact in payload["artifacts"]:
                key = artifact["name"]
                type = artifact["type"]
                if type == "artifacts":
                    if key in checksum_map:
                        artifact["checksum"] = checksum_map[key]
                    else:
                        key_without_prefix = key.removeprefix(f"{APP_GROUP}-")
                        if key_without_prefix in checksum_map:
                            artifact["checksum"] = checksum_map[key_without_prefix]
                        else:
                            print(f"Checksum not found for artifact: {key}")
                            exit(1)
                elif type == "dockerImages":
                    if key in checksum_map:
                        artifact["checksum"] = checksum_map[key]
                    else:
                        key_without_prefix = key.removeprefix(f"{APP_GROUP}-")
                        if key_without_prefix in checksum_map:
                            artifact["checksum"] = checksum_map[key_without_prefix]
                        else:
                            print(f"Checksum not found for docker image: {key}")
                            exit(1)

print(json.dumps(payload, indent=4))
post_request(payload)
