# Release Process

## 1. Prepare the Change Set

- Update `DESCRIPTION` for version or dependency changes.
- Add concise, user-facing bullets to `NEWS.md`; put function names early and
  reference related issues as `(#123)`.
- Update roxygen comments for public APIs and add new topics to `_pkgdown.yml`.
- Edit `README.Rmd` and regenerate `README.md`; do not edit the generated file
  directly.
- Update vignettes when semantics, context behavior, or compatibility changes.
- Preserve the mpdecimal copyright and BSD-2-Clause notices in
  `inst/COPYRIGHTS` and `src/mpdecimal/COPYRIGHT.txt`.

## 2. Regenerate Documentation

```sh
air format .
Rscript -e "devtools::document()"
Rscript -e "devtools::build_readme()"
Rscript -e "pkgdown::check_pkgdown()"
```

Review changes to `NAMESPACE`, `man/`, and `README.md`; they should be
explainable by their source edits.

## 3. Validate Locally

```sh
Rscript -e "devtools::test()"
Rscript -e "devtools::check()"
Rscript -e "urlchecker::url_check()"
R CMD build .
```

The release target is zero errors, warnings, and actionable notes. For native
changes, also run the manually dispatched sanitizer, Valgrind, LTO, gctorture,
and rchk workflow before release.

## 4. Confirm CI and CRAN Metadata

GitHub Actions checks R release on Linux, macOS, and Windows, R devel on Linux
and Windows, and old-release on Linux. Confirm the coverage workflow and all
relevant native checks. Update `cran-comments.md` with the actual test
environments and check results; remove placeholders before submission. The
Windows R-devel job mirrors CRAN's incoming checks, so a separate win-builder
run is optional.

## 5. Final Review

- Install and load the built tarball in a clean R library.
- Verify `mpdecimal_version()` reports `4.0.1`.
- Read rendered README, reference pages, and the vignettes.
- Confirm examples do not depend on undeclared packages or network access.
- Confirm the Git diff contains no build products (`*.o`, `*.so`, check
  directories, or generated site files).
- Ensure commits are focused and the pull request lists every validation
  command used.

Tagging, publishing, and CRAN submission are deliberate maintainer actions;
they are not implied by completing the checks above.

## 6. Submit, Then Commit CRAN-SUBMISSION

`main` accepts changes only through pull requests, so merge the release pull
request first and submit from an up-to-date `main`:

```sh
git switch main && git pull
Rscript -e "devtools::submit_cran()"
```

Confirm the submission from CRAN's email. `submit_cran()` writes
`CRAN-SUBMISSION` with the version and the SHA of `HEAD`. Submit from `main`
itself: a SHA from a feature branch that is later squash-merged never reaches
`main`, and the tag would then mark a commit that `main` does not contain.

Then commit `CRAN-SUBMISSION` to `main`. It is tracked in Git and listed in
`.Rbuildignore`, so it never enters the tarball. Because `main` takes pull
requests, open one with only that file and merge it:

```sh
git switch -c cran-submission-<version>
git add CRAN-SUBMISSION
git commit -m "CRAN-SUBMISSION for <version>"
git push -u origin HEAD
gh pr create --label ci:docs --title "CRAN-SUBMISSION for <version>" --body "Record the <version> submission."
```

Merging it runs `.github/workflows/cran-release.yaml` (r-actions'
`cran-release.yml`). The workflow:

- tags the submitted commit with the bare version (`0.1.2`, not `v0.1.2`),
  as the earlier `0.1.0` and `0.1.1` tags are;
- creates the `decimal <version>` GitHub release, with that version's
  `NEWS.md` section as its notes;
- opens a pull request that bumps `main` to `<version>.9000` and adds the
  `# decimal (development version)` heading.

There is no manual tag or GitHub release step. A resubmission of the same
version writes a new `CRAN-SUBMISSION`, and committing it moves the tag.

Merge the bump pull request only once CRAN accepts the version. Then close out
the release with `pkg-post-cran`.
