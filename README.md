# MTSX Linter (Raku + Java)

- `lint/regex-checker/` — Java Maven project (RegexChecker).
  - Build with `mvn package` to produce jar `target/regex-checker-0.1.0-jar-with-dependencies.jar`.
  - Usage: `java -jar lint/regex-checker-0.1.0-jar-with-dependencies.jar --validate "<pattern>"`

- `lint/mtsx_lint_raku.raku` — Raku linter that:
  - Finds `.mtsx` files (via `git ls-files` or globs)
  - Extracts regex literals (`/.../flags`)
  - Calls Java `regex-checker` to validate Java regex compilation; merges notes into errors/warnings depending on mode.
  - Usage:
    ```bash
    raku tools/mtsx_lint_raku.raku --jar regex-checker/target/regex-checker-0.1.0-jar-with-dependencies.jar --mode strict --json
    ```

## Quick steps

1. Build Java checker:
   ```bash
   cd lint/regex-checker
   mvn -q package
   cd ../..
   ```

2. Run Raku linter:
   ```bash
   raku lint/mtsx-lint.raku --mode lenient --with-java lint/regex-checker/target/regex-checker-0.1.0-jar-with-dependencies.jar --json > lint-result.json
   ```

## CI notes

- The linter expects `java` and `raku` (Rakudo) to be available in the runner.
- Example approach:
  1. Use `actions/setup-java` to install Java and build the jar.
  2. Use a container with Rakudo (e.g. `rakudo/rakudo`) and ensure `java` is available in that container, or install Rakudo on the runner.
  3. Run the Raku linter pointing to the built jar.
