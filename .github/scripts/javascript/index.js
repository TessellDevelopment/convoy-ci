const createDoubleCommit = require('./create_double_commit.js');
const checkVersion = require('./check_version.js');
const functions = require('./functions.js');
const args = process.argv;
const functionName = args[2]

BASE_REF = process.env.BASE_REF;
BASE_SHA = process.env.BASE_SHA;
GITHUB_SHA = process.env.GITHUB_SHA;
GITHUB_EVENT_BEFORE = process.env.GITHUB_EVENT_BEFORE;
GITHUB_EVENT_NAME = process.env.GITHUB_EVENT_NAME;
OWNER = process.env.OWNER;
REPO = process.env.REPO;

if (functionName === "createDoubleCommit") {
  createDoubleCommit();
}
else if (functionName === 'checkVersion') {
  checkVersion();
}
else {
  if (!(functionName in functions)) {
    console.error(`Function '${functionName}' not found.`);
    process.exit(1);
  }
  functions[functionName]();
}
