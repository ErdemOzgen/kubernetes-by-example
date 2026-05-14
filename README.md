# Learn Kubernetes by Example 

1. Namespace
2. Pod
3. ConfigMap
4. Secret
5. ServiceAccount

6. Deployment
7. DaemonSet
8. Job
9. CronJob

10. Service
11. Endpoints
12. Ingress
13. NetworkPolicy

14. PersistentVolume
15. PersistentVolumeClaim
16. StorageClass
17. StatefulSet

18. LimitRange
19. ResourceQuotas
20. PriorityClass
21. PodDisruptionBudget

22. Role
23. RoleBinding
24. ClusterRole
25. ClusterRoleBinding

26. broken-Pod
27. broken-Deployment
28. broken-Secret

29. CustomResourceDefinition
30. Istio

31. cloud-providers
32. plugins
33. tests

## Setup Lab Environment

* You can use k3d to create a local Kubernetes cluster for testing and learning purposes. It is a lightweight wrapper around k3s, which is a minimal Kubernetes distribution. You can install k3d using the following command:

```bash
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
```

* Once you have k3d installed,there are bash scrips in bin folder k3dup.sh and k3ddown.sh to create and delete a local Kubernetes cluster. You can run the following command to create a cluster.


```bash
    ./bin/k3dup.sh
```
* This will create a local Kubernetes cluster named "k3s-default" with 1 server and 2 agents. You can verify that the cluster is up and running by using the following command:

```bash
    kubectl get nodes
```

* To delete the cluster, you can run the following command:

```bash
    ./bin/k3ddown.sh
```