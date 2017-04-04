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
set -e

function prep_loopback_device {
  sudo mkdir -p /data/ceph
  sudo dd if=/dev/zero of=/data/ceph/ceph-osd0.img bs=1024 count=3 seek=1073741824
  LOOP=$(sudo losetup -f)
  sudo losetup $LOOP /data/ceph/ceph-osd0.img
  sudo parted $LOOP mklabel gpt
  sudo dd if=/dev/zero of=/data/ceph/ceph-osd1.img bs=1024 count=1 seek=1073741824
  LOOP=$(sudo losetup -f)
  sudo losetup $LOOP /data/ceph/ceph-osd1.img
  sudo parted $LOOP mklabel gpt
  sudo partprobe
}
