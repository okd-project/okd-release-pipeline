# OKD Release Pipeline

## Prerequisites
1. create or update the following secrets:
* `okd-githubapp-auth`
  * contains key `private.key`, which is private key of GitHub App (okd-tekton-token) with permissions to create releases in `okd` project
* `okd-quay-pull-secret`, which is a dockerconfig with permissions to push to `quay.io/okd/scos-release` and `quay.io/okd/scos-content`
* `okd-release-gpg-signing-key`
  * contains key `private.key`, which is the GPG key used to sign the OKD release
* `okd-prow-sa-auth`
  * contains key `token`, which is a Service Account token for the Prow CI cluster, with permissions to tag release images. This token comes from the secret (sa-image-tagger-token-chsw6) stored in the app.ci cluster on the origin project.
* `okd-matrix-bot-auth`, which contains an access token for Matrix (under key `token`)

2. Apply:
```bash
oc apply -k environments/moc
```

## Run the pipeline
Launch the pipeline run with the Tekton client.

Example for stable release:
```bash
oc create -f environments/moc/pipelineruns/okd-release-stable-pipelinerun.yaml
```

Example for 4.next release: 
```bash
oc create -f environments/moc/pipelineruns/okd-release-next-pipelinerun.yaml

```

## Cincinnati graph-data PRs
When `enable-graph-update` is `"true"` (as in the `moc` PipelineRuns), the release pipeline finishes by starting an
`okd-graph-update-pipeline` run for the promoted release. Because acceptance can take hours, this runs as its own
PipelineRun, so the release pipeline still finishes and sends its notification on time:

1. `wait-for-release-acceptance` polls the release controller until the release is `Accepted` in its target stream
   (e.g. `5-scos-stable`). If the release is `Rejected`, or is not accepted within 12h, the run fails and no PR is opened.
2. `propose-graph-update` adds the release to every channel in cincinnati-graph-data whose `feeder.name` matches the
   stream (`*-scos-stable` → `stable`, `*-scos-next` → `candidate`) and whose `feeder.filter` matches the release. It
   makes one commit per channel and opens an `Enable <release> in <feeder> channels` PR. If no channel matches (e.g. the
   first release of a new minor), it fails rather than creating a channel.

The PR is opened by the same GitHub App that creates the OKD GitHub releases (okd-tekton-token, via
`get-github-access-token` and the `okd-githubapp-auth` secret). It pushes the `okd-release/<release>` branch straight to
cincinnati-graph-data, so the app's okd-project installation must include that repository, with **Contents** and
**Pull requests** read & write permissions.

`propose-graph-update` needs `yq` and `git` in `quay.io/okd/tekton-worker`; rebuild and push the image from
[tekton-worker-image](tekton-worker-image/) before enabling this.

```bash
# Follow the graph-data runs started by a release pipeline
oc get pipelineruns -n okd-coreos -l okd.io/parent-pipelinerun=<release-pipelinerun-name>

# Propose a graph update for an already accepted release, by hand (dry-run=true only prints the diff)
tkn pipeline start okd-graph-update-pipeline -n okd-coreos \
  --param release-name=5.0.0-okd-scos.2 \
  --param target-release-stream=5-scos-stable \
  --param dry-run=true
```

## Annex - running a task individually
```bash
tkn task start create-github-release \
  --param github-org-repo="okd-project/okd" \
  --param github-token-secret-key="gh-okd-token" \
  --param github-token-secret-name="gh-token" \
  --param gpg-key-id="maintainers@okd.io" \
  --param gpg-signing-key="okd-release-gpg-signing-key" \
  --param mirrored-release-pullspec="quay.io/okd/scos-release:4.12.0-0.okd-scos-2022-12-02-083740" \
  --param release-name="4.12.0-0.okd-scos-2022-12-02-083740"

```
