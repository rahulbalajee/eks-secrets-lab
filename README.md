# eks-secrets-lab

Companion code for **[From Terraform to Pod: How Config, Secrets and AWS Credentials Really Reach Your App on EKS](https://rahulbalajee.com/blog/config-secrets-and-aws-credentials-on-eks)**.

A small Go "transcoder" gets its configuration from three places:

| Value | Lives in | Reaches the pod through |
| --- | --- | --- |
| `LOG_LEVEL`, `WORKERS`, `FFMPEG_PRESET` | ConfigMap, in Git | `envFrom` |
| Queue URL, output bucket (Terraform outputs) | SSM Parameter Store | External Secrets Operator → Secret |
| Database password | AWS Secrets Manager | External Secrets Operator → Secret |

AWS credentials come from **EKS Pod Identity**: no keys anywhere, and the app
just calls `config.LoadDefaultConfig`. An IRSA version of the same role is in
[`terraform/examples/irsa`](terraform/examples/irsa).

```
app/                Go service (logs where each setting came from, never the secret itself)
k8s/base/           ConfigMap, ServiceAccount, ClusterSecretStores, ExternalSecrets, Deployment
k8s/overlays/eks/   production: your image, Pod Identity, no credentials
k8s/overlays/lab/   local: fake credentials, 15 s refresh, locally built image
terraform/          SQS, S3, Parameter Store, Secrets Manager, IAM roles, Pod Identity
lab/                kind + moto (a fake AWS) so you can run all of it on a laptop
```

## Run it locally (no AWS account, no cost)

Needs Docker, [kind](https://kind.sigs.k8s.io/), kubectl, Helm, the AWS CLI and
openssl. Everything talks to [moto](https://github.com/getmoto/moto), an
in-memory fake of the AWS APIs; the lab scripts set fake credentials and a
local endpoint so nothing reaches real AWS.

```sh
./lab/up.sh                  # kind, moto, ESO, Reloader, seed data, the app
kubectl -n video get externalsecret
kubectl -n video logs deploy/transcoder

./lab/etcd.sh                # read the Secret straight out of etcd
./lab/rotate.sh              # rotate the password and watch it propagate
./lab/encrypted.sh           # same, on a cluster with encryption at rest

./lab/down.sh
```

To see the difference between environment variables and mounted files,
remove the Reloader annotation before rotating:

```sh
kubectl -n video annotate deploy/transcoder reloader.stakater.com/auto-
./lab/rotate.sh
kubectl -n video logs deploy/transcoder -f   # "changed on disk; this process still uses the old one"
```

## Run it on EKS

You need an EKS cluster on Kubernetes 1.28 or later with Linux EC2 nodes (Pod
Identity does not work on Fargate; use the IRSA example there), and a node role
that allows `eks-auth:AssumeRoleForPodIdentity` (`AmazonEKSWorkerNodePolicy`
does).

```sh
# 1. AWS side: queue, bucket, parameters, secret, roles, Pod Identity
cd terraform
terraform init
terraform apply -var cluster_name=my-cluster

# 2. Cluster add-ons. Install ESO after step 1: Pod Identity credentials are
#    injected when a pod is created, so a controller that started before its
#    association needs a restart.
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --version 2.14.0
helm install reloader stakater/reloader -n reloader --create-namespace --version 2.2.18

# 3. The app: push the image, set it in k8s/overlays/eks, apply
kubectl apply -k k8s/overlays/eks
kubectl -n video logs deploy/transcoder   # aws_credentials=CredentialsEndpointProvider
```

The ClusterSecretStores use `eu-west-1`; change `region` in
`k8s/base/clustersecretstores.yaml` and `-var region=...` together.

Costs: standard Parameter Store parameters are free at standard throughput.
Secrets Manager charges per secret per month and per 10,000 API calls, and every
ESO refresh is an API call, so keep `refreshInterval` at an hour unless you need
faster.

## Checks

```sh
make check   # go vet + test, terraform fmt + validate, kustomize + kubeconform
```

## License

MIT
