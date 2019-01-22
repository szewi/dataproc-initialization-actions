#!/bin/bash
#    Copyright 2019 Google, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
# This initialization action installs Apache Ranger on Dataproc Cluster.

set -euxo pipefail
readonly SOLR_HOME='/opt/solr'
readonly NODE_NAME="$(/usr/share/google/get_metadata_value name)"

gsutil cp gs://polidea-dataproc-utils/ranger/apache-ranger-1.2.0.tar.gz /tmp/apache-ranger-1.2.0.tar.gz

cd /tmp && tar -xf apache-ranger-1.2.0.tar.gz
mkdir -p /usr/lib/ranger && cd /usr/lib/ranger

#ranger-admin
tar -xf /tmp/apache-ranger-1.2.0/target/ranger-1.2.0-admin.tar.gz \
  && ln -s ranger-1.2.0-admin ranger-admin

sed -i 's/^db_root_password=/db_root_password=root-password/' \
  /usr/lib/ranger/ranger-admin/install.properties
sed -i 's/^db_password=/db_password=rangerpass/' \
  /usr/lib/ranger/ranger-admin/install.properties
sed -i 's/^rangerAdmin_password=/rangerAdmin_password=dataproc2019/' \
  /usr/lib/ranger/ranger-admin/install.properties
sed -i 's/^audit_solr_urls=/audit_solr_urls=http:\/\/localhost:8983\/solr\/ranger_audits/' \
  /usr/lib/ranger/ranger-admin/install.properties
sed -i 's/^audit_solr_user=/audit_solr_user=solr/' \
  /usr/lib/ranger/ranger-admin/install.properties

mysql -u root -proot-password -e "CREATE USER 'rangeradmin'@'localhost' IDENTIFIED BY 'rangerpass';"
mysql -u root -proot-password -e "CREATE DATABASE ranger;"
mysql -u root -proot-password -e "GRANT ALL PRIVILEGES ON ranger.* TO 'rangeradmin'@'localhost' ;"

runuser -l solr -c "${SOLR_HOME}/bin/solr create_core -c ranger_audits -d /usr/lib/ranger/ranger-admin/contrib/solr_for_audit_setup/conf -shards 1 -replicationFactor 1"

cd /usr/lib/ranger/ranger-admin && ./setup.sh
ranger-admin start

#ranger-usersync
cd /usr/lib/ranger/
tar -xf /tmp/apache-ranger-1.2.0/target/ranger-1.2.0-usersync.tar.gz \
  && ln -s ranger-1.2.0-usersync ranger-usersync

mkdir -p /var/log/ranger-usersync && chown ranger /var/log/ranger-usersync \
  && chgrp ranger /var/log/ranger-usersync

sed -i 's/^logdir=logs/logdir=\/var\/log\/ranger-usersync/' \
  /usr/lib/ranger/ranger-usersync/install.properties
sed -i 's/^POLICY_MGR_URL =/POLICY_MGR_URL = http:\/\/localhost:6080/' \
  /usr/lib/ranger/ranger-usersync/install.properties

cd /usr/lib/ranger/ranger-usersync && ./setup.sh
ranger-usersync start

#ranger-hdfs-plugin
cd /usr/lib/ranger/
tar -xf /tmp/apache-ranger-1.2.0/target/ranger-1.2.0-hdfs-plugin.tar.gz \
  && ln -s ranger-1.2.0-hdfs-plugin ranger-hdfs-plugin

sed -i 's/^POLICY_MGR_URL=/POLICY_MGR_URL=http:\/\/localhost:6080/' \
  /usr/lib/ranger/ranger-hdfs-plugin/install.properties
sed -i 's/^REPOSITORY_NAME=/REPOSITORY_NAME=hadoopdev/' \
  /usr/lib/ranger/ranger-hdfs-plugin/install.properties
sed -i 's/^XAAUDIT.SOLR.ENABLE=false/XAAUDIT.SOLR.ENABLE=true/' \
  /usr/lib/ranger/ranger-hdfs-plugin/install.properties
sed -i 's/^XAAUDIT.SOLR.URL=NONE/XAAUDIT.SOLR.URL=http:\/\/localhost:8983\/solr\/ranger_audits/' \
  /usr/lib/ranger/ranger-hdfs-plugin/install.properties
sed -i 's/^XAAUDIT.SOLR.USER=NONE/XAAUDIT.SOLR.USER=solr/' \
  /usr/lib/ranger/ranger-hdfs-plugin/install.properties

mkdir -p /usr/lib/ranger/hadoop/etc
ln -s /etc/hadoop/conf /usr/lib/ranger/hadoop/etc/hadoop
mkdir -p /usr/lib/ranger/hadoop/share/hadoop/hdfs/
ln -s /usr/lib/hadoop-hdfs/lib /usr/lib/ranger/hadoop/share/hadoop/hdfs/

cd /usr/lib/ranger/ranger-hdfs-plugin && ./enable-hdfs-plugin.sh

systemctl stop hadoop-hdfs-datanode.service
systemctl stop hadoop-hdfs-secondarynamenode.service
systemctl stop hadoop-hdfs-namenode.service
systemctl start hadoop-hdfs-namenode.service
systemctl start hadoop-hdfs-secondarynamenode.service
systemctl start hadoop-hdfs-datanode.service

cat << EOF > service-hdfs.json
{
    "configs": {
        "password": "dataproc2019",
        "username": "admin",
	    "hadoop.security.authentication": "Simple",
	    "hadoop.security.authorization": "No",
	    "fs.default.name": "hdfs://${NODE_NAME}:8020"
        },
    "description": "Hadoop hdfs service",
    "isEnabled": true,
    "name": "hadoopdev",
    "type": "hdfs",
    "version": 1
}
EOF
curl --user admin:dataproc2019 -H "Content-Type: application/json"  \
   -X POST -d @service-hdfs.json http://localhost:6080/service/public/v2/api/service

#ranger-hive-plugin
cd /usr/lib/ranger/
tar -xf /tmp/apache-ranger-1.2.0/target/ranger-1.2.0-hive-plugin.tar.gz \
  && ln -s ranger-1.2.0-hive-plugin ranger-hive-plugin

sed -i 's/^POLICY_MGR_URL=/POLICY_MGR_URL=http:\/\/localhost:6080/' \
  /usr/lib/ranger/ranger-hive-plugin/install.properties
sed -i 's/^REPOSITORY_NAME=/REPOSITORY_NAME=hivedev/' \
  /usr/lib/ranger/ranger-hive-plugin/install.properties
sed -i 's/^XAAUDIT.SOLR.ENABLE=false/XAAUDIT.SOLR.ENABLE=true/' \
  /usr/lib/ranger/ranger-hive-plugin/install.properties
sed -i 's/^XAAUDIT.SOLR.URL=NONE/XAAUDIT.SOLR.URL=http:\/\/localhost:8983\/solr\/ranger_audits/' \
  /usr/lib/ranger/ranger-hive-plugin/install.properties
sed -i 's/^XAAUDIT.SOLR.USER=NONE/XAAUDIT.SOLR.USER=solr/' \
  /usr/lib/ranger/ranger-hive-plugin/install.properties

mkdir -p hive
ln -s /etc/hive/conf hive
ln -s /usr/lib/hive/lib /usr/lib/ranger/hive

cd /usr/lib/ranger/ranger-hive-plugin && ./enable-hive-plugin.sh
systemctl stop hive-server2.service
systemctl stop hive-metastore.service
systemctl start hive-metastore.service
systemctl start hive-server2.service

cat << EOF > service-hive.json
{
    "configs": {
        "password": "dataproc2019",
        "username": "admin",
        "jdbc.driverClassName" : "org.apache.hive.jdbc.HiveDriver",
        "jdbc.url" : "jdbc:mysql://localhost"
        },
    "description": "Hadoop HIVE service",
    "isEnabled": true,
    "name": "hivedev",
    "type": "hive",
    "version": 1
}
EOF
curl --user admin:dataproc2019 -H "Content-Type: application/json"  \
   -X POST -d @service-hive.json http://localhost:6080/service/public/v2/api/service

#ranger-yarn-plugin
cd /usr/lib/ranger/
tar -xf /tmp/apache-ranger-1.2.0/target/ranger-1.2.0-yarn-plugin.tar.gz \
  && ln -s ranger-1.2.0-yarn-plugin ranger-yarn-plugin

sed -i 's/^POLICY_MGR_URL=/POLICY_MGR_URL=http:\/\/localhost:6080/' \
  /usr/lib/ranger/ranger-yarn-plugin/install.properties
sed -i 's/^REPOSITORY_NAME=/REPOSITORY_NAME=yarndev/' \
  /usr/lib/ranger/ranger-yarn-plugin/install.properties
sed -i 's/^XAAUDIT.SOLR.ENABLE=false/XAAUDIT.SOLR.ENABLE=true/' \
  /usr/lib/ranger/ranger-yarn-plugin/install.properties
sed -i 's/^XAAUDIT.SOLR.URL=NONE/XAAUDIT.SOLR.URL=http:\/\/localhost:8983\/solr\/ranger_audits/' \
  /usr/lib/ranger/ranger-yarn-plugin/install.properties
sed -i 's/^XAAUDIT.SOLR.USER=NONE/XAAUDIT.SOLR.USER=solr/' \
  /usr/lib/ranger/ranger-yarn-plugin/install.properties

cd /usr/lib/ranger/ranger-yarn-plugin && ./enable-yarn-plugin.sh
#systemctl stop hadoop-yarn-nodemanager.service
systemctl stop hadoop-yarn-resourcemanager.service
#systemctl stop hadoop-yarn-timelineserver.service
#systemctl start hadoop-yarn-nodemanager.service
systemctl start hadoop-yarn-resourcemanager.service
#systemctl start hadoop-yarn-timelineserver.service

cat << EOF > service-yarn.json
{
    "configs": {
        "password": "dataproc2019",
        "username": "admin",
	    "yarn.url": "http://${NODE_NAME}:8088"
        },
    "description": "Hadoop YARN service",
    "isEnabled": true,
    "name": "yarndev",
    "type": "yarn",
    "version": 1
}
EOF

curl --user admin:dataproc2019 -H "Content-Type: application/json"  \
   -X POST -d @service-yarn.json http://localhost:6080/service/public/v2/api/service