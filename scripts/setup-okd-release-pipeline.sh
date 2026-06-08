#!/usr/bin/env bash
set -euo pipefail

# OKD Release Pipeline Setup Script
# Run this script after 'oc login' to set up the release pipeline on a new cluster

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="okd-coreos"

echo "=========================================="
echo "OKD Release Pipeline Setup Script"
echo "=========================================="

# Check if logged in
if ! oc whoami &>/dev/null; then
    echo "ERROR: Not logged in to OpenShift. Run 'oc login' first."
    exit 1
fi

echo "Logged in as: $(oc whoami)"
echo "Cluster: $(oc whoami --show-server)"
echo ""

# Step 1: Get worker node name
echo "[1/8] Getting worker node name..."
WORKER_NODE=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$WORKER_NODE" ]]; then
    echo "ERROR: No worker nodes found"
    exit 1
fi
echo "Worker node: $WORKER_NODE"

# Step 2: Update PV and PipelineRun files with new node name
echo "[2/8] Updating node selectors in PV and PipelineRun files..."

# Update PVs (match any worker node pattern)
for pv_file in "$SCRIPT_DIR/okd-release-pipeline/base/core/persistentvolumes/pipeline-release-"*"-pv.yaml"; do
    if [[ -f "$pv_file" ]]; then
        # Match any existing worker node pattern and replace
        sed -i -E "s/- [a-zA-Z0-9_-]+-worker-[a-zA-Z0-9-]+/- $WORKER_NODE/" "$pv_file"
        # Also handle simpler patterns like host-xxx
        sed -i -E "s/- host-[0-9-]+/- $WORKER_NODE/" "$pv_file"
        echo "  Updated: $pv_file"
    fi
done

# Update PipelineRuns
for pr_file in "$SCRIPT_DIR/okd-release-pipeline/environments/moc/pipelineruns/"*.yaml; do
    if [[ -f "$pr_file" ]]; then
        sed -i "s/kubernetes.io\/hostname: .*/kubernetes.io\/hostname: $WORKER_NODE/" "$pr_file"
        echo "  Updated: $pr_file"
    fi
done

# Note: The cluster-command-task dynamically patches nodeSelector when using EventListener,
# so GitHub URLs in TriggerTemplate don't need manual updates

# Step 3: Create namespace
echo "[3/8] Creating namespace $NAMESPACE..."
oc create namespace "$NAMESPACE" 2>/dev/null || echo "  Namespace already exists"

# Step 4: Apply secrets
echo "[4/8] Applying secrets..."
if [[ -d "$SCRIPT_DIR/secrets" ]]; then
    oc apply -f "$SCRIPT_DIR/secrets/" -n "$NAMESPACE"
else
    echo "  WARNING: secrets/ directory not found. Please apply secrets manually."
fi

# Step 5: Install Tekton (if not already installed)
echo "[5/8] Installing Tekton Pipelines and Triggers..."
if ! oc get crd tasks.tekton.dev &>/dev/null; then
    echo "  Installing Tekton Pipelines..."
    oc apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
    
    echo "  Installing Tekton Triggers..."
    oc apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
    oc apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
    
    echo "  Granting privileged SCC to Tekton service accounts..."
    for sa in tekton-pipelines-controller tekton-pipelines-webhook tekton-events-controller \
              tekton-triggers-controller tekton-triggers-webhook tekton-triggers-core-interceptors; do
        oc adm policy add-scc-to-user privileged -z "$sa" -n tekton-pipelines 2>/dev/null || true
    done
    
    echo "  Waiting for Tekton CRDs to be available..."
    for i in {1..60}; do
        if oc get crd tasks.tekton.dev &>/dev/null && oc get crd eventlisteners.triggers.tekton.dev &>/dev/null; then
            echo "  Tekton CRDs are ready!"
            break
        fi
        echo "  Waiting... ($i/60)"
        sleep 5
    done
    
    # Delete replicasets to apply SCC changes
    oc delete rs --all -n tekton-pipelines 2>/dev/null || true
    
    echo "  Waiting for Tekton pods to be ready..."
    sleep 10
    oc wait --for=condition=available deployment --all -n tekton-pipelines --timeout=120s || true
else
    echo "  Tekton already installed"
fi

# Step 6: Apply kustomize base resources
echo "[6/8] Applying kustomize base resources..."
oc apply -k "$SCRIPT_DIR/okd-release-pipeline/environments/moc/"

# Step 7: Apply release-promotions
echo "[7/8] Applying release-promotions..."
cd "$SCRIPT_DIR/okd-release-pipeline/release-promotions"
bash apply.sh
cd "$SCRIPT_DIR"

# Step 8: Grant SCCs and ClusterRoleBindings
echo "[8/8] Granting SCCs and ClusterRoleBindings..."
oc adm policy add-scc-to-user privileged -z tekton-cluster-access -n "$NAMESPACE"

oc create clusterrolebinding tekton-cluster-access-eventlistener \
    --clusterrole=tekton-triggers-eventlistener-clusterroles \
    --serviceaccount="$NAMESPACE":tekton-cluster-access 2>/dev/null || \
    echo "  ClusterRoleBinding already exists"

# Restart EventListener to apply SCC changes
echo "  Restarting EventListener..."
oc delete rs -l app.kubernetes.io/managed-by=EventListener -n "$NAMESPACE" 2>/dev/null || true

# Wait for EventListener to be ready
echo "  Waiting for EventListener to be ready..."
sleep 10
oc wait --for=condition=Ready eventlistener/cluster-command-listener -n "$NAMESPACE" --timeout=60s || true

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "EventListener status:"
oc get eventlistener -n "$NAMESPACE"
echo ""
echo "Pods in $NAMESPACE:"
oc get pods -n "$NAMESPACE"
echo ""
echo "To trigger a pipeline run manually:"
echo "  oc create -f okd-release-pipeline/environments/moc/pipelineruns/okd-release-stable-pipelinerun.yaml -n $NAMESPACE"
echo ""
echo "To trigger via EventListener:"
echo "  oc run manual-promotion-\$(date +%Y%m%d-%H%M%S) --image=curlimages/curl --restart=Never \\"
echo "    -- curl -X POST http://el-cluster-command-listener.$NAMESPACE.svc.cluster.local:8080 \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"message\":\"manual\", \"next\":\"true\", \"stable\":\"true\"}'"
