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

async function run() {
  octokit = getOctokit();
  organisation = core.getInput('organisation');
  repo_name = core.getInput('repo_name');
  branch_name = core.getInput('new_branch');

  console.log("Checking if branch exist.");
  try {
    response = await octokit.rest.repos.getBranch({
      owner: organisation,
      repo: repo_name,
      branch: branch_name,
    });
    if (response.status == 200) {
      core.setFailed('Branch already exist.');
      return;
    }
  } catch (error) {
    console.log('Branch does not exist.');
  }

  console.log('Getting repository details');
  response = await octokit.rest.repos.get({
    owner: organisation,
    repo: repo_name
  });
  default_branch = response.data['default_branch'];
  console.log("Getting latest commit id of " + default_branch);

  response = await octokit.rest.repos.getBranch({
    owner: organisation,
    repo: repo_name,
    branch: default_branch,
  });
  branch_sha = response.data['commit']['sha'];
  console.log("Creating branch against " + branch_sha);

  result = await octokit.rest.git.createRef({
    owner: organisation,
    repo: repo_name,
    ref: 'refs/heads/' + branch_name,
    message: 'Tag created by CI pipeline',
    sha: branch_sha
  });
  console.log("Branch created successfully.");
}
run();
