## Node selection example

This example shows how to assign a pod to a specific node or to one of a set of nodes using node labels and the nodeSelector field in a pod specification. Generally this is unnecessary, as the scheduler will take care of things for you, but you may want to do so in certain circumstances like to ensure that your pod ends up on a machine with an SSD attached to it.

### Step Zero: Prerequisites

This example assumes that you have a basic understanding of kubernetes pods and that you have [turned up a Kubernetes cluster](https://github.com/GoogleCloudPlatform/kubernetes#documentation).

### Step One: Attach label to the node

Run `kubectl get nodes` to get the names of your cluster's nodes. Pick out the one that you want to add a label to.

Then, to add a label to the node you've chosen, run `kubectl label nodes <node-name> <label-key>=<label-value>`. For example, if my node name is 'kubernetes-foo-node-1.c.a-robinson.internal' and my desired label is 'disktype=ssd', then I can run `kubectl label nodes kubernetes-foo-node-1.c.a-robinson.internal disktype=ssd`.

If this fails with an "invalid command" error, you're likely using an older version of kubectl that doesn't have the `label` command. In that case, see the [previous version](https://github.com/GoogleCloudPlatform/kubernetes/blob/a053dbc313572ed60d89dae9821ecab8bfd676dc/examples/node-selection/README.md) of this guide for instructions on how to manually set labels on a node.

Also, note that label keys must be in the form of DNS labels (as described in the [identifiers doc](/docs/design/identifiers.md)), meaning that they are not allowed to contain any upper-case letters.

You can verify that it worked by re-running `kubectl get nodes` and checking that the node now has a label.

### Step Two: Add a nodeSelector field to your pod configuration

Take whatever pod config file you want to run, and add a nodeSelector section to it, like this. For example, if this is my pod config:

<pre>
apiVersion: v1beta1
desiredState:
  manifest:
    containers:
      - image: nginx
        name: nginx
    id: nginx
    version: v1beta1
id: nginx
kind: Pod
labels:
  env: test
</pre>

Then add a nodeSelector like so:

<pre>
apiVersion: v1beta1
desiredState:
  manifest:
    containers:
      - image: nginx
        name: nginx
    id: nginx
    version: v1beta1
id: nginx
kind: Pod
labels:
  env: test
<b>nodeSelector:
  disktype: ssd</b>
</pre>

When you then run `kubectl create -f pod.yaml`, the pod will get scheduled on the node that you attached the label to! You can verify that it worked by running `kubectl get pods` and looking at the "host" that the pod was assigned to.

### Conclusion

While this example only covered one node, you can attach labels to as many nodes as you want. Then when you schedule a pod with a nodeSelector, it can be scheduled on any of the nodes that satisfy that nodeSelector. Be careful that it will match at least one node, however, because if it doesn't the pod won't be scheduled at all.
