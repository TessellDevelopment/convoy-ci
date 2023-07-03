const core = require('@actions/core');

try {
  console.log(`Tags are ${process.env.INPUT_TAGS}`);
  let latest_tag = '0.0.0';
  const tags = process.env.INPUT_TAGS.split(' ');

  if (tags.length === 1) {
    console.log(`There is only one tag. Using it: ${tags[0]}`);
    latest_tag = tags[0];
  } else {
    if (process.env.INPUT_SOURCE_BRANCH === 'main') {
      for (let i = 0; i < tags.length; i++) {
        const tag = tags[i];
        console.log(`Checking tag ${tag}`);
        if (latest_tag === null) {
          latest_tag = tag;
          continue;
        }
        const latest_parts = latest_tag.split('.');
        const tag_parts = tag.split('.');
        for (let j = 0; j < tag_parts.length; j++) {
          if (parseInt(tag_parts[j]) < parseInt(latest_parts[j])) {
            console.log(`Skipping ${tag}`);
            break;
          }
          if (parseInt(tag_parts[j]) > parseInt(latest_parts[j])) {
            latest_tag = tag;
            console.log(`Setting ${latest_tag}`);
            break;
          }
        }
      }
    } else {
      const tag_base = process.env.INPUT_SOURCE_BRANCH.substring(4).split('.').slice(0, 2);
      latest_tag = `${tag_base.join('.')}.0`;
      for (let i = 0; i < tags.length; i++) {
        const tag = tags[i];
        console.log(`branch - Checking tag ${tag}`);
        const tag_parts = tag.split('.');
        if (tag_base[0] === tag_parts[0] && tag_base[1] === tag_parts[1]) {
          const latest_parts = latest_tag.split('.');
          if (parseInt(latest_parts[2]) < parseInt(tag_parts[2])) {
            latest_tag = tag;
          }
        }
      }
    }
  }

  console.log(`Latest tag: ${latest_tag}`);
  if (latest_tag === '' || latest_tag === undefined) {
    console.log("Couldn't determine the latest tag, exiting. Retry manually..");
    process.exit(1);
  }

  core.setOutput('tag_ref', latest_tag);
} catch (error) {
  core.setFailed(error.message);
}
