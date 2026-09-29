# Deployment Runbook — Virtualization Lab (Spring Boot)

This is the complete, literal step-by-step record of everything executed to build, containerize,
publish, and deploy this project — every command, every AWS Console click, and every value used
(instance IDs, IPs, tags). It exists as a detailed reference/runbook alongside the polished
top-level `README.md`.

---

## Part 1 — Build the web application

1. Maven project laid out at the repository root (not under `src/main`, which is a common mistake —
   `pom.xml` must sit next to `src/`, since Maven resolves `src/main/java` relative to the POM's
   own location).

2. `pom.xml` — Spring Boot 4.1.1 parent, `spring-boot-starter-web`, Java 21:

   ```xml
   <parent>
       <groupId>org.springframework.boot</groupId>
       <artifactId>spring-boot-starter-parent</artifactId>
       <version>4.1.1</version>
   </parent>
   <properties>
       <java.version>21</java.version>
   </properties>
   <dependencies>
       <dependency>
           <groupId>org.springframework.boot</groupId>
           <artifactId>spring-boot-starter-web</artifactId>
       </dependency>
   </dependencies>
   ```

3. `src/main/java/co/edu/escuelaing/HelloRestController.java` — `@RestController` exposing
   `GET /greeting?name=`, default `"World"`.

4. `src/main/java/co/edu/escuelaing/RestServiceApplication.java` — `@SpringBootApplication` entry
   point. Reads the port from `PORT`, default **`9000`**:

   ```java
   SpringApplication aplication = new SpringApplication(RestServiceApplication.class);
   aplication.setDefaultProperties(
       Map.of("server.port", System.getenv().getOrDefault("PORT", "9000")));
   aplication.run(args);
   ```

   > Earlier iteration used port `6000` as the default. It was changed to `9000` because Chromium
   > browsers hard-block port `6000` as an "unsafe port" (`ERR_UNSAFE_PORT`, historically reserved
   > for X11) — `curl` worked fine, but testing in a browser failed. `9000` has no such restriction.

5. Build and run:

   ```bash
   mvn clean package
   java -jar target/virtualization-lab-1.0.0.jar
   ```

   Verified: `http://localhost:9000/greeting?name=Pedro` → `Hello, Pedro`
   (evidence: `evidence/04-local-run-port9000-greeting.jpg`)

---

## Part 2 — Docker image and container isolation

1. `Dockerfile` at the repo root:

   ```dockerfile
   FROM amazoncorretto:21
   WORKDIR /app
   COPY target/*.jar app.jar
   ENV PORT=9000
   EXPOSE 9000
   ENTRYPOINT [ "java", "-jar", "app.jar" ]
   ```

2. Build the image (Docker Desktop must be running — on Windows it was launched with
   `Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"` and given a few seconds
   for the engine to come up before `docker ps` responded):

   ```bash
   docker build -t exael74/virtualizationlab:1.0 .
   ```

3. Run one container:

   ```bash
   docker run -d --name virtualization-lab-1 -e PORT=9000 -p 34000:9000 exael74/virtualizationlab:1.0
   ```

4. Demonstrate isolation — two more independent instances of the same image:

   ```bash
   docker run -d --name virtualization-lab-2 -p 34001:9000 exael74/virtualizationlab:1.0
   docker run -d --name virtualization-lab-3 -p 34002:9000 exael74/virtualizationlab:1.0
   ```

5. Verified independently:

   ```
   curl http://localhost:34000/greeting?name=Container   → Hello, Container
   curl http://localhost:34001/greeting?name=Container2  → Hello, Container2
   curl http://localhost:34002/greeting?name=Container3  → Hello, Container3
   ```

   `docker ps` confirmed three separate container IDs (`40632c8543b7`, `4e8386572423`,
   `e1e386fa9873`), each with its own port mapping, all from image `exael74/virtualizationlab:1.0`.
   Full transcript: `evidence/05-docker-ps-three-isolated-containers-port9000.txt`.

6. Cleanup before moving to Compose:

   ```bash
   docker rm -f virtualization-lab-1 virtualization-lab-2 virtualization-lab-3
   ```

---

## Part 3 — Multi-container environment with Docker Compose (web + MongoDB)

1. `compose.yaml`:

   ```yaml
   services:
     web:
       build:
         context: .
         dockerfile: Dockerfile
       container_name: virtualization-web
       environment:
         PORT: 9000
         SPRING_DATA_MONGODB_URI: mongodb://db:27017/workshop
       ports:
         - "8087:9000"
       depends_on:
         - db

     db:
       image: mongo:8
       container_name: virtualization-db
       volumes:
         - mongodb:/data/db
         - mongodb_config:/data/configdb
       ports:
         - "27017:27017"
       command: mongod

   volumes:
     mongodb:
     mongodb_config:
   ```

2. Start both services:

   ```bash
   docker compose up -d --build
   docker compose ps
   docker compose logs web --tail 15
   docker compose logs db --tail 10
   ```

3. Verify the web service: `curl http://localhost:8087/greeting?name=Compose` → `Hello, Compose`
   (evidence: `evidence/07-compose-greeting-port8087.jpg`)

4. Verify MongoDB connectivity end-to-end via `mongosh` inside the `db` container:

   ```bash
   docker compose exec db mongosh --quiet --eval '
     printjson(db.adminCommand({listDatabases:1}).databases.map(d=>d.name));
     const wdb = db.getSiblingDB("workshop");
     wdb.messages.insertOne({ message: "Hello from Docker Compose" });
     printjson(wdb.messages.find().toArray());
   '
   ```

   Result: `['admin', 'config', 'local']` then the inserted document with a real generated
   `ObjectId`, proving the `web` service's declared MongoDB URI (`mongodb://db:27017/workshop`)
   resolves correctly to the `db` service by its Compose service name, over the network Compose
   creates automatically. Full transcript: `evidence/06-docker-compose-web-and-mongodb-output.txt`.

5. Tear down (keeping the named volumes):

   ```bash
   docker compose down
   ```

---

## Part 4 — Publish to Docker Hub

1. Docker Desktop was already authenticated (its credential store handles the Docker Hub login
   transparently; no interactive `docker login` was required in this session).

2. Tag and push both versions:

   ```bash
   docker tag exael74/virtualizationlab:1.0 exael74/virtualizationlab:latest
   docker push exael74/virtualizationlab:1.0
   docker push exael74/virtualizationlab:latest
   ```

3. Verified publicly at https://hub.docker.com/r/exael74/virtualizationlab/tags — both `1.0` and
   `latest` tags listed, digest `sha256:6d3e908454e9...`, 231.87 MB compressed, `linux/amd64`.
   (evidence: `evidence/08-dockerhub-both-tags.jpg`)

---

## Part 5 — AWS EC2 deployment

### 5.1 Getting the operator's public IP (for the SSH security-group rule)

```bash
curl -s https://api.ipify.org
# → 181.63.25.112
```

### 5.2 Launching the instance (AWS Console — EC2 → Launch an instance)

> Note: the AWS Console's "Launch an instance" wizard repeatedly failed to respond to scrolling
> and keyboard navigation under browser automation in this session (confirmed across a page
> reload, a brand-new tab, and a resized new browser window — the renderer itself hung on
> `Page.captureScreenshot` calls). Rather than keep fighting an unstable page, the wizard was
> completed manually by the account owner while the assistant provided the exact field-by-field
> values below; deployment then continued via SSH, which the assistant executed directly.

Exact configuration used:

| Field | Value |
|---|---|
| Name | `virtualization-lab` |
| Application and OS Image (AMI) | Amazon Linux 2023 (default Quick Start selection), `ami-0b245cc5f82576748` |
| Instance type | `t2.micro` |
| Key pair | New key pair, name `virtualization-lab-key`, type RSA, format `.pem` — downloaded to `Downloads\virtualization-lab-key.pem` |
| Security group | New — `launch-wizard-1` |
| Inbound rule 1 | SSH, TCP 22, source **My IP** → resolved to `181.63.25.112/32` |
| Inbound rule 2 | Custom TCP, port **8080**, source `0.0.0.0/0` (public demo endpoint) |
| Storage | 8 GiB `gp3` (default) |

Result: instance `i-0f776796ea6e335f1`, state `running`, public IPv4 **`54.175.21.62`**.

### 5.3 Installing Docker over SSH

```bash
chmod 400 "Downloads/virtualization-lab-key.pem"

ssh -i "Downloads/virtualization-lab-key.pem" -o StrictHostKeyChecking=no \
    ec2-user@54.175.21.62 "echo CONNECTED && uname -a"
# → Linux ip-172-31-31-130.ec2.internal 6.18.51-... x86_64 GNU/Linux

ssh -i "Downloads/virtualization-lab-key.pem" ec2-user@54.175.21.62 "
  sudo yum update -y -q &&
  sudo yum install -y docker -q &&
  sudo service docker start &&
  sudo usermod -a -G docker ec2-user &&
  sudo docker --version
"
# → Docker version 25.0.14, build 0bab007
```

### 5.4 Pulling and running the image

```bash
ssh -i "Downloads/virtualization-lab-key.pem" ec2-user@54.175.21.62 "
  sudo docker pull exael74/virtualizationlab:1.0 &&
  sudo docker run -d \
    --name virtualization-lab \
    --restart unless-stopped \
    -e PORT=9000 \
    -p 8080:9000 \
    exael74/virtualizationlab:1.0 &&
  sudo docker ps &&
  sudo docker logs virtualization-lab --tail 15
"
```

### 5.5 External verification (from the operator's machine, not via SSH — proves the security group truly allows internet traffic)

```bash
curl -s -m 10 "http://54.175.21.62:8080/greeting?name=AWS"
# → Hello, AWS
```

Screenshot: `evidence/09-ec2-public-deployment-greeting.jpg`.
Full transcript: `evidence/10-ec2-docker-install-and-run-output.txt`.

---

## Part 6 — AWS Pricing Calculator (cost analysis)

1. Navigated to `https://calculator.aws/#/addService`, declined non-essential cookies, changed
   region from the default "US East (Ohio)" to **US East (N. Virginia)** (`us-east-1`, matching
   the deployed instance).

2. Searched for and configured the **Amazon EC2** service:
   - Description: "Small workload - virtualization-lab (10,000 req/month)"
   - Tenancy: Shared Instances · OS: Linux · Workload: Constant usage · Number of instances: `1`
   - Instance type: searched and selected **`t2.micro`** explicitly (1 vCPU, 1 GiB memory,
     EBS only) — confirmed On-Demand rate **$0.0116/hour**.
   - Payment option: **On-Demand**, Expected utilization **100%** (constant usage type,
     "Utilization percent per month").
   - Expanded **Amazon Elastic Block Store (EBS)**: General Purpose SSD (`gp3`), storage amount
     set to **8 GB** (matching the actual EC2 root volume).
   - Expanded **Data transfer**: confirmed the "Internet" destination rate is **$0.05–$0.09/GB**,
     with AWS's always-free 100 GB/month internet egress allowance noted directly in the tool.

3. Clicked **Save and view summary** → resulting estimate:

   ```
   Upfront cost:  0.00 USD
   Monthly cost:  4.87 USD
   Total 12 months cost: 58.44 USD
   ```

   Screenshot: `evidence/11-aws-pricing-calculator-estimate.jpg`.

4. This single calculator-verified data point ($4.87/month for 1× `t2.micro` + 8 GiB `gp3`,
   running continuously) was then used as the anchor to derive the Medium and Large workload
   scenarios analytically (same per-unit rates, scaled by instance count and — where relevant —
   estimated data transfer), documented with all assumptions in the main `README.md`, Section 11.

---

## Part 7 — Decommissioning

The EC2 instance was **stopped/terminated** after all evidence above was captured, per the
workshop's explicit closing instruction ("Terminate the EC2 instance when the workshop ends to
avoid unnecessary charges") and at the repository owner's request. After this point, the public
URL `http://54.175.21.62:8080/greeting?name=AWS` referenced elsewhere in this repository is no
longer reachable — it is preserved in the README and in `evidence/` purely as proof that the
deployment worked while it was live.
