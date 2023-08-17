# OKD Release Pipeline

## Prerequisites
1. create or update the following secrets:
* `okd-githubapp-auth`
  * contains key `private.key`, which is private key of GitHub App (okd-tekton-token) with permissions to create releases in `okd-scos` project
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

## Annex - running a task individually
```bash
tkn task start create-github-release \
  --param github-org-repo="okd-project/okd-scos" \
  --param github-token-secret-key="gh-okd-token" \
  --param github-token-secret-name="gh-token" \
  --param gpg-key-id="maintainers@okd.io" \
  --param gpg-signing-key="okd-release-gpg-signing-key" \
  --param mirrored-release-pullspec="quay.io/okd/scos-release:4.12.0-0.okd-scos-2022-12-02-083740" \
  --param release-name="4.12.0-0.okd-scos-2022-12-02-083740"

```
