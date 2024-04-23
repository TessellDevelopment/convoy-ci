const functions = require('./functions.js');
const args = process.argv;
const functionName = args[2]

GITHUB_SHA = process.env.GITHUB_SHA;
GITHUB_EVENT_BEFORE = process.env.GITHUB_EVENT_BEFORE;
GITHUB_EVENT_NAME = process.env.GITHUB_EVENT_NAME;
BASE_REF = process.env.BASE_REF;
PR_SHA = process.env.PR_SHA;
OWNER = process.env.OWNER;
REPO = process.env.REPO;

if (!(functionName in functions)) {
    console.error(`Function '${functionName}' not found.`);
    process.exit(1);
}
functions[functionName]();
