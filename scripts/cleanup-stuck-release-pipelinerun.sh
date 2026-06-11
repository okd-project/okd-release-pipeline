#!/usr/bin/env bash
# Tear down a stuck okd-release-* PipelineRun and Tekton affinity assistants when
# workspace PVCs were pending (unbound) or node/PV topology drifted.
set -euo pipefail
NS="${NS:-okd-coreos}"

usage() {
  echo "Usage: NS=okd-coreos $0 [PIPELINERUN_NAME]" >&2
  echo "  With no argument, deletes PipelineRuns labeled tekton.dev/pipeline=okd-release-pipeline." >&2
  exit 1
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

pr_delete_args=()
if [[ $# -ge 1 ]]; then
  pr_delete_args=("$1")
else
  pr_delete_args=()
  while IFS= read -r line; do
    [[ -n "${line}" ]] && pr_delete_args+=("$line")
  done < <(oc get pipelineruns.tekton.dev -n "${NS}" -l tekton.dev/pipeline=okd-release-pipeline -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
fi

for pr in "${pr_delete_args[@]}"; do
  [[ -z "${pr}" ]] && continue
  echo "Deleting PipelineRun ${pr}"
  oc delete pipelineruns.tekton.dev "${pr}" -n "${NS}" --ignore-not-found --wait=false || true
done

echo "Removing affinity-assistant StatefulSets (owned by PipelineRuns)"
while read -r sts; do
  [[ -z "${sts}" ]] && continue
  echo "Deleting StatefulSet ${sts}"
  oc delete statefulset "${sts}" -n "${NS}" --ignore-not-found --wait=false || true
done < <(oc get statefulset -n "${NS}" -l app.kubernetes.io/component=affinity-assistant -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

echo "Done. Reapply PV/PVC with: oc apply -k okd-release-pipeline/environments/moc/"
echo "Confirm PVC is Bound: oc get pvc -n ${NS}"
