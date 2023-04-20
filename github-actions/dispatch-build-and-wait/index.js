/**
 * Github action to dispatch the build and wait for the build to complete.
 * 
 *
 */
const core = require('@actions/core');
const github = require('@actions/github');

function getOctokit() {
  
  let githubToken = core.getInput('github-token');
  if (!githubToken) {
    if (process.env.GITHUB_TOKEN) {
      githubToken = process.env.GITHUB_TOKEN;
    } else {
      core.setFailed(
        'Input "github-token" is missing, and not provided in environment'
      );
    }
  }
  const octokit = github.getOctokit(githubToken);
  return octokit;
}

async function dispatch_build(octokit, organisation, repo_name, branch_name) {
  const sleep = dt => new Promise(resolve => setTimeout(resolve, dt))
  console.log('Call webhook here for ' + repo_name)
  try {
    response = await octokit.rest.repos.createDispatchEvent({
      owner: organisation,
      repo: repo_name,
      event_type: 'publish',
      client_payload: {"inputs": { "organisation": organisation }}
    })
  } catch (error) {
    console.log(error)
    core.setFailed(error)
    return null;
  }
  max_ctr = 4
  ctr = 0
  while(true) {
    console.log("Sleeping for 15 seconnds")
    await sleep(15 * 1000);
    console.log("Getting the job number ")
    let queued_workflows = await octokit.rest.actions.listWorkflowRunsForRepo({
      owner: organisation,
      repo: repo_name,
      event: 'repository_dispatch',
      status: 'queued',
      per_page: 100
    })
    let in_progress_workflows = await octokit.rest.actions.listWorkflowRunsForRepo({
      owner: organisation,
      repo: repo_name,
      event: 'repository_dispatch',
      status: 'in_progress',
      per_page: 100
    })
    incomplete_workflows = queued_workflows.data.workflow_runs.concat(in_progress_workflows.data.workflow_runs)
    console.log(incomplete_workflows)
    if (incomplete_workflows.length == 0) {
      console.log(response.status)
      console.log(response.data)
      console.log(ctr)
      console.log(max_ctr)
      console.log(ctr >= max_ctr)
      if (ctr >= max_ctr) {
        core.setFailed("Could not submit the job for repository: " + repo_name)
        break;
      } else {
        console.log("Sleep and try to fetch details again.")
        ctr = ctr + 1
      }
    } else {
      break;
    }
  }
  return incomplete_workflows;
}

async function run() {
  octokit = getOctokit();
  organisation = core.getInput('organisation');
  repo_name = core.getInput('repo_name');
  branch_name = core.getInput('branch_name');

  incomplete_workflows = await dispatch_build(octokit, organisation, repo_name, branch_name)
  for (var idx in incomplete_workflows) {
    job_status = await wait_for_workflow(octokit, organisation, repo_name, branch_name,incomplete_workflows[idx])
    console.log("Job status: " + job_status.conclusion) 
    core.setOutput('job_status', job_status.conclusion)
    core.setOutput(repo_name, job_status)
  }
}

async function wait_for_workflow(octokit, organisation, repo_name, branch_name, workflow_run) {
  const sleep = dt => new Promise(resolve => setTimeout(resolve, dt))
  console.log("Workflow - " + workflow_run.id + " Status " + workflow_run.status)
  while(true) {
    response = await octokit.rest.actions.getWorkflowRun({
      owner: organisation,
      repo: repo_name,
      run_id: workflow_run.id
    })
    if (response.data.status == 'completed') {
      console.log("Workflow - " + workflow_run.id + " Status " + response.data.conclusion)
      return response.data
    }
    console.log("Sleeping for 1 min.")
    await sleep(60000);
  }
}

run();
