# ci-pipelines

GitHub Actions pipelines shared by my repositories. A project keeps only thin caller
workflows; the logic lives here as [reusable workflows](https://docs.github.com/actions/sharing-automations/reusing-workflows).

## Layout

```
.github/workflows/
  ai-teammate.yml   reusable: one leg of the machine loop (dev, review or rework) for an issue
  sm.yml            reusable: the state machine tick that starts the review and rework legs
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
   `.github/workflows/issue-teammate.yml`, `ci.yml` and, when `repos.conf` names a machine author,
   `machine-sm.yml`; open and merge that pull request.
2. Set the secrets `PAT_TOKEN` and `CLAUDE_CODE_API_KEY` (`scripts/set-secrets.sh`, or by hand).
3. Enable Issues and Actions, create the labels `dmtools:plan` and `dmtools:develop`.
4. Put the project-specific part next to the code: `.dmtools/config.js` (base branch,
   repository) and `.dmtools/prompts/*.md` (what the agent must know about this project). With the
   state machine on, also set the label that starts development, so planned sub-issues start the
   same way: `issuePlanning: { devLabel: 'dmtools:develop' }`.

Label an issue to start the agent on it:

- `dmtools:plan` (the default way): the agent plans first. A small issue is kept whole and
  developed; a big one is split into ordered sub-issues, developed one at a time (see below).
- `dmtools:develop`: the agent develops the issue directly, without planning.

## The state machine

`sm.yml` is the machine loop of [dmtools-agents](https://github.com/IstiN/dmtools-agents): its rule
engine `agents/sm_github.json` runs on a tick and starts the next step from the labels, CI results
and merge state of the issues and pull requests. No AI model runs in a tick.

```
label dmtools:plan -> plan leg -> kept whole -> label dmtools:develop on the issue
                               -> split      -> sub-issues 1..N; the tick labels the next one
                                                dmtools:develop when the previous one is closed

label dmtools:develop -> dev leg -> pull request -> CI -> review leg -> pr_approved -> you merge
                                        ^              |
                                        +-- rework leg <-+  review findings, red CI, merge conflicts
```

- **Planning** is the `issue_planning` agent of dmtools-agents. A split issue gets the label
  `ai_planned` and a comment with the ordered steps; each step is a sub-issue whose description
  links the parent. The rule `plan-advance` starts one step at a time, in order, and closes the
  parent when every step is closed. Steps run sequentially: each one waits for you to merge the
  previous one.

- **Legs** are runs of the project's `issue-teammate.yml` (`ai-teammate.yml` here). The tick
  dispatches it with `leg` = `review` or `rework` and the issue or the pull request. A pull
  request without an issue is resolved to its issue from "Closes #N" or the `ai/gh-N` branch.
- **No merge.** `sm_rules` in `sm.yml` lists the rules that run, and the rules that merge are not
  in it. The pull request waits for you with the label `pr_approved`; the rule `close-on-merge`
  closes the issue after you merge. `merge-validated` and `validate-armed` are the upstream merge
  rules; they are left out on purpose and untested here.
- **Only the machine author's pull requests** get automatic review and rework, those opened by
  the login in the `machine_author` column of `repos.conf` (the owner of `PAT_TOKEN`). Put the label
  `agent:rework` or `agent:review` on any pull request to ask for a leg by hand.
- **Ticks** run after `CI` and `Issue Teammate` runs and every 30 minutes. Dispatch
  `machine-sm.yml` by hand with *dry run* on (the default) to read the plan without any effect.
- **Branches that are behind** are updated by a step of `sm.yml` (`gh pr update-branch` with the
  PAT), not by the upstream rule `silent-update-behind`: that rule runs a shell command DMTools on
  Java refuses and assumes the base branch is `main`.
- **A failing leg stops itself.** A leg whose agent produced no output (an exhausted API key, the
  turn cap, a crash), or whose work the post-action could not commit or push, fails red instead of
  ending green. After `max_failed_runs_per_hour` (default 3)
  failed runs with the same title, e.g. `rework · gh-5`, within an hour, the next run labels the
  issue `blocked`, comments once and stops before any setup; the state machine skips blocked items.
  Fix the cause and remove the label to resume.
- **CI must be dispatchable.** The tick starts CI on a pull request head itself, so the project's
  `ci.yml` has a `workflow_dispatch` trigger (the template has it).
- **Rework limits.** The agent rules cap rework by red heads; there is no other cost cap. Watch
  the first runs.

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

`ai-teammate.yml` has run once as a reusable workflow, for the dev leg. Not yet run: the `review`
and `rework` legs, the `agents` checkout used when a project has no submodule, and `sm.yml`. Run
`machine-sm.yml` as a dry run first. The rule engine was written for the Dart runtime of DMTools;
whether the Java fork jar runs every rule is untested.
