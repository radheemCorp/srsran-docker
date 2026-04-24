the updated docker file build was failing so reverted 

```bash
radr@devred:~/tuilm/srsran-docker$  cd /home/radr/tuilm/srsran-docker/srsRAN_Project/docker && docker compose -f docker-compose.yml build
[+] Building 283.1s (18/48)                                                                                                                                                   
 => [internal] load local bake definitions                                                                                                                               0.0s
 => => reading from stdin 1.18kB                                                                                                                                         0.0s
 => [5gc internal] load build definition from Dockerfile                                                                                                                 0.0s
 => => transferring dockerfile: 3.20kB                                                                                                                                   0.0s
 => [gnb internal] load build definition from Dockerfile                                                                                                                 0.0s
 => => transferring dockerfile: 8.31kB                                                                                                                                   0.0s
 => [5gc internal] load metadata for docker.io/library/ubuntu:22.04                                                                                                      0.6s
 => [gnb internal] load metadata for docker.io/anchore/syft:v1.26.1                                                                                                      0.6s
 => [gnb internal] load metadata for docker.io/library/python:3.11.3-alpine                                                                                              0.6s
 => [gnb internal] load metadata for docker.io/library/ubuntu:24.04                                                                                                      0.6s
 => [5gc internal] load .dockerignore                                                                                                                                    0.0s
 => => transferring context: 2B                                                                                                                                          0.0s
 => [gnb internal] load .dockerignore                                                                                                                                    0.0s
 => => transferring context: 2B                                                                                                                                          0.0s
 => CACHED [5gc base 1/8] FROM docker.io/library/ubuntu:22.04@sha256:962f6cadeae0ea6284001009daa4cc9a8c37e75d1f5191cf0eb83fe565b63dd7                                    0.1s
 => => resolve docker.io/library/ubuntu:22.04@sha256:962f6cadeae0ea6284001009daa4cc9a8c37e75d1f5191cf0eb83fe565b63dd7                                                    0.1s
 => [5gc internal] load build context                                                                                                                                    0.0s
 => => transferring context: 179B                                                                                                                                        0.0s
 => CACHED [gnb builder-base 1/3] FROM docker.io/library/ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b                            0.1s
 => => resolve docker.io/library/ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b                                                    0.1s
 => [gnb spdx-merger 1/6] FROM docker.io/library/python:3.11.3-alpine@sha256:4e8e9a59bf1b3ca8e030244bc5f801f23e41e37971907371da21191312087a07                            0.1s
 => => resolve docker.io/library/python:3.11.3-alpine@sha256:4e8e9a59bf1b3ca8e030244bc5f801f23e41e37971907371da21191312087a07                                            0.1s
 => [gnb internal] load build context                                                                                                                                    0.2s
 => => transferring context: 399.59kB                                                                                                                                    0.1s
 => [gnb syft-bin 1/1] FROM docker.io/anchore/syft:v1.26.1@sha256:a29957b223c67ee0503018d9228e74495903b0c6290f9bc6d74d1501680fef85                                       0.1s
 => => resolve docker.io/anchore/syft:v1.26.1@sha256:a29957b223c67ee0503018d9228e74495903b0c6290f9bc6d74d1501680fef85                                                    0.1s
 => ERROR [5gc base 2/8] RUN DEBIAN_FRONTEND=noninteractive apt-get update     && apt install -y software-properties-common     && rm -rf /var/lib/apt/lists/*         282.0s
 => CACHED [gnb builder-base 2/3] ADD . /src                                                                                                                             0.0s
 => CANCELED [gnb builder-base 3/3] RUN /src/docker/scripts/install_dependencies.sh build &&     /src/docker/scripts/install_dependencies.sh extra &&     /src/docker  282.1s
------
 > [5gc base 2/8] RUN DEBIAN_FRONTEND=noninteractive apt-get update     && apt install -y software-properties-common     && rm -rf /var/lib/apt/lists/*:
5.536 Get:1 http://security.ubuntu.com/ubuntu jammy-security InRelease [129 kB]
6.320 Get:2 http://archive.ubuntu.com/ubuntu jammy InRelease [270 kB]
9.823 Get:3 http://security.ubuntu.com/ubuntu jammy-security/universe amd64 Packages [1311 kB]
11.32 Get:4 http://archive.ubuntu.com/ubuntu jammy-updates InRelease [128 kB]
15.31 Get:5 http://archive.ubuntu.com/ubuntu jammy-backports InRelease [127 kB]
27.02 Get:6 http://security.ubuntu.com/ubuntu jammy-security/multiverse amd64 Packages [62.6 kB]
37.43 Get:7 http://security.ubuntu.com/ubuntu jammy-security/main amd64 Packages [3929 kB]
41.12 Get:8 http://security.ubuntu.com/ubuntu jammy-security/restricted amd64 Packages [7015 kB]
78.78 Ign:9 http://archive.ubuntu.com/ubuntu jammy/restricted amd64 Packages
140.9 Ign:10 http://archive.ubuntu.com/ubuntu jammy/multiverse amd64 Packages
144.7 Get:11 http://archive.ubuntu.com/ubuntu jammy/universe amd64 Packages [17.5 MB]
150.1 Get:12 http://archive.ubuntu.com/ubuntu jammy/main amd64 Packages [1792 kB]
157.5 Get:13 http://archive.ubuntu.com/ubuntu jammy-updates/universe amd64 Packages [1623 kB]
161.5 Get:14 http://archive.ubuntu.com/ubuntu jammy-updates/multiverse amd64 Packages [70.9 kB]
167.4 Ign:15 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 Packages
167.4 Get:16 http://archive.ubuntu.com/ubuntu jammy-updates/restricted amd64 Packages [7232 kB]
176.0 Get:17 http://archive.ubuntu.com/ubuntu jammy-backports/main amd64 Packages [84.0 kB]
202.6 Get:18 http://archive.ubuntu.com/ubuntu jammy-backports/universe amd64 Packages [35.9 kB]
237.7 Get:9 http://archive.ubuntu.com/ubuntu jammy/restricted amd64 Packages [164 kB]
244.5 Get:10 http://archive.ubuntu.com/ubuntu jammy/multiverse amd64 Packages [266 kB]
281.3 Get:15 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 Packages [4264 kB]
281.3 Err:15 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 Packages
281.3   File has unexpected size (4263778 != 4263737). Mirror sync in progress? [IP: 91.189.92.22 80]
281.3   Hashes of expected file:
281.3    - Filesize:4263737 [weak]
281.3    - SHA256:2a41dbb065882063d445fb6d397f23dfdad250397dc25d985bb33ae1fde4484d
281.3    - SHA1:bf5e8b952fad7c791116e7c20024ce99b55e76b1 [weak]
281.3    - MD5Sum:a2b7fc4e7b417e4b245c8ef8b2f534b9 [weak]
281.3   Release file created at: Fri, 17 Apr 2026 06:29:54 +0000
281.3 Fetched 41.7 MB in 4min 36s (151 kB/s)
281.3 Reading package lists...
282.0 E: Failed to fetch http://archive.ubuntu.com/ubuntu/dists/jammy-updates/main/binary-amd64/Packages.gz  File has unexpected size (4263778 != 4263737). Mirror sync in progress? [IP: 91.189.92.22 80]
282.0    Hashes of expected file:
282.0     - Filesize:4263737 [weak]
282.0     - SHA256:2a41dbb065882063d445fb6d397f23dfdad250397dc25d985bb33ae1fde4484d
282.0     - SHA1:bf5e8b952fad7c791116e7c20024ce99b55e76b1 [weak]
282.0     - MD5Sum:a2b7fc4e7b417e4b245c8ef8b2f534b9 [weak]
282.0    Release file created at: Fri, 17 Apr 2026 06:29:54 +0000
282.0 E: Some index files failed to download. They have been ignored, or old ones used instead.
------
[+] build 0/2
 ⠙ Image srsran/gnb Building                                                                                                                                            278.5s
 ⠙ Image docker-5gc Building                                                                                                                                            278.5s
Dockerfile:15

--------------------

  14 |     

  15 | >>> RUN DEBIAN_FRONTEND=noninteractive apt-get update \

  16 | >>>     && apt install -y software-properties-common \

  17 | >>>     && rm -rf /var/lib/apt/lists/*

  18 |     

--------------------

target 5gc: failed to solve: process "/bin/sh -c DEBIAN_FRONTEND=noninteractive apt-get update     && apt install -y software-properties-common     && rm -rf /var/lib/apt/lists/*" did not complete successfully: exit code: 100

radr@devred:~/tuilm/srsran-docker/srsRAN_Project/docker$ 
```