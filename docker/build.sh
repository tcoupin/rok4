#!/bin/bash

if [ ! -z "$DEBUG" ]
then
  echo "DEBUG MODE ENABLED"
else
  echo "DEBUG MODE DISABLED"
fi

docker kill build > /dev/null 2>&1
docker rm build > /dev/null 2>&1

docker run --rm --privileged multiarch/qemu-user-static:register --reset
docker build --tag rok4-build-env:${ARCH} -f docker/Dockerfile.build.${ARCH} docker
docker run -e DEBUG=$DEBUG -it -d --name build -v $PWD:/rok4 -w /rok4 --rm rok4-build-env:${ARCH} bash

if [ -z "$DEBUG" ]
then
  rm -rf build
fi

mkdir build 
docker exec -u $UID build bash -c 'cd /rok4/build && cmake .. -DBUILD_ROK4=TRUE -DBUILD_BE4=TRUE -DBUILD_DOC=FALSE -DUNITTEST=false -DDEBUG_BUILD=FALSE'
docker exec -u $UID build bash -c "cd /rok4/build && make package"
