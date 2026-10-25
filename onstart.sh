#!/bin/bash
# Vast onstart for the prebuilt image. The controller replaces FS_TOKEN_VALUE before renting.
mkdir -p /work
export FS_TOKEN=FS_TOKEN_VALUE
nohup bash /opt/faceswap/job.sh > /work/job_outer.log 2>&1 &
