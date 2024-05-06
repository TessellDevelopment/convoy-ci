import os
import re
import yaml
from jira import JIRA


def validateJira():
    try:
        options = {"server": "https://tessell.atlassian.net"}
        jira = JIRA(options, basic_auth=(user, apikey))
        try:
            issue = jira.issue(jira_ticket)
            print("Ticket Summary=", issue.fields.summary)
        except Exception as ex:
            print("Not a valid jira", jira_ticket)
            raise Exception(ex)
    except Exception as ex:
        raise Exception(ex)


def extractJira():
    match_branch = re.search(rf"({supported_jira_projects})\d+", branch_name)
    match_pr = re.search(rf"({supported_jira_projects})\d+", pr_title)

    if jira_match == "ALL":
        if match_branch and match_pr and jira_source == "BOTH":
            ticket_branch = match_branch.group(0)
            ticket_pr = match_pr.group(0)
            if ticket_branch == ticket_pr:
                print(f"Same Jira present in both Branch and PR:{ticket_branch}")
                return ticket_branch
            else:
                raise Exception("Error: Different Jira present in both Branch and PR")
        elif match_branch and jira_source == "BRANCH_NAME_PREFIX":
            ticket = match_branch.group(0)
            print(f"Jira ticket extracted from Branch name:{ticket}")
            return ticket
        elif match_pr and jira_source == "PR_TITLE_PREFIX":
            ticket = match_pr.group(0)
            print(f"Jira ticket extracted from PR Title:{ticket}")
            return ticket
        else:
            raise Exception(
                "No Appropriate Jira ticket found in Branch name or PR Title"
            )
    elif jira_match == "ANY":
        if jira_source == "BRANCH_NAME_PREFIX":
            if match_branch:
                ticket = match_branch.group(0)
                print(f"Jira ticket extracted from Branch name:{ticket}")
                return ticket
            else:
                print(f"No Jira ticket found in Branch name, checking in PR title")
                if match_pr:
                    ticket = match_pr.group(0)
                    print(f"Jira ticket extracted from PR Title:{ticket}")
                    return ticket
                else:
                    raise Exception(
                        "No Appropriate Jira ticket found in Branch name or PR Title"
                    )
        elif jira_source == "PR_TITLE_PREFIX":
            if match_pr:
                ticket = match_pr.group(0)
                print(f"Jira ticket extracted from PR Title:{ticket}")
                return ticket

            else:
                print(f"No Jira ticket found in PR Title, checking in Branch name")
                if match_branch:
                    ticket = match_branch.group(0)
                    print(f"Jira ticket extracted from Branch name:{ticket}")
                    return ticket
                else:
                    raise Exception(
                        "No Appropriate Jira ticket found in Branch name or PR Title"
                    )
        elif jira_source == "BOTH":
            if match_branch:
                ticket = match_branch.group(0)
                print(f"Jira ticket extracted from Branch name:{ticket}")
                return ticket
            else:
                print(f"No Jira ticket found in Branch name, checking in PR title")
                if match_pr:
                    ticket = match_pr.group(0)
                    print(f"Jira ticket extracted from PR Title:{ticket}")
                    return ticket
                else:
                    raise Exception(
                        "No Appropriate Jira ticket found in Branch name or PR Title"
                    )
        else:
            raise Exception("Error: Invalid selection in Jira Source")
    elif jira_match == "NONE":
        print("No extraction of Jira ticket specified")
        exit(0)
    else:
        raise Exception("Invalid Jira Match type specified")


with open("convoy.yaml", "r") as file:
    data = yaml.safe_load(file)

apikey = os.environ.get("JIRA_API_TOKEN")
branch_name = os.environ.get("HEAD_BRANCH")
jira_source = (
    data.get("ci").get("bestPractices").get("jiraValidation").get("jiraIdSource")
)
jira_match = (
    data.get("ci").get("bestPractices").get("jiraValidation").get("matchingRule")
)
pr_title = os.environ.get("PR_TITLE")
supported_jira_projects = os.environ.get("SUPPORTED_JIRA_PROJECTS")
user = os.environ.get("JIRA_USERNAME")

jira_ticket = extractJira()
validateJira()
