# OKD Release Promotions

Promotes OKD releases (stable and next) to production.

## Usage

### Manual Promotion

```bash
# Promote both releases
oc run okd-manual-promotion-$(date +%Y%m%d-%H%M%S) --image=curlimages/curl --restart=Never \
  -- curl -X POST http://el-cluster-command-listener.okd-coreos.svc.cluster.local:8080 \
  -H 'Content-Type: application/json' \
  -d '{"message":"manual", "next":"true", "stable":"true"}'

# Promote only next
oc run okd-manual-promotion-$(date +%Y%m%d-%H%M%S) --image=curlimages/curl --restart=Never \
  -- curl -X POST http://el-cluster-command-listener.okd-coreos.svc.cluster.local:8080 \
  -H 'Content-Type: application/json' \
  -d '{"message":"manual", "next":"true"}'

# Promote only stable  
oc run okd-manual-promotion-$(date +%Y%m%d-%H%M%S) --image=curlimages/curl --restart=Never \
  -- curl -X POST http://el-cluster-command-listener.okd-coreos.svc.cluster.local:8080 \
  -H 'Content-Type: application/json' \
  -d '{"message":"manual", "stable":"true"}'

# Promote from local yaml
oc run okd-manual-promotion-$(date +%Y%m%d-%H%M%S) --image=curlimages/curl --restart=Never \
  -- curl -X POST http://el-cluster-command-listener.okd-coreos.svc.cluster.local:8080 \
  -H 'Content-Type: application/json' \
  -d '{"message":"manual", "next":"true", "next-yaml": "../environments/moc/pipelineruns/okd-release-next-pipelinerun.yaml"}'

```


### Automatic
CronJob runs every Monday at 5:00 AM UTC, automatically promoting both releases with default YAML URLs.

## Monitoring

```bash
# List recent promotion pods
oc get pods -n okd-coreos | grep okd-manual-promotion

# View logs (example: okd-manual-promotion-20251226-143052)
oc logs okd-manual-promotion-20251226-143052 -n okd-coreos -f
```