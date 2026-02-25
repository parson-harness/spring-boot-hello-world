# Spring Boot Hello World

A sample Java application built with Spring Boot, with AWS ASG infrastructure and Harness Blue-Green deployment support.

---

## ⚡️ What you get

- Spring Boot 2.7.x (Java 11) web app
- Clean landing page at `/` (static `index.html`)
- JSON API at `/api` and health at `/health`
- Swagger UI at `/swagger-ui.html`
- Build & commit metadata at `/actuator/info`
- **AWS Infrastructure** (Terraform): VPC, ALB, ASG with Blue-Green support
- **Harness CD**: ASG Blue-Green deployment with traffic shifting
- Kubernetes manifests (Deployment + Service) ready for EKS
- Docker image that runs on Linux/amd64

---

## 🚀 Quick Start (AWS ASG Deployment)

For a complete AWS ASG deployment with Harness Blue-Green support:

```bash
# Run the setup script
./setup.sh
```

This will:
1. Build the application JAR
2. Deploy Terraform state backend (S3 + DynamoDB)
3. Deploy AWS infrastructure (VPC, ALB, ASG, S3)
4. Upload the JAR to S3
5. Output the ALB DNS and Harness configuration values

See [infra/README.md](infra/README.md) for detailed infrastructure documentation.

---

## 🧰 Prereqs

- JDK 11
- Maven 3.8+
- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- Docker (with `buildx`) - for Kubernetes deployment
- kubectl connected to a cluster (EKS or compatible) - for Kubernetes deployment

---

## 🚀 Build & Run Locally

```bash
# build jar
mvn clean package -DskipTests

# run app
java -jar target/spring-boot-hello-world-1.0-SNAPSHOT.jar

# open in browser
open http://localhost:8080/
```

Endpoints:
- `GET /` → landing page
- `GET /api` → sample JSON
- `GET /health` → health JSON
- `GET /swagger-ui.html` → API docs
- `GET /actuator/info` → build & commit metadata

---

## ☁️ AWS ASG Deployment

### Manual Deployment

```bash
# 1. Build the application
mvn clean package -DskipTests

# 2. Deploy Terraform state backend
cd infra/terraform-bootstrap
terraform init && terraform apply

# 3. Deploy main infrastructure
cd ../terraform
terraform init && terraform apply

# 4. Upload JAR to S3
aws s3 cp ../../target/spring-boot-hello-world-1.0-SNAPSHOT.jar s3://$(terraform output -raw s3_bucket_name)/

# 5. Access the application
echo "App URL: http://$(terraform output -raw alb_dns_name)"
```

### Harness Blue-Green Deployment

The infrastructure supports Harness ASG Blue-Green deployment with traffic shifting:
- Two target groups (prod + stage) for weighted traffic distribution
- Listener rule supporting incremental traffic shifts
- Sample pipeline with 10% → 50% → 100% traffic progression

See [infra/README.md](infra/README.md) for Harness setup instructions.

---

## 🐳 Build & Push Docker Image

The runtime image expects the fat jar to be present (built with the command above). The Dockerfile copies the jar and runs `java -jar`.

```bash
# build & push for EKS (linux/amd64)
docker buildx build   --platform linux/amd64   -t parsontodd/spring-boot-hello-world:latest   --push .
```

> Tip: If you're using a private registry, make sure your cluster has the right imagePullSecret.

---

## ☸️ Deploy to Kubernetes (EKS)

```bash
# namespace (templated)
kubectl get ns dev >/dev/null 2>&1 || kubectl create ns dev

# apply manifests
kubectl apply -f kubernetes/service.yml
kubectl apply -f kubernetes/deployment.yml

# watch rollout
kubectl rollout status deploy/spring-boot-hello-world -n dev

# get external endpoint
kubectl get svc spring-boot-hello-world-svc -n dev
```

When the `EXTERNAL-IP` is ready, open:
```
http://<EXTERNAL-IP>/
```

If you’re in a cluster without external LoadBalancers, port-forward instead:
```bash
kubectl port-forward svc/spring-boot-hello-world-svc 8080:80 -n dev
# then visit http://localhost:8080/
```

---

## 🔁 Fast Dev Loop

This repo ships with `:latest` and `imagePullPolicy: Always`, so you don’t need to edit YAML on each build. After pushing a new image, just restart the deployment:

```bash
docker buildx build --platform linux/amd64 -t parsontodd/spring-boot-hello-world:latest --push .

kubectl rollout restart deploy/spring-boot-hello-world -n dev
kubectl rollout status deploy/spring-boot-hello-world -n dev
```

---

## ⚙️ Configuration

`src/main/resources/application.properties`:
```properties
server.port=8080
management.endpoints.web.exposure.include=health,info
management.info.git.mode=full
info.app.name=springboothelloworld
info.app.description=A sample Java application built with Spring Boot
```

Env vars used by the container (set in the Deployment):
- `JAVA_OPTS` → JVM container tuning (defaults to `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`)
- `POD_NAME`, `POD_NAMESPACE` → auto-injected via Downward API (used in the sample response)

---

## 🧪 Tests

```bash
mvn test
```

`AppTest` includes:
- Spring context load smoke test
- `/api` JSON contract
- `/health` contract

---

## 📦 Project Layout

```
spring-boot-hello-world/
├─ src/                              # Application source code
│  ├─ main/
│  │  ├─ java/com/harness/springboothelloworld/
│  │  │  ├─ App.java
│  │  │  └─ HelloController.java
│  │  └─ resources/
│  │     └─ static/
│  │        └─ index.html
│  └─ test/
│     └─ java/com/harness/springboothelloworld/AppTest.java
├─ infra/                            # Infrastructure as Code
│  ├─ terraform-bootstrap/           # Terraform state backend (S3 + DynamoDB)
│  ├─ terraform/                     # Main AWS infrastructure (VPC, ALB, ASG)
│  ├─ harness/
│  │  ├─ asg/                        # Harness ASG Blue-Green configs
│  │  └─ service/                    # Harness Kubernetes service configs
│  └─ kubernetes/                    # Kubernetes manifests
├─ setup.sh                          # One-command deployment script
├─ Dockerfile
└─ pom.xml
```

---

## 🧭 Troubleshooting

- **Image pulls but pod crashes** → check `kubectl logs` and verify the jar path is `/app/app.jar` inside the image.
- **`exec format error`** on startup → your image arch doesn’t match node arch. Build with `--platform linux/amd64` for EKS x86 nodes.
- **`/` shows Whitelabel error** → ensure `src/main/resources/static/index.html` exists in the jar (`jar tf target/*.jar | grep BOOT-INF/classes/static/index.html`).
- **Changes don’t show up** → you pushed `:latest` but Pods reused the cached image. Use `imagePullPolicy: Always` (already set) and `kubectl rollout restart`.

---

## 📝 License

© todd.parson@harness.io. For demo/PoV purposes.
