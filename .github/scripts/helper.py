import os
import git
import yaml
import sys

tagNumber = sys.argv[1]

#git.Repo.clone_from('https://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@github.com/rajeshtessell/demo-backend/', 'demo-backend')
cmd = f"git config --global user.email 'kambala.rajesh@tessell.com' "
os. system(cmd)
#cmd = f"git config --global user.name 'rajeshtessell' "
#os. system(cmd)
#cmd = f"git checkout -b 'update-distribution' "
os. system(cmd)
cmd = f"cd demo-backend "
cmd = f"cd tessell-iam "
os. system(cmd)

with open(f"/home/runner/work/tessell-template-repo/tessell-template-repo/tessell-iam/values.yaml", "r+") as f:
    data = yaml.load(f, Loader=yaml.FullLoader)
    data["image_tag"] = tagNumber
    f.seek(0)
    yaml.dump(data, f)
    f.truncate()
#cmd = f"git add -A"
#os. system(cmd)
#cmd = f"git commit -m 'updating values_yaml' "
#os. system(cmd)
#cmd = f"git push origin update-distribution"
#os. system(cmd)
