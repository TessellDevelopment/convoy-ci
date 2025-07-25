# convoy-ci

## Testing

In order to perform any kind of testing, a few crucial changes are always needed to be made in the workflow definitions.

If any of those changes are missed, there's a chance that the tester may try some testing which do not result as expected,
leading to confusion and wastage of time trying to debug why things are not working as expected.

To avoid manual dependency for making those crucial changes, 2 scripts are placed inside the `scripts` folder.
The purpose of these scripts is to make testing easier, by ensuring that the minimal set of changes required to
get started with testing, is taken care of automatically.

### Steps to start testing:

1. Create a test branch, by checking out from the `main` branch:
   ```
   git checkout -b <branchName>
   ```
2. Run the `add-test-branch-customizations` script to add the required crucial changes for testing:
   ```
   .scripts/add-test-branch-customizations <branchName>
   ```

This prepares the branch for testing purposes.

### Steps to remove testing related changes:

Once the testing is completed, in order to get the branch merged to the `main` branch via a PR, all the changes that were added by the above script must be removed.

In order to to do so, simply run the `cleanup-test-branch-customizations` script to remove the changes:

```
.scripts/cleanup-test-branch-customizations <branchName>
```
