# antiope-cloudsploit
Integration of Antiope &amp; CloudSploit for CSPM


## Installation
From your Antiope Local repo:
```bash
git submodule add https://github.com/jchrisfarris/antiope-cloudsploit.git
cd antiope-cloudsploit
git submodule init
git submodule update
```

Copy the SAMPLE Manifest file into the Manifests directory of your antiope-local repo.

Customize the Manifest:


* Create the ECR Repo:
```bash
aws ecr create-repository --repository-name antiope-cloudsploit --image-scanning-configuration scanOnPush=true
```