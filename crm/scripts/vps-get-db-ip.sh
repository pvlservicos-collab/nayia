#!/bin/bash
CID=$(docker ps --filter name=follemcrm_db --format '{{.ID}}')
docker inspect "$CID" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}}
{{end}}'
