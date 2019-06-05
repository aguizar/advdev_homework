#!/bin/bash
# Setup Jenkins Project
if [[ "$#" -ne 3 ]]; then
    echo "Usage:"
    echo "  $0 GUID REPO CLUSTER"
    echo "  Example: $0 wkha https://github.com/redhat-gpte-devopsautomation/advdev_homework_template.git na311.openshift.opentlc.com"
    exit 1
fi

GUID=$1
REPO=$2
CLUSTER=$3
echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"
oc project ${GUID}-jenkins

# Set up Jenkins with sufficient resources
oc new-app jenkins-persistent --param MEMORY_LIMIT=2Gi --param VOLUME_CAPACITY=4Gi --param DISABLE_ADMINISTRATIVE_MONITORS=true

# Create custom agent container image with skopeo
oc new-build -D $'FROM docker.io/openshift/jenkins-agent-maven-35-centos7:v3.11\n
      USER root\nRUN yum -y install skopeo && yum clean all\n
      USER 1001' --name=jenkins-agent-appdev

# Make sure that Jenkins is fully up and running before proceeding!
while : ; do
  echo "Checking if Jenkins is Ready..."
  AVAILABLE_REPLICAS=$(oc get dc jenkins -n ${GUID}-jenkins -o=jsonpath='{.status.availableReplicas}')
  if [[ "$AVAILABLE_REPLICAS" == "1" ]]; then
    echo "...Yes. Jenkins is ready."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done

# Create pipeline build config pointing to the ${REPO} with contextDir `openshift-tasks`
curl -H 'Content-Type: application/xml' -d "<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin='workflow-job@2.25'>
  <actions/>
  <description>Tasks Pipeline</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <io.fabric8.jenkins.openshiftsync.BuildConfigProjectProperty plugin='openshift-sync@1.0.27'>
      <uid></uid>
      <namespace></namespace>
      <name></name>
      <resourceVersion></resourceVersion>
    </io.fabric8.jenkins.openshiftsync.BuildConfigProjectProperty>
  </properties>
  <definition class='org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition' plugin='workflow-cps@2.54'>
    <scm class='hudson.plugins.git.GitSCM' plugin='git@3.9.1'>
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>${REPO}</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/master</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class='list'/>
      <extensions/>
    </scm>
    <scriptPath>openshift-tasks/Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>" https://jenkins-${GUID}-jenkins.apps.na311.openshift.opentlc.com/createItem
