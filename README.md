# ci-pipelines

GitHub Actions pipelines shared by my repositories. A project keeps only thin caller
workflows; the logic lives here as [reusable workflows](https://docs.github.com/actions/sharing-automations/reusing-workflows).

## Layout

```
.github/workflows/
  ai-teammate.yml   reusable: issue -> agent -> pull request (DMTools + dmtools-agents)
  gradle-ci.yml     reusable: build and test a Gradle project
  self-test.yml     actionlint and shellcheck for this repository
templates/          the caller workflows written into each project
scripts/
  sync.sh           render the templates into every repository of repos.conf and push a branch
  set-secrets.sh    set the secrets from the environment with gh
repos.conf          the projects and their parameters
```

## Using it from a project

1. Run `scripts/sync.sh owner/repo`. It pushes the branch `ci/sync-pipelines` with
   `.github/workflows/issue-teammate.yml` and `ci.yml`; open and merge that pull request.
2. Set the secrets `PAT_TOKEN` and `CLAUDE_CODE_API_KEY` (`scripts/set-secrets.sh`, or by hand).
3. Enable Issues and Actions, create the label `dmtools:develop`.
4. Put the project-specific part next to the code: `.dmtools/config.js` (base branch,
   repository) and `.dmtools/prompts/*.md` (what the agent must know about this project).

Adding the label `dmtools:develop` to an issue now runs the agent on that issue.

## One-time setup of this repository

- **Access**: Settings -> Actions -> General -> Access -> "Accessible from repositories owned by
  the user". Without it, private projects cannot call these workflows.
- **Versions**: callers pin `@v1`. After a change that is safe for every project, move the tag:
  `git tag -f v1 && git push -f origin v1`. Try a risky change on one project first by changing
  its caller to `@<branch>`.
- **Callers** take `PIPELINES_REF` (default `v1`) from the environment when `sync.sh` runs.

## Things to know

- In a reusable workflow `github.*` is the *caller's* context and `actions/checkout` checks out
  the *caller*. To use files of this repository inside a workflow, check it out separately.
- Triggers (`on: issues`, `on: pull_request`) must be in the project; that is why the thin
  callers exist.
- `secrets: inherit` is documented for organizations; for a personal account the callers pass
  the secrets explicitly.
- `ai-teammate.yml` builds DMTools from `ba3a/dm.ai` because no release has the GitHub Issues
  tracker yet. Set `dmtools_fork_repo: ''` (and pin `dmtools_release`) once one does.
- The agent runs with `bypassPermissions` on an ephemeral runner, like the other providers of
  dmtools-agents. Scope `PAT_TOKEN` to the project (fine-grained: Contents, Pull requests, Issues,
  Actions read/write; no Workflows, no Administration) and keep branch protection on.

## Status

Written, not yet run. The first run of `ai-teammate.yml` as a reusable workflow, and the
`agents` checkout used when a project has no submodule, are untested.
