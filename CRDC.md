Implement these changes in the DC(double commit) workflow logic:
- if rel-0.0.0 exists in the repo then create a DC there (irrespective of original base branch)
- Get CRDS mapping list for given { appGroup , sourceBranch } using api 
```
curl --location 'https://api.convoy.tessell.cloud/devops/crdc?sourceAppGroup={}&sourceBranch={}' \
--header 'X-Api-Key: {}' \
--header 'Content-Type: application/json' \
--data ''

RESPONSE:
[
    {
        "sourceAppGroup": "tessell",
        "sourceBranch": "main",
        "targetAppGroup": "gcpcore",
        "targets": [
            {
                "name": "rel-0.0.0",
                "type": "branch"
            },
            {
                "name": "IN_PRODUCTION",
                "type": "release_status"
            }
        ],
        "id": "29c8b4ff-f0e8-4cb6-85d1-137470b268e6",
        "dateModified": "2026-01-27T07:26:20.161422",
        "modifiedBy": "20fbe777-dd95-46b2-9970-59cba1fbbf31",
        "dateCreated": "2026-01-27T07:26:20.161409",
        "createdBy": "20fbe777-dd95-46b2-9970-59cba1fbbf31"
    }
]
```
  - Raise DCs on the target repos
    - Derive repoName from target appGroup
      - cross repo name: remove tessell- prefix from original repo name and add targetAppGroup- prefix
    - Add remote to target repoName
    - Push branch with name *_crdc and raise PR with title "CRDC*" similar to same repo DC

Upon completing this we'll focus on refining the "targets" logic for now presume the targets[0] will be of type branch for the cross repo



Now for the multiple target clarity:
1. The targets order is in a high priority order(If first one is present then skip the rest)
2. If target type is branch, first check if that branch exists in target repo if yes then create CRDC and continue. No need to do anything for other target
3. If target type is release_status then use this API

curl --location 'https://api.convoy.tessell.cloud/apps/<>/releases' \
--header 'action: LIST_WITH_DETAILS' \
--header 'x-api-key: <>'

it's response will be a list of release
{
    "releases": [
        {
            "name": "rel-140",
            "status": "INCUBATING",
            "dateCreated": "2026-01-13T10:31:37.639143Z",
            "actionsAllowed": [
                "CREATE"
            ]
        }]}
check if any release exists with given release_status if yes then get release name and create a CRDC on corresponding branch format rel-0.x.0 if it exists
4. As soon as a match is found in the targets going sequentially create a CRDC and exit, no need to check other target.


Implement the code as simply as possible
1. Get targets
2. Create target repo name and add remote to repo
2. Loop over targets
4. Do above logic
5. Create a CRDC as soon as a match is found
