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
    env_tags = core.getInput('env-tags');
    source_branch = core.getInput('source-branch');

    console.log("Tags are " + env_tags)
    latest_tag = '0.0.0'
    // process multiple tags if any
    tags = env_tags.split(' ')
    if (tags.length == 1) {
        console.log("There is only one tag. Using it." + tags[0])
        latest_tag = tags[0]
    } else {
        if (source_branch == "main") {
        for (i in tags) {
            tag = tags[i]
            console.log("Checking tag " + tag)
            if (latest_tag == null) {
            latest_tag = tag
            continue
            }
            latest_parts = latest_tag.split(".")
            tag_parts = tag.split(".")
            for (i = 0; i < tag_parts.length; i++) {
            if (parseInt(tag_parts[i]) < parseInt(latest_parts[i])) {
                console.log("Skipping " + tag)
                break
            }
            if (parseInt(tag_parts[i]) > parseInt(latest_parts[i])) {
                latest_tag = tag
                console.log("Setting " + latest_tag)
                break
            }
            }
        }
        } else {
        tag_base = source_branch.substring(4).split(".").slice(0,2)
        latest_tag = tag_base.join(".") + ".0"
        for (i in tags) {
            tag = tags[i]
            console.log("branch - Checking tag " + tag)
            tag_parts = tag.split(".")
            if (tag_base[0] == tag_parts[0] && tag_base[1] == tag_parts[1]) {
            latest_parts = latest_tag.split(".")
            if (parseInt(latest_parts[2]) < parseInt(tag_parts[2])) {
                latest_tag = tag
            }
            }
        }
        }
    }
    console.log("Latest tag: " + latest_tag)
    // check if we have
    if ( latest_tag == '' || latest_tag === undefined) {
        console.log("Couldn't determine the latest tag, exiting. Retry manually..")
        process.exit(1);
    }
    core.setOutput('tag_ref', latest_tag)
}
run()