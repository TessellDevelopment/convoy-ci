function findLatestTag() {
  var source_branch = process.env.SOURCE_BRANCH
  var tags = process.env.TAGS
  console.log("Tags are " + tags)
  latest_tag = '0.0.0'
  // process multiple tags if any
  tags = tags.split(' ')
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
      tag_base = source_branch.substring(4).split(".").slice(0, 2)
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
  core.setOutput('tag_ref', latest_tag)
}

findLatestTag();