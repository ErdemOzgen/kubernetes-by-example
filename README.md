# Learn Kubernetes by Example 

1. [Namespace](Namespace/)
2. [Pod](Pod/)
3. [ConfigMap](ConfigMap/)
4. [Secret](Secret/)
5. [ServiceAccount](ServiceAccount/)

6. [Deployment](Deployment/)
7. [DaemonSet](DaemonSet/)
8. [Job](Job/)
9. [CronJob](CronJob/)

10. [Service](Service/)
11. [Endpoints](Endpoints/)
12. [Ingress](Ingress/)
13. [NetworkPolicy](NetworkPolicy/)

14. [PersistentVolume](PersistentVolume/)
15. [PersistentVolumeClaim](PersistentVolumeClaim/)
16. [StorageClass](StorageClass/)
17. [StatefulSet](StatefulSet/)

18. [LimitRange](LimitRange/)
19. [ResourceQuotas](ResourceQuotas/)
20. [PriorityClass](PriorityClass/)
21. [PodDisruptionBudget](PodDisruptionBudget/)

22. [Role](Role/)
23. [RoleBinding](RoleBinding/)
24. [ClusterRole](ClusterRole/)
25. [ClusterRoleBinding](ClusterRoleBinding/)

26. [broken-Pod](broken-Pod/)
27. [broken-Deployment](broken-Deployment/)
28. [broken-Secret](broken-Secret/)

29. [CustomResourceDefinition](CustomResourceDefinition/)
30. [Istio](Istio/)

31. [cloud-providers](cloud-providers/)
32. [plugins](plugins/)
33. [tests](tests/)

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