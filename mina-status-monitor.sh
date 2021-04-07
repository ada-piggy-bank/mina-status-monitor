#!/bin/bash
MINA_STATUS=""
STAT=""
ARCHIVESTAT=0
CONNECTINGCOUNT=0
OFFLINECOUNT=0
TOTALCONNECTINGCOUNT=0
TOTALOFFLINECOUNT=0
TOTALSTUCK=0
ARCHIVEDOWNCOUNT=0
TIMEZONE=Asia/Ho_Chi_Minh
GRAPHQL_URI="$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' mina)"
if [[ "$GRAPHQL_URI" != "" ]]; then
  GRAPHQL_URI="http://$GRAPHQL_URI:3085/graphql"
fi

package=`basename "$0"`
while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo "./$package - attempt to monitor the mina daemon"
      echo " "
      echo "./$package [options] [arguments]"
      echo " "
      echo "options:"
      echo "-h, --help                     show brief help"
      echo "-g, --graphql-uri=GRAPHQL-URI  specify the GraphQL endpoint uri of the mina daemon"
      echo "-t, --timezone=TIMEZONE        specify the time zone for the log time"
      exit 0
      ;;
    -g)
      shift
        GRAPHQL_URI=$1
      shift
      ;;
    --graphql-uri*)
        GRAPHQL_URI=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    -t)
      shift
        TIMEZONE=$1
      shift
      ;;
    --timezone*)
        TIMEZONE=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    *)
      break
      ;;
  esac
done

if [[ "$GRAPHQL_URI" == "" ]]; then
    echo "./$package - attempt to monitor the mina daemon"
    echo " "
    echo "./$package [options] [arguments]"
    echo " "
    echo "options:"
    echo "-h, --help                     show brief help"
    echo "-g, --graphql-uri=GRAPHQL-URI  specify the GraphQL endpoint uri of the mina daemon"
    echo "-t, --timezone=TIMEZONE        specify the time zone for the log time"
    exit 0
else
  echo "GraphQL endpoint: $GRAPHQL_URI"
  while :; do
    MINA_STATUS=$(curl $GRAPHQL_URI -s \
    -H 'content-type: application/json' \
    --data-raw '{"operationName":null,"variables":{},"query":"{\n  daemonStatus {\n    syncStatus\n    highestBlockLengthReceived\n    highestUnvalidatedBlockLengthReceived\n  }\n}\n"}' \
    --compressed)

    STAT="$(echo $MINA_STATUS | jq .data.daemonStatus.syncStatus)"
    HIGHESTBLOCK="$(echo $MINA_STATUS | jq .data.daemonStatus.highestBlockLengthReceived)"
    HIGHESTUNVALIDATEDBLOCK="$(echo $MINA_STATUS | jq .data.daemonStatus.highestUnvalidatedBlockLengthReceived)"
    ARCHIVERUNNING=`ps -A | grep coda-archive | wc -l`
    NOW=$(TZ=$TIMEZONE date +'(%Y-%m-%d %H:%M:%S)')

    # Calculate difference between validated and unvalidated blocks
    # If block height is more than 10 block behind, somthing is likely wrong
    DELTAVALIDATED="$(($HIGHESTUNVALIDATEDBLOCK-$HIGHESTBLOCK))"
    echo "$NOW - DELTA VALIDATE: $DELTAVALIDATED"
    if [[ "$DELTAVALIDATED" -gt 10 ]]; then
      echo "Node stuck validated block height delta more than 10 blocks"
      ((TOTALSTUCK++))
      docker restart mina
    fi

    if [[ "$STAT" == "\"SYNCED\"" ]]; then
      OFFLINECOUNT=0
      CONNECTINGCOUNT=0
    fi

    if [[ "$STAT" == "\"CONNECTING\"" ]]; then
      ((CONNECTINGCOUNT++))
      ((TOTALCONNECTINGCOUNT++))
    fi

    if [[ "$STAT" == "\"OFFLINE\"" ]]; then
      ((OFFLINECOUNT++))
      ((TOTALOFFLINECOUNT++))
    fi

    if [[ "$CONNECTINGCOUNT" -gt 1 ]]; then
      docker restart mina
      CONNECTINGCOUNT=0
    fi

    if [[ "$OFFLINECOUNT" -gt 3 ]]; then
      docker restart mina
      OFFLINECOUNT=0
    fi

    if [[ "$ARCHIVERUNNING" -gt 0 ]]; then
      ARCHIVERRUNNING=0
    else
      ((ARCHIVEDOWNCOUNT++))
    fi 
    echo "Status:" $STAT, "Connecting Count, Total:" $CONNECTINGCOUNT $TOTALCONNECTINGCOUNT, "Offline Count, Total:" $OFFLINECOUNT $TOTALOFFLINECOUNT, "Archive Down Count:" $ARCHIVEDOWNCOUNT, "Node Stuck Below Tip:" $TOTALSTUCK
    sleep 300s
    test $? -gt 128 && break;
  done
fi