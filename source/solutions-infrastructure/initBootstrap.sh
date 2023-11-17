#!/bin/bash

yum update && yum install -y git java-11-amazon-corretto-devel docker nodejs https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm
systemctl start docker
git init
release_tag=$(curl -s https://api.github.com/repos/opensearch-project/opensearch-migrations/releases/latest | jq -r ".tag_name")
git remote add -f origin https://github.com/opensearch-project/opensearch-migrations.git
git config core.sparseCheckout true
echo -e 'deployment\nTrafficCapture\nFetchMigration\nVERSION' > .git/info/sparse-checkout
git checkout tags/$release_tag

cd deployment/cdk/opensearch-service-migration || exit
npm install -g aws-cdk
npm install
./buildDockerImages.sh