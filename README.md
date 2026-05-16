# Learn Kubernetes by Example 

<p align="center">
    <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/3/39/Kubernetes_logo_without_workmark.svg/250px-Kubernetes_logo_without_workmark.svg.png?utm_source=commons.wikimedia.org&utm_campaign=index&utm_content=thumbnail" alt="Kubernetes logo" />
</p>

1. [Namespace](Namespace/notes.md)
2. [Pod](Pod/notes.md)
3. [ConfigMap](ConfigMap/notes.md)
4. [Secret](Secret/notes.md)
5. [ServiceAccount](ServiceAccount/notes.md)

6. [Deployment](Deployment/notes.md)
7. [DaemonSet](DaemonSet/notes.md)
8. [Job](Job/notes.md)
9. [CronJob](CronJob/notes.md)

10. [Service](Service/notes.md)
11. [Endpoints](Endpoints/notes.md)
12. [Ingress](Ingress/notes.md)
13. [GatewayAPI](GatewayAPI/notes.md)
14. [NetworkPolicy](NetworkPolicy/notes.md)

15. [PersistentVolume](PersistentVolume/notes.md)
16. [PersistentVolumeClaim](PersistentVolumeClaim/notes.md)
17. [StorageClass](StorageClass/notes.md)
18. [StatefulSet](StatefulSet/notes.md)

19. [LimitRange](LimitRange/notes.md)
20. [ResourceQuotas](ResourceQuotas/notes.md)
21. [PriorityClass](PriorityClass/notes.md)
22. [PodDisruptionBudget](PodDisruptionBudget/notes.md)

23. [Role](Role/)
24. [RoleBinding](RoleBinding/)
25. [ClusterRole](ClusterRole/)
26. [ClusterRoleBinding](ClusterRoleBinding/)

27. [broken-Pod](broken-Pod/)
28. [broken-Deployment](broken-Deployment/)
29. [broken-Secret](broken-Secret/)

30. [CustomResourceDefinition](CustomResourceDefinition/)
31. [Istio](Istio/)

32. [cloud-providers](cloud-providers/)
33. [plugins](plugins/)
34. [tests](tests/)

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