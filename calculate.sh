#!/bin/bash
set -e

function write_data {
  curl -m 30 -s -i -XPOST $INFLUXDB_ADDRESS/write?db=$db --data-binary "$BATCH_DATA"
}

function fetch_node_capacity {
  data=$(eval $CURL_CMD/api/v1/nodes/$NODE/proxy/metrics)
  TOTAL_CPU_CORES=$(echo "$data" | grep '^machine_cpu_cores' | cut -f2 -d ' ')
  TOTAL_MEMORY=$(echo "$data" | grep '^machine_memory_bytes' | cut -f2 -d ' ')

  if [ -z "$TOTAL_MEMORY" ] || [ -z "$TOTAL_CPU_CORES" ]; then
    DATA_POINT=""
  else
    TOTAL_CPU_CORES=$(echo $[$TOTAL_CPU_CORES * 1000])
    TOTAL_MEMORY=$(printf "%.0f\n" $TOTAL_MEMORY)
    DATA_POINT="stats,node=$NODE cpu_cores=$TOTAL_CPU_CORES,memory_bytes=$TOTAL_MEMORY"
  fi
}

function fetch_cluster_capacity {
  BATCH_DATA=""
  for NODE in `eval $CURL_CMD/api/v1/nodes | grep \"name\" | cut -f4 -d \"`; do
    fetch_node_capacity

    if [ -n "$BATCH_DATA" ]; then
      BATCH_DATA=$(echo -ne "$BATCH_DATA\n$DATA_POINT")
    else
      BATCH_DATA="$DATA_POINT"
    fi
  done

  write_data
}

export BEARER_TOKEN=/var/run/secrets/kubernetes.io/serviceaccount/token

if [ -f $BEARER_TOKEN ]; then
  TOKEN=$(cat $BEARER_TOKEN)
  CURL_CMD="curl -m 30 -s --header \"Authorization: Bearer $TOKEN\" --insecure https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"
elif [ -n "$KUBERNETES_MASTER" ]; then
  CURL_CMD="curl -m 30 -s --insecure http://$KUBERNETES_MASTER"
else
  echo "Unable to find a service token or KUBERNETES_MASTER variable"
  exit -1
fi

echo "$CURL_CMD"

if [ -z ${INFLUXDB_ADDRESS+x} ]; then
  echo "No influxdb endpoint."
  exit -1
fi

db=${INFLUXDB:-k8s_data}
curl -s  http://$INFLUXDB_ADDRESS/query --data-urlencode "q=CREATE DATABASE $db"

while true;
do
  fetch_cluster_capacity
  sleep 300
done
