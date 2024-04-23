async function outputPRDiff() {
  const fs = require('fs');
  const github = require('@actions/github');
  head_commit = GITHUB_SHA
  base_commit = GITHUB_SHA
  if ( GITHUB_EVENT_BEFORE != '0000000000000000000000000000000000000000') { 
    base_commit = GITHUB_EVENT_BEFORE
  }
  if ( GITHUB_EVENT_NAME == 'pull_request') {
    console.log("Using the base branch's commit for comparing.")
    base_commit = BASE_SHA
  }
  response = await github.rest.repos.compareCommits({
      owner: OWNER,
      repo: REPO.split('/')[1],
      head: head_commit,
      base: base_commit
  });
  let jsonResponse = JSON.stringify(response);
  fs.writeFileSync('response.txt', jsonResponse, 'utf8');
}

function checkMergeConflicts() {
  const fs = require('fs');
  fs.readFile('response.txt', 'utf8', (err, resData) => {
    if (err) {
        console.error('Error reading file:', err);
        process.exit(1);
    }
    let response = JSON.parse(resData);
    response.data.files.forEach(function(file_entry) {
      console.log(file_entry.filename);
      dir_name = file_entry.filename.split("/")[0];
      console.log(file_entry.patch);
      if(typeof file_entry.patch !== 'undefined'){
        if ( file_entry.patch.includes("+<<<<<<<") || file_entry.patch.includes("+=======") || file_entry.patch.includes("+>>>>>>>")) {
          core.setFailed("Please resolve Merge Conflict in: " + dir_name );  
        }
      }
      else{
        console.log("Skipping:" + file_entry.filename);
      }
  });
  console.log("No merge conflicts found"); 
  });
}

async function checkDBMigrationScripts() {
  const fs = require('fs');
  let path = "";
  let response;
  fs.readFile('response.txt', 'utf8', (err, resData) => {
    if (err) {
        console.error('Error reading file:', err);
        process.exit(1);
    }
    response = JSON.parse(resData);
    response.data.files.forEach(function(file_entry) {
      if (file_entry.filename.endsWith(".sql") && file_entry.filename.includes("db/migration/") && 
          (file_entry.status == 'modified' || file_entry.status == 'removed')) {
        console.log(file_entry.filename);
        console.log(file_entry.status);
        core.setFailed("Modifying or removing a flyway history file " + file_entry.filename);
      }
      if (file_entry.filename.endsWith(".sql") && file_entry.filename.includes("db/migration/")) {
        const lastSlashIndex = file_entry.filename.lastIndexOf("/");
        path = file_entry.filename.substring(0, lastSlashIndex);
      }
    });
    console.log(path);
  });
  const { Octokit } = require("@octokit/rest");
  const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN, request: { fetch } });
  const { data: existingFiles } = await octokit.repos.getContent({
    owner: OWNER,
    repo: REPO.split('/')[1],
    ref: BASE_REF,
    path: path,
  });
  console.log(existingFiles)
  const existing_versions = existingFiles.map(f => f.name.split("__")[0]);
  response.data.files.forEach(function(file_entry){
    if (file_entry.filename.endsWith(".sql") && file_entry.filename.includes("db/migration/")) {
      console.log(existing_versions)
      const version = file_entry.filename.split("__")[0].split("/").pop();
      console.log(version)
      console.log(existing_versions)
      if (existing_versions.includes(version)) {
        console.log(file_entry.filename);
        core.setFailed(`Flyway file with version ${version} already exists`);
      }
    }
  });
}

function checkTerraformVersion(){
  const fs = require('fs');
  fs.readFile('response.txt', 'utf8', (err, resData) => {
    if (err) {
        console.error('Error reading file:', err);
        process.exit(1);
    }
    let response = JSON.parse(resData);
    var terraform_file = [] 
    response.data.files.forEach(function(file_entry) {
      if (file_entry.filename.endsWith(".tf") && file_entry.status != 'removed') {
        console.log(file_entry.filename);
        console.log(file_entry.status);
        terraform_file.push(file_entry.filename)
        console.log(terraform_file) ;
      }
    });
    core.setOutput('terraform_files' , terraform_file.join(','));
  });
}

module.exports = {
  outputPRDiff,
  checkMergeConflicts,
  checkDBMigrationScripts,
  checkTerraformVersion
};
