async function createTag() {
  const fs = require('fs');
  const yaml = require('js-yaml');
  const github = require('@actions/github');
  const content = fs.readFileSync('./convoy.yaml', 'utf8');
  const data = yaml.load(content);
  var language = data.language
  var version = data.version
  var uses_custom_version = "false"
  var tag_exists = process.env.TAG_EXISTS
  var current_tag = process.env.CURRENT_TAG
  var base_ref = process.env.BASE_REF
  var tags = process.env.TAGS
  var merge_commit_sha = process.env.MERGE_COMMIT_SHA
  var owner = process.env.OWNER
  var repo = process.env.REPO
  if (tag_exists === 'true') {
    new_tag = current_tag
    if (language === 'helm' || version !== undefined) {
      uses_custom_version = "true"
    }
    console.log("Skipping New tag creation")
  } else {
    if (language === 'helm') {
      const path = data.generates.helmCharts[0].chartPath
      const contentHelm = fs.readFileSync(path, 'utf8');
      const dataHelm = yaml.load(contentHelm);
      new_tag = dataHelm.version
      uses_custom_version = "true"
    } else {
      if (version !== undefined) {
        uses_custom_version = "true"
      }
      latest_tag = '0.0.0'
      // process multiple tags if any
      tags = tags.split(' ')
      if (tags.length == 1) {
        latest_tag = tags[0]
      } else {
        if (base_ref == "main") {
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
          tag_base = base_ref.substring(4).split(".").slice(0, 2)
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
      if (latest_tag == '' || latest_tag === undefined) {
        console.log("Couldn't determine the latest tag, exiting. Retry manually..")
        process.exit(1);
      }

      // increase the minor version lineraly to get the new tag
      tag_parts = latest_tag.split('.')
      new_tag = [tag_parts[0], tag_parts[1], parseInt(tag_parts[2]) + 1].join('.')

    }

    // head of the branch needs to be tagged
    sha_to_tag = merge_commit_sha

    console.log("Creating tag: " + new_tag + " against commit " + sha_to_tag)

    result = await github.rest.git.createTag({
      owner: owner,
      repo: repo.split('/')[1],
      tag: new_tag,
      message: 'Tag created by CI pipeline',
      type: 'commit',
      object: sha_to_tag
    });

    console.log(result)

    fullTagName = "refs/tags/" + new_tag

    console.log("Updating tag with REF: " + fullTagName)

    newRef = await github.rest.git.createRef({
      owner: owner,
      repo: repo.split('/')[1],
      ref: fullTagName,
      sha: sha_to_tag
    });
    console.log('Ref updated.');
  }
  core.setOutput('tag_ref', new_tag)
  core.setOutput('uses_custom_version', uses_custom_version)
}

createTag();