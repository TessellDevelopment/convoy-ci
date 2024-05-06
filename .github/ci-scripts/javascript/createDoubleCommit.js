async function createDoubleCommit() {
  const github = require('@actions/github');
  const prTitle = process.env.PR_TITLE
  // Get base branch minor version of the PR
  const prBaseBranch = process.env.BASE_REF
  const prBaseBranchMinVer = prBaseBranch.split('.')[1]
  // get pr source branch
  const prSrcBranch = process.env.HEAD_REF
  const mailID = process.env.MAIL_ID
  var owner = process.env.OWNER
  var repo = process.env.REPO
  // check if this itself is a double commit.
  // then we don't need to create another one from this.
  if (prSrcBranch.includes("double_commit")) {
    console.log("This branch " + prSrcBranch + " is itself a double commit branch")
    process.exit(0);
  }
  // check if NODC is set
  if (prTitle.endsWith('::NODC::') || prTitle.startsWith('::NODC::')) {
    console.log("NODC set, aborting..");
    process.exit(0);
  }

  // create rel branches array
  const branches = process.env.BRANCHES.split(' ')
  // add 'main' branch to the list
  branches.push("main")
  // loop through the available active branches to create DC
  console.log("prBaseBranch: " + prBaseBranch)
  console.log("prBaseBranchMinVer: " + prBaseBranchMinVer)
  console.log("prSrcBranch: " + prSrcBranch);
  for (branch in branches) {
    // if the branch is empty, iterate with next element
    if (branches[branch] == "") {
      continue
    }
    console.log(" Iterating " + branches[branch])
    dstBranch = branches[branch].trim()
    console.log("dstBranch:" + dstBranch)
    // check if its a forward active branch
    if (dstBranch != "main") {
      // remove the 'origin' from the remote branch name
      dstBranch = dstBranch.split('/')[1]

      // No need to create PR for branches not starting with 'rel-'
      if (!dstBranch.startsWith('rel-')) {
        continue
      }

      // dst branch minor version
      dstBranchMinVer = dstBranch.split('.')[1]
      // if minor version is more than the current branch, its a latest release and
      // we need to create DC
      if (parseInt(dstBranchMinVer) <= parseInt(prBaseBranchMinVer)) {
        continue
      }
    }
    // new branch name
    prBranchName = [prSrcBranch, dstBranch, "double_commit"].join("-")
    const { exec } = require('child_process');
    const util = require('util');
    const execPromise = util.promisify(exec);
    command = 'git checkout -b ' + prBranchName + ' origin/' + dstBranch
    try {
      // wait for exec to complete
      const result = await execPromise(command);
      console.log("stdout: " + result.stdout);
      console.log("stderr: " + result.stderr);
    } catch (error) {
      console.log(error);
    }

    command = 'git cherry-pick ' + process.env.SHA
    try {
      // wait for exec to complete
      const result = await execPromise(command);
      console.log("stdout: " + result.stdout);
      console.log("stderr: " + result.stderr);
    } catch (error) {
      console.log(error);
      try {
        command = "find . -type f -name index.lock | xargs rm -rf "
        const result = await execPromise(command);
        console.log("stdout: " + result.stdout);
        console.log("stderr: " + result.stderr);
      } catch (error2) {
        console.log("Error during rm and find.")
        console.log(error2)
      }
      try {
        console.log("Running git status")
        command = "git status"
        result = await execPromise(command);
        console.log("stdout: " + result.stdout);
        console.log("stderr: " + result.stderr);
      } catch (error_status) {
        console.log("Error during git status.")
        console.log(error_status)
      }
      try {
        command = `git add . ; git -c core.editor=true commit --amend --author=${mailID}`
        result = await execPromise(command);
        console.log("stdout: " + result.stdout);
        console.log("stderr: " + result.stderr);
      } catch (error3) {
        console.log("Error during git add.")
        console.log(error3)
        try {
          console.log("Trying cherry-pick --continue")
          command = "git add . ; git -c core.editor=true cherry-pick --continue; git status"
          result = await execPromise(command);
          console.log("stdout: " + result.stdout);
          console.log("stderr: " + result.stderr);
        } catch (error4) {
          console.log("Error during git add with cherry-pick --continue")
          console.log(error4)
        }
        try {
          console.log("Amend the commit")
          command = `git -c core.editor=true commit --amend --author=${mailID}`
          result = await execPromise(command);
          console.log("stdout: " + result.stdout);
          console.log("stderr: " + result.stderr);
        } catch (error5) {
          console.log("Failed during Amending the commit.")
          console.log(error5)
        }
      }
    }
    command = 'git push -u -f origin ' + prBranchName
    result = await execPromise(command);
    console.log("stdout: " + result.stdout);
    console.log("stderr: " + result.stderr);
    // create pull request
    dcTitle = `Double Commit: ${prTitle}`
    pullCreateResponse = await github.rest.pulls.create({
      owner: owner,
      title: dcTitle,
      repo: repo.split('/')[1],
      head: prBranchName,
      base: dstBranch
    });
    console.log(pullCreateResponse)
  }
}

createDoubleCommit();