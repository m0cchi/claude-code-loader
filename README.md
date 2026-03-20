# ccloader

`ccloader` is a small Bash CLI for managing Claude Code resources stored under `.claude` in external Git repositories.

It supports:

- `ccloader add <name> <gitrepository>`
- `ccloader update`
- `ccloader load [--all] <name>`

## Storage layout

Managed repositories are cloned into:

```text
~/.claude-code-loader/repositories/<name>
```

`<name>` may contain only letters, numbers, `.`, `_`, and `-`.

`ccloader add` accepts repositories even if they do not currently contain a `.claude` directory. In that case it prints a warning, and `load` will fail until `.claude` exists.

## Load behavior

`ccloader load` walks upward from the current directory and uses the first `.claude` directory it finds as the target.

The source side is always:

```text
~/.claude-code-loader/repositories/<name>/.claude
```

Each visible item directly under that source `.claude` directory is treated as a loadable entry, for example `skills`, `agents`, or any other file/directory. Hidden entries such as `.gitkeep` are ignored.

By default, `load` shows a numbered list and prompts for one or more entries to link.

```bash
ccloader load myrepo
```

For non-interactive bulk linking, use:

```bash
ccloader load --all myrepo
```

Links are created directly under the nearest target `.claude` directory. Existing paths are never overwritten. If any selected target already exists, the command fails before creating any links.

## Update behavior

`ccloader update` runs `git pull --ff-only` for every directory under `~/.claude-code-loader/repositories`.

- Successful updates are summarized on stdout.
- Failures are summarized on stderr after all repositories have been processed.
- The command exits non-zero if any repository fails.

## PATH setup

Expose `ccloader` on your `PATH` however you prefer. For example, place this repository somewhere stable and add its path to your shell configuration manually.
