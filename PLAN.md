# Fix remaining build error and verify Swift 6.2 compilation

**What's broken:**

- One remaining reference to a non-existent log category (`.general`) in the Import/Export screen causes a build failure

**Fix:**

1. Replace `category: .general` with `category: .system` in the Import/Export view (line 460) — `.general` doesn't exist in the log category list
2. Run a full build to verify everything compiles cleanly
3. If additional errors surface from the build, fix them iteratively until the build succeeds

