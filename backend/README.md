run:

```Bash

podman run -d \
  -p 8080:3000 \
  -v .:/app:Z \
  --name backend-dev \
  my-node-backend \
  npm run dev
```