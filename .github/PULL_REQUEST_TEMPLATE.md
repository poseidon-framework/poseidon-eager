---
name: "Add: [PACKAGE_NAME]"
about: Add a new package for processing
labels: "new package"
---

<!--
# poseidon-framework/poseidon-eager package request

Hello there!

Thanks for suggesting a new publication to add to the Poseidon Package Directory!
Please ensure you are completing all the TODOs outlined in these comments for each section.
-->

Closes #XXX <!-- TODO: Please link the issue requesting the package here. -->

## PR Checklist
- [ ] The PR contains a sequencingSourceFile (`.ssf`) for the package. 
- [ ] The name of the `.ssf` file(s) matches the package name (i.e. `packages/2023_my_package/2023_my_package.ssf`).
- [ ] Comment `@delphis-bot create backbone` to this pull request to awaken Poseidon's trusty helper. (This should be repeated whenever changes are made to the SSF file contents).
This will add a number of files to the PR. Check that they are all there.
- [ ] `packages/{package_name}/{package_name}.tsv` was added to the PR.
- [ ] `packages/{package_name}/{package_name}.tsv_patch.sh` was added to the PR from template.
- [ ] `packages/{package_name}/script_versions.txt` was added to the PR.
- [ ] `packages/{package_name}/{package_name}.config` was added to the PR from template.
<!-- TODO: Follow the steps outlined above and tick them off as you go. -->

## Human validation
<!-- TODO: Please do the minimal validation of the files outlined below -->

### Package TSV file (`*.tsv`)
  - [ ] I confirm that the `udg`, `library_built` columns are correct for each library.
  - [ ] I confirm that the `R1_target_file` and `R2_target_file` columns point to the correct FastQ files for the library (i.e. consistent with SSF file).

### Package config file (`*config`)
The template config file includes a few TODO statements, and information about them. Please ensure that you:
  - [ ] I have selected the appropriate config for the CaptureType of the package.
  - [ ] If any nf-core/eager parameters need to be altered from their defaults, I have added them within the `params` section at the end of the package config file.
