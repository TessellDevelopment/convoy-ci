const core = require('@actions/core');

async function run() {
  try {
    console.log("Tags are " + process.env.TAGS);
    let latestTag = '0.0.0';
    const tags = process.env.TAGS.split(' ');

    if (tags.length === 1) {
      console.log("There is only one tag. Using it." + tags[0]);
      latestTag = tags[0];
    } else {
      if (process.env.SOURCE_BRANCH === "main") {
        for (let i in tags) {
          const tag = tags[i];
          console.log("Checking tag " + tag);
          if (latestTag === null) {
            latestTag = tag;
            continue;
          }
          const latestParts = latestTag.split(".");
          const tagParts = tag.split(".");
          for (let i = 0; i < tagParts.length; i++) {
            if (parseInt(tagParts[i]) < parseInt(latestParts[i])) {
              console.log("Skipping " + tag);
              break;
            }
            if (parseInt(tagParts[i]) > parseInt(latestParts[i])) {
              latestTag = tag;
              console.log("Setting " + latestTag);
              break;
            }
          }
        }
      } else {
        const tagBase = process.env.SOURCE_BRANCH.substring(4).split(".").slice(0, 2);
        latestTag = tagBase.join(".") + ".0";
        for (let i in tags) {
          const tag = tags[i];
          console.log("branch - Checking tag " + tag);
          const tagParts = tag.split(".");
          if (tagBase[0] == tagParts[0] && tagBase[1] == tagParts[1]) {
            const latestParts = latestTag.split(".");
            if (parseInt(latestParts[2]) < parseInt(tagParts[2])) {
              latestTag = tag;
            }
          }
        }
      }
    }

    console.log("Latest tag: " + latestTag);

    if (latestTag === '' || latestTag === undefined) {
      console.log("Couldn't determine the latest tag, exiting. Retry manually..");
      process.exit(1);
    }

    core.setOutput('tag_ref', latestTag);
  } catch (error) {
    core.setFailed(error.message);
  }
}

run();
