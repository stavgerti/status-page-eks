# Architecture

Two diagrams, generated from what's actually deployed (`infra/`, `platform/bootstrap`, `app/helm-chart`, `.github/workflows/`) — not a generic reference architecture. See `README.md` for the full narrative and the non-obvious decisions behind each piece.

## Diagram 1 — Runtime traffic flow

What happens, end to end, when a browser hits `devops.lvtvv.com`, plus the control-plane connections (dashed) that keep the app deployed, secured, and observed.

```mermaid
flowchart TD
    Client(["Browser"])
    R53["Route 53"]
    LE["Let's Encrypt"]

    subgraph Public["Public Subnet"]
        NLB["Network LB"]
    end

    subgraph Cluster["EKS Cluster"]
        ING["NGINX Ingress"]
        SVC["Web Service"]

        subgraph AppPods["Application Pods"]
            WEB["Web Pod"]
            WRK["Worker Pod"]
            SCH["Scheduler Pod"]
        end

        subgraph Platform["Platform Services"]
            ARGO["ArgoCD"]
            CM["cert-manager"]
            ESO["External Secrets"]
            EDNS["ExternalDNS"]
            PROM["Prometheus"]
            GRAF["Grafana"]
        end
    end

    subgraph Data["Data Layer"]
        RDS[("RDS Postgres")]
        REDIS[("ElastiCache")]
        SM["Secrets Manager"]
    end

    Client -->|DNS lookup| R53
    R53 -->|resolves to NLB| NLB
    NLB -->|private VPC routing| ING
    ING -->|TLS terminates here| SVC
    SVC -->|ClusterIP load-balances| WEB

    WEB -->|reads / writes| RDS
    WEB -->|cache + queue| REDIS
    WRK -->|consumes jobs| REDIS
    WRK -->|writes| RDS

    CM -.->|DNS-01 challenge| LE
    CM -.->|provides TLS cert| ING
    EDNS -.->|writes DNS record| R53
    ESO -.->|pulls secrets| SM
    ESO -.->|injects env vars| WEB
    ARGO -.->|syncs deploy| WEB
    ARGO -.->|syncs deploy| WRK
    ARGO -.->|syncs deploy| SCH
    PROM -.->|scrapes /metrics| WEB
    GRAF -.->|queries| PROM

    classDef aws fill:#FF9900,stroke:#8a5a00,color:#1a1a1a,font-weight:bold;
    classDef k8s fill:#326CE5,stroke:#1a3d82,color:#ffffff,font-weight:bold;
    classDef ext fill:#9aa0a6,stroke:#5f6368,color:#1a1a1a;

    class R53,NLB,RDS,REDIS,SM aws
    class ING,SVC,WEB,WRK,SCH,ARGO,CM,ESO,EDNS,PROM,GRAF k8s
    class Client,LE ext
```

**Legend:** orange = AWS-managed service (runs outside any pod, reached over the AWS API or network — Route 53, the NLB, RDS, ElastiCache, Secrets Manager). Blue = in-cluster Kubernetes component (runs as a pod, whether it's application code or a platform controller). Gray = external/third-party (the browser, Let's Encrypt). Solid arrows are the request path. Dashed arrows are control-plane traffic — deploys, secret sync, DNS/cert automation, metrics scraping — not user traffic. Note the NLB does TCP passthrough only; TLS terminates at the NGINX Ingress because ACM (and therefore an ALB) is denied in this AWS account. ElastiCache has no in-transit encryption, which is why its edge isn't labeled "TLS."

## Diagram 2 — CI/CD & GitOps pipeline

How a `git push` to `main` turns into running pods, and why nothing outside the cluster ever holds a credential that can reach it.

```mermaid
flowchart TD
    Dev(["git push main"])

    subgraph GitHub["GitHub"]
        CI["GitHub Actions"]
        SCAN["Gitleaks Scan"]
        REPO["Git Repository"]
    end

    subgraph AwsZone["AWS"]
        ECR[("ECR")]
    end

    subgraph Cluster["EKS Cluster"]
        ARGO["ArgoCD"]
        PODS["Web / Worker Pods"]
    end

    Dev -->|triggers build| CI
    Dev -.->|triggers scan| SCAN
    CI -->|assumes scoped CI role| ECR
    CI -->|builds & pushes image| ECR
    CI -->|bumps values.yaml, commits| REPO
    ARGO -->|pulls chart from Git| REPO
    ARGO -->|auto-sync, self-heal| PODS
    PODS -->|pulls image by tag| ECR

    classDef aws fill:#FF9900,stroke:#8a5a00,color:#1a1a1a,font-weight:bold;
    classDef k8s fill:#326CE5,stroke:#1a3d82,color:#ffffff,font-weight:bold;
    classDef ext fill:#9aa0a6,stroke:#5f6368,color:#1a1a1a;

    class ECR aws
    class ARGO,PODS k8s
    class Dev,CI,SCAN,REPO ext
```

**Legend:** gray = GitHub-side (developer, Actions runner, gitleaks, the repo itself). Orange = AWS-managed (ECR). Blue = in-cluster (ArgoCD, the pods it manages). Every arrow that crosses into the `EKS Cluster` box originates *inside* that box — `ArgoCD` reaches out to Git to check for changes, and the pods themselves pull their image from ECR. No arrow originates outside the cluster and terminates inside it: CI's own credentials (an assumed, ECR-scoped, 1-hour-session IAM role) never touch Kubernetes at all. The gitleaks scan runs on every push and PR but is a separate, non-blocking workflow — it doesn't gate the build-and-deploy path. There is no test step in the pipeline; the repo currently has zero automated tests (tracked in `README.md`'s "Known gaps").
