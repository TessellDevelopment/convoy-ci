function checkNexusVersion(nexusRepo, exporter, version) {
  console.log(nexusRepo);
  console.log(exporter);
  console.log(version);
  execSync = require('child_process').execSync;
  const output = execSync(`
      file="${exporter}-${version}"
      API_URL="$NEXUS_URL=${nexusRepo}&version=${version}"
      echo $API_URL
      echo $file
      response=$(curl -u "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" -X GET "$API_URL")
      check="$(echo $response | grep $file)"
      if [ ! -z "$check" ]
          then
              echo "Fail"
              exit 
          fi
      
      while [ "$(echo $response | jq -r '.continuationToken')" != "null" ]; do
          continuationToken=$(echo $response | jq -r '.continuationToken')
          response=$(curl -u "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" -X GET "$API_URL&continuationToken=$continuationToken")
          check="$(echo $response | grep $file)"
          if [ ! -z "$check" ]
          then
              echo "Fail"
              exit 
          fi
      done
      if [ -z "$check" ]
          then
              echo "Pass"
              exit 
          fi
  `, { encoding: 'utf-8' });
  console.log(output);
  if (output.includes("Fail")) {
    throw new Error("Error: Update version, matching version file already present in Nexus")
  }
  else
    console.log("Passed: No matching version present in Nexus")
}

export function checkVersion() {
  const exp = require('constants');
  const fs = require('fs');
  const yaml = require('js-yaml');
  var nexusRepo;
  var version;
  var exporter;

  try {
    const content = fs.readFileSync('./convoy.yaml', 'utf8');
    const data = yaml.load(content);
    var language = data.language
    if (language === 'terraform') {
      modifiedFiles = process.env.CHANGED_MODIFIED_FILES
      pathsArray = modifiedFiles.split(" ");
      dir = pathsArray.map(path => path.split("/")[0]);
      uniqueDirectories = [...new Set(dir)];
      modifiedDir = uniqueDirectories.join(" ");
      console.log(modifiedDir);
      const directories = modifiedDir.split(' ');
      const excludeDirectories = ['.github', 'convoy.yaml', '.gitignore', 'README.md'];
      for (let i = 0; i < directories.length; i++) {
        console.log(directories[i]);
        const directory = directories[i];
        if (excludeDirectories.includes(directory)) {
          continue;
        }
        const path = `./${directories[i]}/convoy.yaml`
        const contentDir = fs.readFileSync(path, 'utf8');
        const dataDir = yaml.load(contentDir);
        exporter = dataDir.generates.artifacts[0].name
        version = dataDir.version
        try {
          checkNexusVersion(process.env.NEXUS_PUSH_REPOS_M2, exporter, version);
        } catch (e) {
          console.error(e);
          process.exit(1);
        }
      }
      process.exit(0);
    }
    else if (language === 'helm') {
      const buildFunction = data.generates.helmCharts[0].buildFunction
      anyModified = process.env.ANY_MODIFIED
      if (buildFunction === 'helm-template' && anyModified === 'false') {
        console.log("No change in services/**.Skipping version checks")
        process.exit(0);
      }
      else {
        const path = data.generates.helmCharts[0].chartPath
        const contentHelm = fs.readFileSync(path, 'utf8');
        const dataHelm = yaml.load(contentHelm);
        version = dataHelm.version
        exporter = data.generates.helmCharts[0].name
        nexusRepo = process.env.NEXUS_PUSH_REPOS_HELM
      }
    }
    else if (language === 'python') {
      version = data.version
      exporter = data.generates.artifacts[0].name
      exporter = exporter.replaceAll('-', '_')
      nexusRepo = process.env.NEXUS_PUSH_REPOS_PY
    }
    else {
      version = data.version;
      exporter = data.generates.artifacts[0].name
      nexusRepo = process.env.NEXUS_PUSH_REPOS_M2
    }
    if (version === undefined || exporter === undefined) {
      console.log("Required parameters not present in convoy.yaml, skipping check nexus version")
      process.exit(0);
    }
  } catch (error) {
    console.log("convoy.yaml not present in repository or missing key. skipping check nexus version.")
    console.error('Error:', error.message)
    process.exit(0);
  }
  try {
    checkNexusVersion(nexusRepo, exporter, version)
  } catch (e) {
    console.error(e);
    process.exit(1);
  }
}