import requests
import json
import os
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

IMAGE_SCAN_API_URL = os.environ.get('IMAGE_SCAN_API_URL')
CONVOY_API_KEY = os.environ.get('CONVOY_API_KEY')
REPO = os.environ.get('REPO')
IMAGE = os.environ.get('IMAGE')

def post_to_slack(message):
  usergroup_id=os.environ.get('DEVOPS_TEAM')
  mention = f"<!subteam^{usergroup_id}>"
  full_message=f"{mention}\n vulnerability validation failed in \`{REPO}\` for \`{IMAGE}\`, please check \n\`\`\`{message}\`\`\`"
  client = WebClient(token=os.environ.get('SLACK_TOKEN'))
  try:
    response = client.chat_postMessage(channel=os.environ.get('CHANNEL_ID'), text=full_message)
    return response["ok"]
  except SlackApiError as e:
    print(f"Error posting to Slack: {e.response['error']}")
    return False

with open('trivy_image_scan_result.json') as json_file:
  trivy_json = json.load(json_file)
with open('dockle_image_scan_result.json') as json_file:
  dockle_json = json.load(json_file)
payload = {
  "repository": REPO,
  "CVE":trivy_json,
  "DOCKER_BEST_PRACTICE":dockle_json,
}

headers = {
  'Content-Type': 'application/json',
  'x-api-key': CONVOY_API_KEY
}

try:
  response = requests.post(IMAGE_SCAN_API_URL, json=payload, headers=headers)
  if response.status_code == 200:
    print(response.status_code)
    print(response.text)
  elif response.status_code == 409:
    print(json.dumps(response.json(), indent=2))
    print("Get approval for these vulnerabilities or fix them")
    exit(1)
  else:
    print(response.status_code)
    print(response.text)
    post_to_slack(response.text)
    exit(1)
except Exception as e:
  print(e)
  post_to_slack(e)
  exit(1)
  