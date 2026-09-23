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

## 6. Submit and Tag

`main` accepts changes only through pull requests, so merge the release pull
request first and submit from an up-to-date `main`:

```sh
git switch main && git pull
Rscript -e "devtools::submit_cran()"
```

`submit_cran()` writes `CRAN-SUBMISSION` with the version and the SHA of
`HEAD`. The file is local state and is ignored by Git; do not commit it.
Submitting from a feature branch that is later squash-merged records a SHA
that never reaches `main`.

Once CRAN accepts the package, run `usethis::use_github_release()`. It tags
the recorded SHA, publishes the `NEWS.md` section as the GitHub release, and
deletes `CRAN-SUBMISSION`. Then open a pull request from
`usethis::use_dev_version()` to move to the next development version, which
also switches the pkgdown site back to `/dev/`.
