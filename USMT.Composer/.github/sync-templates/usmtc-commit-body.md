# USMT.Composer Component Synchronization

## Summary

This automated update synchronizes the `${COMPONENT_NAME}` component from the source repository into the WinTwin.Fusion framework repository.

---

## Source

Repository: `${SOURCE_REPOSITORY}` <br>
Branch: `${SOURCE_BRANCH}` <br>
Commit: `${SOURCE_COMMIT}` <br>
Short Commit: `${SOURCE_COMMIT_SHORT}` <br>

## Source Pull Request

Pull Request: `#${PR_NUMBER}` <br>
Title: `${PR_TITLE}` <br>
Merged By: `${MERGED_BY}` <br>
Merged At: `${MERGED_AT}` <br>


## Target

Repository: `${TARGET_REPOSITORY}` <br>
Base Branch: `${TARGET_BASE_BRANCH}` <br>
Update Branch: `${TARGET_BRANCH}` <br>
Target Path: `${TARGET_PATH}` <br>

---

## Synchronised Files

${CHANGED_FILES}

---

## Excluded Files

The following files were intentionally excluded from the synchronization:
<!--
- `.gitignore`
- `ducc.wm.changelog.md`
-->

---

## Sync Metadata

A metadata file was generated at:

```text
${TARGET_PATH}/.usmtc-sync.json