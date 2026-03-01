# GitHub Actions Workflows (Optional)

These workflows are **disabled by default**. Use them if you want GitHub Actions to build artifacts. Otherwise, use **Harness CI** for the full Harness experience.

## Available Workflows

| Workflow | Purpose |
|----------|---------|
| `build-ami.yml.disabled` | Build AMI with Packer |
| `build-lambda-image.yml.disabled` | Build and push Lambda container image |
| `build-k8s-image.yml.disabled` | Build and push K8s container image |

## To Enable GitHub Actions

```bash
# Enable the workflow you need
mv .github/workflows/build-ami.yml.disabled .github/workflows/build-ami.yml

# Or enable all
for f in .github/workflows/*.disabled; do mv "$f" "${f%.disabled}"; done
```

## Required Secrets

Add these to your GitHub repo settings (Settings → Secrets → Actions):

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_ARN` | IAM role ARN for GitHub OIDC (e.g., `arn:aws:iam::123456789:role/github-actions-role`) |

## Using Harness CI Instead

If you prefer Harness CI:

1. Create a Harness CI pipeline
2. Use the build steps from these workflow files as reference
3. Push artifacts to ECR or build AMI
4. Trigger Harness CD pipeline

See `infra/harness/pipelines/` for CD pipeline templates.
