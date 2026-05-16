See: https://kubernetes.io/docs/concepts/services-networking/gateway/

This folder contains a minimal Gateway API example set:
- `gateway-class.yaml`
- `gateway.yaml`
- `backend.yaml`
- `http-route.yaml`

Notes:
- Gateway API requires CRDs and a compatible controller implementation.
- `GatewayClass.spec.controllerName` must match your installed controller.
- If no controller is installed, these resources may be created but no traffic will flow.
