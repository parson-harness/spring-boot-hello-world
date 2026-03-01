# Harness Pipeline Templates

Ready-to-import pipeline YAML files for each deployment model.

## How to Import

1. Go to **Harness → Pipelines → Create Pipeline**
2. Click **YAML** tab (top right)
3. Copy/paste the pipeline YAML
4. Replace `<+input>` placeholders with your values
5. Save and run

## Available Pipelines

| File | Deployment Type | Strategy |
|------|-----------------|----------|
| `asg-blue-green.yaml` | AWS ASG | Blue-Green with traffic shifting |
| `lambda-canary.yaml` | AWS Lambda | Canary (10% → 50% → 100%) |
| `k8s-canary.yaml` | Kubernetes | Canary with rolling deployment |

## Required Inputs

### ASG Blue-Green
| Input | Description |
|-------|-------------|
| `serviceRef` | Your ASG service identifier |
| `environmentRef` | Target environment (e.g., `dev`) |
| `infrastructureDefinitions` | Your ASG infrastructure |
| `loadBalancer` | ALB name |
| `prodListener` | Production listener ARN |
| `prodListenerRuleArn` | Production listener rule ARN |
| `stageListener` | Stage listener ARN |
| `stageListenerRuleArn` | Stage listener rule ARN |
| `version` | AMI version to deploy |

### Lambda Canary
| Input | Description |
|-------|-------------|
| `serviceRef` | Your Lambda service identifier |
| `environmentRef` | Target environment |
| `infrastructureDefinitions` | Your Lambda infrastructure |
| `tag` | ECR image tag to deploy |

### K8s Canary
| Input | Description |
|-------|-------------|
| `serviceRef` | Your K8s service identifier |
| `environmentRef` | Target environment |
| `infrastructureDefinitions` | Your K8s infrastructure |
| `tag` | ECR image tag to deploy |

## Pipeline Flow

### ASG Blue-Green
```
Deploy New ASG → Verify → Approval → Swap Traffic → Done
                                ↓ (reject)
                            Rollback
```

### Lambda Canary
```
Deploy → 10% Traffic → Verify → 50% Traffic → Approval → 100% Traffic → Done
                                                    ↓ (reject)
                                                Rollback
```

### K8s Canary
```
Deploy Canary Pod → Verify → Approval → Delete Canary → Rolling Deploy → Done
                                   ↓ (reject)
                               Rollback
```

## Customization

- **Add more canary steps**: Duplicate traffic shift steps with different percentages
- **Add verification**: Replace ShellScript steps with Harness CV (Continuous Verification)
- **Add notifications**: Add Slack/Email steps after approval or completion
- **Multi-environment**: Add additional stages for staging/prod
