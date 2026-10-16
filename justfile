# This repository's automation -- the template's, not a generated project's (template/justfile is
# that). The commands are the workflows' (.github/workflows/). Formatted with
# `just --fmt --unstable`.

# The GitHub repository the changelog's compare links name: cliff.toml is the template's own copy,
# which names none.
export repository := "veralvx/rust-template"

[doc("List the recipes")]
default:
    @just --list --unsorted

# python-liquid stands in for cargo-generate's Liquid; the versions are tools/requirements.txt's,
# into .venv -- made again when its Python no longer runs (a Nix store path collected, say).
[doc("Every templated file rendered for every answer combination, and checked (tools/render-check.py)")]
render-check:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! .venv/bin/python -c '' 2> /dev/null; then python3 -m venv --clear .venv; fi
    .venv/bin/pip install --quiet --disable-pip-version-check --requirement tools/requirements.txt
    .venv/bin/python tools/render-check.py

# With the real cargo-generate, the answers the smoke test gives, under target/ (which git ignores
# here). cargo-generate makes no repository inside this one, and nixpkgs' build none at all: so
# `git init`, the first commit made. Prints the project's path alone.
[doc("The template generated: just generate <bin|lib|both|workspace>, into target/<kind>/demo")]
[positional-arguments]
generate kind:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$1" in
        bin | lib | both | workspace) ;;
        *)
            echo "error: the kind is one of bin, lib, both, workspace (got '$1')" >&2
            exit 1
            ;;
    esac
    destination="target/$1"
    rm -rf "$destination"
    mkdir -p "$destination"
    cargo-generate generate --path "$PWD" template --name demo --destination "$destination" --silent \
        -d project_kind="$1" -d "description=Does a thing." -d "author_name=Jane Doe" \
        -d author_email=jane@example.com -d github_username=jane -d "license=MIT OR Apache-2.0" \
        -d msrv=1.97 -d keywords=cli,parser -d categories=command-line-utilities >&2
    cd "$destination/demo"
    if [ ! -e .git ]; then git init --quiet -b main; fi
    git add --all
    git -c user.name=generate -c user.email=generate@localhost commit --quiet \
        -m "chore: initial commit from template"
    echo "$destination/demo"

# The smoke test's generate job, its releases aside: in the generated flake's dev shell -- the
# toolchain rust-toolchain.toml pins, Miri's nightly its own shell -- `just checks`, the flake's
# checks built last -- and `just fmt`, which must change nothing. It needs Nix.
[doc("The template generated, then its own checks run: just smoke <bin|lib|both|workspace>")]
[positional-arguments]
smoke kind:
    #!/usr/bin/env bash
    set -euo pipefail
    project="$(just generate "$1")"
    cd "$project"
    just --fmt --check --unstable
    nix develop --command just checks
    nix develop --command just fmt
    git diff --exit-code

# shellcheck and shfmt over every shell script git does not ignore -- shfmt finds them, by extension
# or shebang, and formats them as .editorconfig says -- and over this justfile's shell script
# recipes (a sh, bash, dash or ksh shebang), which no file holds: each taken from `just --dump`,
# the names the justfile exports declared before it for shellcheck (their values are just's
# expressions, not shell's), formatted in the justfile's own style (4 spaces). A script recipe
# takes its values as arguments, never as `{{ }}` spliced into its text, and names its shell in a
# shebang, not a `[script]` attribute (whose body holds none to read): both are refused here.
[doc("The shell: shellcheck and shfmt over the scripts, the git hooks and the justfile's script recipes")]
shell-check:
    #!/usr/bin/env bash
    set -euo pipefail
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    failed=0
    just shfmt --diff || failed=1
    scripts=()
    while IFS= read -r file; do
        scripts+=("$file")
    done < <(just shfmt --find)
    if [ "${#scripts[@]}" -gt 0 ]; then
        shellcheck "${scripts[@]}" || failed=1
    fi
    dump="$(just --dump --dump-format json)"
    while IFS= read -r recipe; do
        if jq -e --arg recipe "$recipe" '.recipes[$recipe].attributes | any(type == "object" and has("script"))' <<< "$dump" > /dev/null; then
            echo "error: $recipe: a [script] recipe -- name its shell in a shebang instead" >&2
            failed=1
            continue
        fi
        # its shebang's program, or the one `env` runs, past env's options (`-S`)
        read -r -a shebang < <(jq -r --arg recipe "$recipe" '.recipes[$recipe].body[0][0] | ltrimstr("#!")' <<< "$dump")
        program="${shebang[0]-}"
        program="${program##*/}"
        if [ "$program" = env ]; then
            program=""
            for word in "${shebang[@]:1}"; do
                if [[ $word != -* ]]; then
                    program="$word"
                    break
                fi
            done
        fi
        case "$program" in
            sh | bash | dash | ksh) ;;
            *) continue ;;
        esac
        jq -r --arg recipe "$recipe" '
            .recipes[$recipe].body
            | map(map(if type == "string" then . else error("\($recipe): an interpolation in a script recipe: pass the value as an argument") end) | join(""))
            | join("\n")
        ' <<< "$dump" > "$work/$recipe" || {
            failed=1
            continue
        }
        # after the shebang, the variables just exports to it: the `export`ed assignments and
        # `$`-parameters, or every one under `set export`
        {
            head -n 1 "$work/$recipe"
            jq -r --arg recipe "$recipe" '
                .settings.export as $all
                | (.assignments[], .recipes[$recipe].parameters[])
                | select($all or .export)
                | "export \(.name)="
            ' <<< "$dump"
            tail -n +2 "$work/$recipe"
        } > "$work/$recipe.with-exports"
        (cd "$work" && shellcheck --shell="$program" "$recipe.with-exports") || failed=1
        (cd "$work" && shfmt --diff --indent 4 --case-indent --space-redirects --binary-next-line "$recipe") || failed=1
    done < <(jq -r '.recipes | to_entries[] | select(.value.shebang) | .key' <<< "$dump")
    exit "$failed"

# shfmt over every shell script git does not ignore and that exists (shfmt finds them, by extension
# or shebang): `just shfmt --find` lists them, `--diff` checks, `--write` formats.
[positional-arguments]
[private]
shfmt mode:
    #!/usr/bin/env bash
    set -euo pipefail
    # a process substitution's failure goes unseen (set -e): outside a repository, ls-files' would
    git rev-parse --is-inside-work-tree > /dev/null
    files=()
    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then files+=("$file"); fi
    done < <(git ls-files -z --cached --others --exclude-standard)
    # with no file, shfmt would read stdin; a command substitution, so a failing shfmt stops here
    found=""
    if [ "${#files[@]}" -gt 0 ]; then found="$(shfmt --find "${files[@]}")"; fi
    if [ -z "$found" ]; then exit 0; fi
    scripts=()
    while IFS= read -r file; do
        scripts+=("$file")
    done <<< "$found"
    case "$1" in
        --find) printf '%s\n' "${scripts[@]}" ;;
        *) shfmt "$1" "${scripts[@]}" ;;
    esac

# The justfile's own script recipes formatted as `just shell-check` holds them: each sh, bash, dash
# or ksh recipe taken from `just --dump`, through shfmt in the justfile's style, and put back in
# its place, 4 spaces in. A `[script]` recipe, or one with a `{{ }}` in it, is shell-check's to
# refuse, and is left as it is.
[private]
shfmt-recipes:
    #!/usr/bin/env bash
    set -euo pipefail
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    dump="$(just --dump --dump-format json)"
    # the shebang's program, or the one `env` runs, past env's options (`-S`), as shell-check reads it
    names="$(jq -r '
        .recipes[]
        | select(.shebang)
        | select(.attributes | any(type == "object" and has("script")) | not)
        | select(all(.body[][]; type == "string"))
        | select(
            (.body[0][0] | ltrimstr("#!") | split(" ") | map(select(. != ""))) as $words
            | ($words[0] | split("/") | last) as $program
            | if $program == "env" then [$words[1:][] | select(startswith("-") | not)][0] else $program end
            | IN("sh", "bash", "dash", "ksh")
        )
        | .name
    ' <<< "$dump")"
    if [ -z "$names" ]; then exit 0; fi
    while IFS= read -r recipe; do
        jq -r --arg recipe "$recipe" '.recipes[$recipe].body | map(join("")) | join("\n")' <<< "$dump" > "$work/body"
        shfmt --indent 4 --case-indent --space-redirects --binary-next-line "$work/body" > "$work/formatted"
        if cmp -s "$work/body" "$work/formatted"; then continue; fi
        # the recipe's line, then its body in place of the old: every line to the next at the
        # margin, less the blank lines before that one
        awk -v recipe="$recipe" -v formatted="$work/formatted" '
            function body(line) {
                while ((getline line < formatted) > 0) print (line == "" ? "" : "    " line)
                close(formatted)
            }
            state == 1 && $0 == "" { blanks++; next }
            state == 1 && /^[ \t]/ { blanks = 0; next }
            state == 1 {
                body()
                for (; blanks > 0; blanks--) print ""
                state = 2
            }
            state == 0 && $0 ~ ("^@?" recipe "([ \t][^:]*)?:") && $0 !~ ("^" recipe "[ \t]*:=") { state = 1 }
            { print }
            END { if (state == 1) body() }
        ' justfile > "$work/justfile"
        cat "$work/justfile" > justfile
    done <<< "$names"

# The template's too: its justfile's script recipes, which only its own `just shell-check` reads.
[doc("The template's `just shell-check`, in template/")]
template-shell-check:
    cd template && just shell-check

# actionlint runs shellcheck on each `run:` script too, when it is on PATH.
[doc("The workflows linted (actionlint): this repository's and the template's")]
actionlint:
    actionlint
    actionlint template/.github/workflows/*.yml

# Every formatter a check holds the files to: the shell (template/'s too), both justfiles, the
# Markdown and the TOML (template/'s are a generated project's), then the Nix through `nix fmt`
# (nixfmt, and shfmt and just's own again) -- without Nix, it stops there, the rest formatted.
[doc("Format the shell scripts, the justfiles, the Markdown and the TOML, then the Nix (modifies files)")]
fmt:
    just shfmt --write
    just shfmt-recipes
    cd template && just shfmt-recipes
    just --fmt --unstable
    just --justfile template/justfile --fmt --unstable
    dprint fmt
    nix fmt

[doc("Markdown and TOML formatted (dprint.json)")]
dprint-check:
    dprint check

# Here and in template/ alike: render-check holds the two plugin lists equal.
[doc("dprint's plugins to their latest releases (dprint.json, here and the template's), then everything rechecked")]
dprint-update:
    dprint config update
    cd template && dprint config update
    dprint check

[doc("Every commit conventional (cog.toml)")]
cog:
    cog check

# `nix fmt -- --ci` formats -- treefmt has no check-only mode -- and fails if that changed a file:
# look at the change, then commit it. The flake's `format` check is the same verdict, on a copy.
[doc("The flake: its formatter's verdict (`nix fmt`), every system evaluated, this one's checks built")]
nix:
    nix fmt -- --ci
    nix flake check --no-build --all-systems
    nix flake check

# `nix` last: the slowest, and the one a machine without Nix cannot run. The flake sees git's files
# only: a new file is invisible to it until `git add`ed. `just smoke <kind>` is the smoke test's,
# and slow.
[doc("Every check but the smoke test, the flake's last")]
checks: render-check shell-check template-shell-check actionlint dprint-check cog nix

# Opt-in, as every git hook is: a clone never installs one, so CI stays the gate.
# `git config --unset core.hooksPath` turns them off again.
[doc("Use .githooks: the shell, the workflows and dprint before a commit; Conventional Commits for the message and before a push")]
install-hooks:
    git config core.hooksPath .githooks

[doc("The changelog (cliff.toml): `just changelog --unreleased` previews the next release")]
[positional-arguments]
changelog *args:
    git cliff --offline --github-repo "$repository" "$@"

# Every step here, in order. The template has no version file: a release is its tag, `v<version>`,
# and the changelog's section; the first is 0.1.0, whatever the level. The tag makes the GitHub
# release (release.yml). No tests here: what is released is origin's main, which CI checks.
[doc("Release: just release <major|minor|patch> -- changelog, commit, tag, push")]
[positional-arguments]
release level:
    #!/usr/bin/env bash
    set -euo pipefail

    # 0. The level -- passed as $1, never spliced into this script's text
    case "$1" in
        major | minor | patch) level="$1" ;;
        *)
            echo "error: the level must be major, minor or patch (got '$1')" >&2
            exit 1
            ;;
    esac

    # 1. From a clean main that is origin's -- pushed, so the commit released is the one CI ran on
    if [ -n "$(git status --porcelain)" ]; then
        echo "error: the working tree is not clean: commit or stash first" >&2
        exit 1
    fi
    if [ "$(git branch --show-current)" != main ]; then
        echo "error: a release is cut from main" >&2
        exit 1
    fi
    git fetch origin
    if ! git rev-parse --quiet --verify origin/main > /dev/null; then
        echo "error: origin has no main: push it first" >&2
        exit 1
    fi
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
        echo "error: main is not origin/main: push (and let CI pass) or pull first" >&2
        exit 1
    fi

    # 2. The version: the latest tag's, bumped by the level; 0.1.0 with no tag yet
    latest="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname | head -n 1)"
    if [ -z "$latest" ]; then
        version=0.1.0
    else
        IFS=. read -r major minor patch <<< "${latest#v}"
        case "$level" in
            major) version="$((major + 1)).0.0" ;;
            minor) version="$major.$((minor + 1)).0" ;;
            patch) version="$major.$minor.$((patch + 1))" ;;
        esac
    fi
    tag="v$version"
    if git rev-parse --quiet --verify "refs/tags/$tag" > /dev/null; then
        echo "error: $tag is already tagged" >&2
        exit 1
    fi

    # 3. Something to release: a commit since the last tag that enters the changelog
    entries="$(just changelog --unreleased --context | jq '[.[].commits | length] | add // 0')"
    if [ "$entries" -eq 0 ]; then
        echo "error: nothing to release -- no commit since the last tag would enter the changelog" >&2
        exit 1
    fi

    # If anything below fails before the commit, put back what it changed: the tree was clean, so
    # HEAD's files are exactly that, and a changelog the first release created goes.
    restore() {
        echo "Release aborted -- restoring the files it changed." >&2
        git reset --quiet --hard HEAD
        if ! git cat-file -e HEAD:CHANGELOG.md 2> /dev/null; then
            rm -f CHANGELOG.md
        fi
    }
    trap restore ERR

    # 4. The changelog, the release's section on top
    just changelog --tag "$tag" --output CHANGELOG.md

    # 5. Commit, then change the trap: a refused commit (a git hook) still restores the files, but
    #    once committed, a failure is finished by hand -- a re-run would bump again
    git add CHANGELOG.md
    git commit -m "chore(release): $tag"
    finish() {
        echo "error: $tag is committed; finish it by hand: git tag -a $tag -m 'Release $tag' (unless tagged), then git push --atomic origin main $tag" >&2
    }
    trap finish ERR
    git tag -a "$tag" -m "Release $tag"

    # 6. The commit and the tag together, both or neither
    git push --atomic origin main "$tag"
    echo "Released $tag: release.yml takes it from here."
