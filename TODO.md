Centralized K3s Monitoring on R430 (GUI) with Mini PC as Control Plane
Yes! You can run the K3s control plane on the mini PC (headless Debian) while visualizing all cluster activity from the R430 (RHEL + GUI). Here’s how to set it up:

Step 1: Configure the K3s Cluster
1. Mini PC (Control Plane Node)
Install K3s (Server) on the mini PC:

bash
curl -sfL https://get.k3s.io | sh -s - server --cluster-init
Key flags:
--cluster-init: Enables HA if you add more control nodes later.
--disable traefik: Skip if you want Traefik (else install Ingress later).

Get the kubeconfig for remote access:

bash
sudo cat /etc/rancher/k3s/k3s.yaml
Copy this to your R430 at ~/.kube/config.

2. R430 & T3500 (Worker Nodes)
Join the cluster (run on each worker):

bash
curl -sfL https://get.k3s.io | K3S_URL=https://<MINI_PC_IP>:6443 K3S_TOKEN=<NODE_TOKEN> sh -
Get NODE_TOKEN from the mini PC:

bash
sudo cat /var/lib/rancher/k3s/server/node-token
Limit Disk Usage (Optional):
If you want K3s to use only specific partitions:

bash
# Mount the desired partition to /var/lib/rancher/k3s/storage
sudo mkdir -p /var/lib/rancher/k3s/storage
sudo mount /dev/sdX1 /var/lib/rancher/k3s/storage
Step 2: Visualize the Cluster from R430 (GUI)
Option A: Kubernetes Dashboard (Web UI)
Install the Dashboard:

bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
Access it via kubectl proxy:

bash
kubectl proxy
Open in Firefox/Chrome on R430:
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

Option B: Lens IDE (Recommended)
Install Lens on R430 (RHEL GUI):

Download the RPM package.

Install:

bash
sudo dnf install ./Lens-*.rpm
Connect to the Cluster:

Open Lens → File > Add Cluster → Paste the kubeconfig from the mini PC.

Option C: Prometheus + Grafana + Loki (Advanced)
Install Monitoring Stack (Helm):

bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack
Access Grafana:

bash
kubectl port-forward svc/monitoring-grafana 3000:80
Open http://localhost:3000 on R430 (default creds: admin/prom-operator).

Step 3: Expose Services for Easy Access
1. NodePorts for Web UIs
Example (Grafana NodePort):

yaml
kubectl expose svc monitoring-grafana --type=NodePort --port=80 --name=grafana-external
Access via http://<R430_IP>:<NodePort>.

2. Ingress (If Using Traefik/Nginx)
Install Traefik (if not pre-installed by K3s):

bash
helm install traefik traefik/traefik
Create an IngressRoute for Grafana:

yaml
kubectl apply -f - <<EOF
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: grafana
  namespace: default
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`grafana.home`)
      kind: Rule
      services:
        - name: monitoring-grafana
          port: 80
EOF
Add grafana.home to your R430’s /etc/hosts pointing to the mini PC IP.

Step 4: Key Benefits
Feature	Mini PC (Control Plane)	R430 (GUI + Worker)
Resource Usage	Low (Headless Debian)	High (64GB RAM)
Visualization	❌ No GUI	✅ Lens/Grafana
Fault Detection	Logs (journalctl)	Web Dashboards
Storage Control	N/A	Partition Limits
Final Architecture
text
Mini PC (Control Plane)
├── K3s Server
├── Cluster DNS
└── API Server
    ↓ (kubeconfig)
R430 (Worker + GUI)
├── K3s Agent
├── Lens IDE / Grafana
└── NodePorts (3000, 9090, etc.)
Why This Works
Control plane stays lightweight (mini PC).

All monitoring lives on the R430 (GUI + resources).

No extra hardware needed (uses existing nodes).

Need help with Helm charts or Ingress? Ask away! 🛠️

