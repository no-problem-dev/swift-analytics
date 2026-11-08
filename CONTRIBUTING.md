# Contributing

Thanks for taking the time to look at this package.

## Reporting a problem

Open an issue with the smallest example that reproduces it, the Swift and Xcode
versions you're on, and the platform you're targeting. A failing test is the
clearest possible report.

## Working on a change

```bash
swift build
swift test
```

`swift test` also runs the catalog generator's own tests (`Scripts/tests/`, Python standard
library only). To run just those: `python3 -m unittest discover -s Scripts/tests`.

**There is no CI.** Run both commands locally and make sure they pass before
opening a pull request.

Documentation lives in the DocC catalog under `Sources/*/*.docc/`. Public
declarations are documented with `///` comments, in English.

## Releasing

Maintainers only. Rename `## [Unreleased]` in `CHANGELOG.md` to the new version,
merge to `main`, then tag and push:

```bash
git tag x.y.z && git push origin x.y.z
```

Versions follow SemVer (in 0.x, a breaking change is a minor). No GitHub Release is created.
