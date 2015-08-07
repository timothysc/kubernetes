#!/bin/bash

# Copyright 2015 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# TODO: This script is a placeholder atm for several other operations
# which include generating certs, right now we temporarily drop a profile 
# which we can breakout as a separate step if needed. 

# drop a env so users can actually use the tool
echo "export ETCDCTL_PEERS=$3" > /etc/profile.d/etcd.sh

