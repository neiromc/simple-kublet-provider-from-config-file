## Run

```bash
DOCKER_CONFIG_FILE=examples/config.json ./simple-kublet-provider-from-config-file.sh < examples/kubelet-request.json
```

Default path to DOCKER_CONFIG_FILE:
```
/var/lib/kubelet/config.json
```

## Use in k8s

1. On host copy shell script to custom bin dir:
```bash
cp ./simple-kublet-provider-from-config-file.sh /usr/local/bin/simple-kublet-provider-from-config-file

chmod ug+x /usr/local/bin/simplekublet-provider-from-config-file
```

2. Create kubelet provider config file /etc/kubernetes/credential-provider-config.yaml
```yaml
apiVersion: kubelet.config.k8s.io/v1
kind: CredentialProviderConfig
providers:
  - name: simple-docker-config-provider
    matchImages:
      - "ghcr.io"
      - "*"  ### or add your custom registries. Official documentation: https://kubernetes.io/docs/reference/config-api/kubelet-config.v1/
    apiVersion: credentialprovider.kubelet.k8s.io/v1
    provider:
      command:
        - /usr/local/bin/simple-kublet-provider-from-config-file
```

3. Restart kubelet with params (you can change it in systemd unit file or add to kubelet config in /etc)
```bash
kubelet \
  --image-credential-provider-config=/etc/kubernetes/credential-provider-config.yaml \
  --image-credential-provider-bin-dir=/usr/local/bin
```
