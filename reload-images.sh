# 1. Remove the old image cache
podman rmi localhost/travel-log-backend:latest

# 2. Restart the pod (this will now trigger the .build file automatically)
systemctl restart travel-log-pod.service