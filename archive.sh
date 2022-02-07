#!/bin/bash
usage(){
cat << EOF
Archiving - automated process for exportind indices from server to another (archiving)

Usage: ${0##*/} [options] [-iopcft]

   -h                            Display this help and exit
   -i <server>                   Elasticsearch server input
   -o <server>                   Elasticsearch server output
   -p                            flag to port forward es server to localhost
   -c <index name>               Custom archive for only this index
   -f <date from> ex:2021.01.12  date from when to start archiving
   -t <date to>   ex:2021.01.12  date to stop archiving at

EOF
}

# export .env files
export $(grep -v '^#' .env | xargs)

INPUT_SERVER=${DEFAULT}
OUTPUT_SERVER=${ARCHIVE}
PORT_FORWARD=false
FROM_DATE=$(date -j -v-14d +"%Y.%m.%d" )
TO_DATE=$(date -j -v-7d +"%Y.%m.%d" )
INDEX=""
OPTIND=1
# Resetting OPTIND is necessary if getopts was used previously in the script.
# It is a good idea to make OPTIND local if you process options in a function.
while getopts "hi:o:pc:f:t:" opt; do
       case $opt in
           h) usage
              exit 0 ;;

           i)  INPUT_SERVER=$OPTARG ;;
           o)  OUTPUT_SERVER=$OPTARG ;;
           p)  PORT_FORWARD=true ;;
           c)  INDEX=$OPTARG ;;
           f)  FROM_DATE=$OPTARG;;
           t)  TO_DATE=$OPTARG;;
           *)  usage >&2
               exit 1 ;;
       esac
   done
echo "Archiving dates from: $FROM_DATE to $TO_DATE"

if ${PORT_FORWARD} ; then
   # kill ssh tunnel already using this port
   port1=$( ps aux | grep '[9]201:' | awk '{print $2}' )
   port2=$( ps aux | grep '[9]202:' | awk '{print $2}' )

   if  ! [ -z "$port1" ]
    then
      echo "Port 9201 is in use...killing"
      kill $port1
    fi

    if  ! [ -z "$port2" ]
     then
       echo "Port 9202 is in use...killing"
       kill $port2
     fi

   # Port forward remote elasticsearch server
   echo "Port forwarding: $INPUT_SERVER to localhost:9201"
   ssh -f -N -q -L "9201:"$INPUT_SERVER ${SERVER}
   echo "Port forwarding: $OUTPUT_SERVER to localhost:9202"
   ssh -f -N -q -L "9202:"$OUTPUT_SERVER ${SERVER}

   INPUT_SERVER='localhost:9201'
   OUTPUT_SERVER='localhost:9202'
fi

echo "Archiving from server: $INPUT_SERVER"
echo "                   to: $OUTPUT_SERVER"


if  ! [ -z "$INDEX" ]
  then

    elasticdump \
          --input=http://$INPUT_SERVER/$INDEX \
          --output=http://$OUTPUT_SERVER/$INDEX \
          --type=mapping\
          --limit=1800
    elasticdump \
          --input=http://$INPUT_SERVER/$INDEX \
          --output=http://$OUTPUT_SERVER/$INDEX \
          --type=data\
          --limit=1800

    original_size=$( curl -s -XGET "$INPUT_SERVER/$INDEX/_stats" | jq '._all.primaries.docs.count' )
    archived_size=$( curl -s -XGET "$OUTPUT_SERVER/$INDEX/_stats" | jq '._all.primaries.docs.count' )

    if [ $original_size = $archived_size ]
    then
      echo "Deleting Index from Original server"
      curl -XDELETE "$INPUT_SERVER/$INDEX"
    else
      echo "Warning: Not deleting Index! Backup documents do not match original."
      echo "    - Original docs: $original_size"
      echo "    - Archived docs: $archived_size"
    fi
  fi

echo $FROM_DATE
echo $TO_DATE
