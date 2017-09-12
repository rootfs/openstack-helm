#!/bin/bash
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
set -ex
: ${WORK_DIR:="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/.."}
source ${WORK_DIR}/tools/gate/vars.sh
source ${WORK_DIR}/tools/gate/funcs/helm.sh
source ${WORK_DIR}/tools/gate/funcs/kube.sh
source ${WORK_DIR}/tools/gate/funcs/network.sh

helm_build

helm search

if [ "x$PVC_BACKEND" == "xceph" ]; then
  kubectl label nodes ceph-osd-device-dev-loop0=enabled --all
  kubectl label nodes ceph-osd-device-dev-loop1=enabled --all

  if [ "x$INTEGRATION" == "xmulti" ]; then
    SUBNET_RANGE="$(find_multi_subnet_range)"
  else
    SUBNET_RANGE=$(find_subnet_range)
  fi

  if [ "x$INTEGRATION" == "xaio" ]; then
    helm install --namespace=ceph ${WORK_DIR}/ceph --name=ceph \
      --set endpoints.identity.namespace=openstack \
      --set endpoints.object_store.namespace=ceph \
      --set endpoints.ceph_mon.namespace=ceph \
      --set ceph.rgw_keystone_auth=${CEPH_RGW_KEYSTONE_ENABLED} \
      --set network.public=${SUBNET_RANGE} \
      --set network.cluster=${SUBNET_RANGE} \
      --set deployment.storage_secrets=true \
      --set deployment.ceph=true \
      --set deployment.rbd_provisioner=true \
      --set deployment.client_secrets=false \
      --set deployment.rgw_keystone_user_and_endpoints=false \
      --set bootstrap.enabled=true \
      --values=${WORK_DIR}/tools/overrides/mvp/ceph.yaml \
      --values=${WORK_DIR}/tools/overrides/mvp/ceph_disks.yaml
  else
    helm install --namespace=ceph ${WORK_DIR}/ceph --name=ceph \
      --set endpoints.identity.namespace=openstack \
      --set endpoints.object_store.namespace=ceph \
      --set endpoints.ceph_mon.namespace=ceph \
      --set ceph.rgw_keystone_auth=${CEPH_RGW_KEYSTONE_ENABLED} \
      --set network.public=${SUBNET_RANGE} \
      --set network.cluster=${SUBNET_RANGE} \
      --set deployment.storage_secrets=true \
      --set deployment.ceph=true \
      --set deployment.rbd_provisioner=true \
      --set deployment.client_secrets=false \
      --set deployment.rgw_keystone_user_and_endpoints=false \
      --set bootstrap.enabled=true
      --set manifests_enabled.client_secrets=false \
      --set bootstrap.enabled=true \
      --values=${WORK_DIR}/tools/overrides/mvp/ceph_disks.yaml
  fi

  kube_wait_for_pods ceph ${SERVICE_LAUNCH_TIMEOUT}

  MON_POD=$(kubectl get pods \
    --namespace=ceph \
    --selector="application=ceph" \
    --selector="component=mon" \
    --no-headers | awk '{ print $1; exit }')

  kubectl exec -n ceph ${MON_POD} -- ceph -s

  helm install --namespace=openstack ${WORK_DIR}/ceph --name=ceph-openstack-config \
    --set endpoints.identity.namespace=openstack \
    --set endpoints.object_store.namespace=ceph \
    --set endpoints.ceph_mon.namespace=ceph \
    --set ceph.rgw_keystone_auth=${CEPH_RGW_KEYSTONE_ENABLED} \
    --set network.public=${SUBNET_RANGE} \
    --set network.cluster=${SUBNET_RANGE} \
    --set deployment.storage_secrets=false \
    --set deployment.ceph=false \
    --set deployment.rbd_provisioner=false \
    --set deployment.client_secrets=true \
    --set deployment.rgw_keystone_user_and_endpoints=false

  kube_wait_for_pods openstack ${SERVICE_LAUNCH_TIMEOUT}
fi

helm install --namespace=openstack ${WORK_DIR}/ingress --name=ingress
if [ "x$INTEGRATION" == "xmulti" ]; then
  helm install --namespace=openstack ${WORK_DIR}/mariadb --name=mariadb
else
  helm install --namespace=openstack ${WORK_DIR}/mariadb --name=mariadb \
    --set=pod.replicas.server=1
fi
helm install --namespace=openstack ${WORK_DIR}/memcached --name=memcached
kube_wait_for_pods openstack ${SERVICE_LAUNCH_TIMEOUT}

helm install --namespace=openstack ${WORK_DIR}/keystone --name=keystone
kube_wait_for_pods openstack ${SERVICE_LAUNCH_TIMEOUT}

if [ "x$OPENSTACK_OBJECT_STORAGE" == "xradosgw" ]; then
  helm install --namespace=openstack ${WORK_DIR}/ceph --name=radosgw-openstack \
    --set endpoints.identity.namespace=openstack \
    --set endpoints.object_store.namespace=ceph \
    --set endpoints.ceph_mon.namespace=ceph \
    --set ceph.rgw_keystone_auth=${CEPH_RGW_KEYSTONE_ENABLED} \
    --set network.public=${SUBNET_RANGE} \
    --set network.cluster=${SUBNET_RANGE} \
    --set deployment.storage_secrets=false \
    --set deployment.ceph=false \
    --set deployment.rbd_provisioner=false \
    --set deployment.client_secrets=false \
    --set deployment.rgw_keystone_user_and_endpoints=true
  kube_wait_for_pods openstack ${SERVICE_LAUNCH_TIMEOUT}
fi

helm install --namespace=openstack ${WORK_DIR}/etcd --name=etcd-rabbitmq
helm install --namespace=openstack ${WORK_DIR}/rabbitmq --name=rabbitmq
helm install --namespace=openstack ${WORK_DIR}/libvirt --name=libvirt
helm install --namespace=openstack ${WORK_DIR}/openvswitch --name=openvswitch
kube_wait_for_pods openstack ${SERVICE_LAUNCH_TIMEOUT}

if [ "x$PVC_BACKEND" == "xceph" ]; then
  helm install --namespace=openstack ${WORK_DIR}/glance --name=glance
else
  helm install --namespace=openstack ${WORK_DIR}/glance --name=glance \
    --values=${WORK_DIR}/tools/overrides/mvp/glance.yaml
fi
kube_wait_for_pods openstack ${SERVICE_LAUNCH_TIMEOUT}
if [ "x$PVC_BACKEND" == "xceph" ]; then
  helm install --namespace=openstack ${WORK_DIR}/nova --name=nova \
    --set=conf.nova.libvirt.nova.conf.virt_type=qemu
else
  helm install --namespace=openstack ${WORK_DIR}/nova --name=nova \
    --values=${WORK_DIR}/tools/overrides/mvp/nova.yaml \
    --set=conf.nova.libvirt.nova.conf.virt_type=qemu
fi
helm install --namespace=openstack ${WORK_DIR}/neutron --name=neutron \
  --values=${WORK_DIR}/tools/overrides/mvp/neutron.yaml
kube_wait_for_pods openstack ${SERVICE_LAUNCH_TIMEOUT}

helm install --namespace=openstack ${WORK_DIR}/heat --name=heat
kube_wait_for_pods openstack ${SERVICE_LAUNCH_TIMEOUT}

if [ "x$INTEGRATION" == "xmulti" ]; then
  if [ "x$PVC_BACKEND" == "xceph" ]; then
    helm install --namespace=openstack ${WORK_DIR}/cinder --name=cinder
  else
    helm install --namespace=openstack ${WORK_DIR}/cinder --name=cinder \
      --values=${WORK_DIR}/tools/overrides/mvp/cinder.yaml
  fi
  helm install --namespace=openstack ${WORK_DIR}/horizon --name=horizon
  kube_wait_for_pods openstack ${SERVICE_LAUNCH_TIMEOUT}

  helm install --namespace=openstack ${WORK_DIR}/barbican --name=barbican
  helm install --namespace=openstack ${WORK_DIR}/magnum --name=magnum
  kube_wait_for_pods openstack ${SERVICE_LAUNCH_TIMEOUT}

  helm install --namespace=openstack ${WORK_DIR}/mistral --name=mistral
  helm install --namespace=openstack ${WORK_DIR}/senlin --name=senlin
  kube_wait_for_pods openstack ${SERVICE_LAUNCH_TIMEOUT}

  helm_test_deployment keystone ${SERVICE_TEST_TIMEOUT}
  helm_test_deployment glance ${SERVICE_TEST_TIMEOUT}
  helm_test_deployment cinder ${SERVICE_TEST_TIMEOUT}
  helm_test_deployment neutron ${SERVICE_TEST_TIMEOUT}
  helm_test_deployment nova ${SERVICE_TEST_TIMEOUT}
  helm_test_deployment barbican ${SERVICE_TEST_TIMEOUT} norally
fi
