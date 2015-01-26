/*
Copyright 2014 Google Inc. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Reads the pod configuration from etcd using the Kubernetes etcd schema.
package config

import (
	"errors"
	"os"
	"path"
	"time"

	"github.com/GoogleCloudPlatform/kubernetes/pkg/api"
        "github.com/GoogleCloudPlatform/kubernetes/pkg/api/resource"
	"github.com/GoogleCloudPlatform/kubernetes/pkg/api/latest"
	"github.com/GoogleCloudPlatform/kubernetes/pkg/kubelet"
	"github.com/GoogleCloudPlatform/kubernetes/pkg/tools"
	"github.com/GoogleCloudPlatform/kubernetes/pkg/util"
	"github.com/GoogleCloudPlatform/kubernetes/pkg/watch"
	"github.com/golang/glog"

	flag "github.com/spf13/pflag"
)

var (
   nodeMilliCPU = flag.Int64("node_milli_cpu", 2000, "The amount of MilliCPU provisioned on each node")
   nodeMemory   = resource.QuantityFlag("node_memory", "4Gi", "The amount of memory (in bytes) provisioned on each node")
)


func EtcdKeyForHost(hostname string) string {
	return path.Join("/", "registry", "nodes", hostname, "boundpods")
}


func EtcdCheckinKey() string {
	hostname,_ := os.Hostname()
	return path.Join("/", "registry", "minions", hostname)
}

type sourceEtcd struct {
	key     string
	helper  tools.EtcdHelper
	updates chan<- interface{}
}

// NewSourceEtcd creates a config source that watches and pulls from a key in etcd
func NewSourceEtcd(key string, client tools.EtcdClient, updates chan<- interface{}) {
	helper := tools.EtcdHelper{
		client,
		latest.Codec,
		tools.RuntimeVersionAdapter{latest.ResourceVersioner},
	}
	source := &sourceEtcd{
		key:     key,
		helper:  helper,
		updates: updates,
	}
	glog.V(1).Infof("Watching etcd for %s", key)
	go util.Forever(source.run, time.Second)
}

func (s *sourceEtcd) run() {
	boundPods := api.BoundPods{}

	// TODO: Make checkin times be a variable
	periodicCheckin := time.NewTicker(time.Second * 2)
	defer periodicCheckin.Stop()
	go func() {

		// TODO get real stats from cadvisor.
		
		hostname,_ := os.Hostname()
		nodeResources := &api.NodeResources{
					Capacity: api.ResourceList{
						api.ResourceCPU:    *resource.NewMilliQuantity(*nodeMilliCPU, resource.DecimalSI),
						api.ResourceMemory: *nodeMemory,
					},
				}


		node := &api.Node{
			          ObjectMeta: api.ObjectMeta{Name: hostname},
			          Spec: api.NodeSpec{
					   Capacity: nodeResources.Capacity,
				  },
			}

		testkey := EtcdCheckinKey()
		
		for t := range periodicCheckin.C {
			err := s.helper.CreateObj(testkey, node, 3)
			if err != nil {
				glog.Errorf("etcd failed to iretrieve the value for the key %q. Error: %v", testkey, err)
			} else {
			    glog.Infof("periodicCheckin checkin",t)
			}

		}
	}()

	err := s.helper.ExtractObj(s.key, &boundPods, false)
	if err != nil {
		glog.Errorf("etcd failed to retrieve the value for the key %q. Error: %v", s.key, err)
		return
	}
	// Push update. Maybe an empty PodList to allow EtcdSource to be marked as seen
	s.updates <- kubelet.PodUpdate{boundPods.Items, kubelet.SET, kubelet.EtcdSource}
	index, _ := s.helper.ResourceVersioner.ResourceVersion(&boundPods)
	watching := s.helper.Watch(s.key, index)
	for {
		select {
		case event, ok := <-watching.ResultChan():
			if !ok {
				return
			}
			if event.Type == watch.Error {
				glog.Infof("Watch closed (%#v). Reopening.", event.Object)
				watching.Stop()
				return
			}
			pods, err := eventToPods(event)
			if err != nil {
				glog.Errorf("Failed to parse result from etcd watch: %v", err)
				continue
			}

			glog.V(4).Infof("Received state from etcd watch: %+v", pods)
			s.updates <- kubelet.PodUpdate{pods, kubelet.SET, kubelet.EtcdSource}
		}
	}
}

// eventToPods takes a watch.Event object, and turns it into a structured list of pods.
// It returns a list of containers, or an error if one occurs.
func eventToPods(ev watch.Event) ([]api.BoundPod, error) {
	pods := []api.BoundPod{}
	if ev.Object == nil {
		return pods, nil
	}
	boundPods, ok := ev.Object.(*api.BoundPods)
	if !ok {
		return pods, errors.New("unable to parse response as BoundPods")
	}

	for _, pod := range boundPods.Items {
		// Backwards compatibility with old api servers
		// TODO: Remove this after 1.0 release.
		if len(pod.Namespace) == 0 {
			pod.Namespace = api.NamespaceDefault
		}
		pods = append(pods, pod)
	}

	return pods, nil
}
