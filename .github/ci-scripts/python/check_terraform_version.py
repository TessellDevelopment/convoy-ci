import os
import hcl2
import sys

terraform_files = os.environ.get("terraform_files")
version_missing = False
for terraform_file in terraform_files.split(","):
    with open(terraform_file, "r") as file:
        tf_file = hcl2.load(file)
    if "terraform" in tf_file and "required_providers" in tf_file["terraform"][0]:
        providers = tf_file["terraform"][0]["required_providers"]
        for provider in providers:
            for _provider, provider_info in provider.items():
                for key in provider_info:
                    if key == "version":
                        break
                else:
                    print(f"{terraform_file}: version is not present for {_provider} ")
                    version_missing = True
    if version_missing:
        sys.exit(1)
