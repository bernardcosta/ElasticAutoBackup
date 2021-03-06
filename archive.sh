#!/bin/bash
usage(){
cat << EOF
Archiving - automated process for exportind timestamped indices from server to another (archiving)

Usage: ${0##*/} [options] [-iopcft]

   -h                            Display this help and exit
   -i <server>                   Elasticsearch server input
   -o <server>                   Elasticsearch server output
   -p                            flag to port forward es server to localhost
   -c <index name>               Custom archive for only this index
   -f <date from> ex:2021.01.12  date from when to start archiving
   -t <date to>   ex:2021.01.12  date to stop archiving at
   -d                            to delete indices once transfered to archive

EOF
}

check_date() {
  date -f "%Y.%m.%d" -j "$1" >/dev/null 2>&1 && is_valid=true || is_valid=false
  if ! ${is_valid}
    then
      echo "Date $1 is invalid. Use format: %Y.%m.%d"
      exit 1;
  fi
}

check_date_range() {
  if [ $(date -f "%Y.%m.%d" -j ${FROM_DATE} +"%s") -gt $(date -f "%Y.%m.%d" -j ${TO_DATE} +"%s") ]
  then
    echo "\"From\" date (${FROM_DATE}) cannot be more recent than \"To\" date (${TO_DATE})"
    exit 1;
  else
    # Convert to seconds
    to=$(date -f "%Y.%m.%d" -j ${TO_DATE} +"%s")
    from=$(date -f "%Y.%m.%d" -j ${FROM_DATE} +"%s")

    # Get difference between dates in days
    echo "Total days to archive: "$(( ( ($to - $from) / (60 * 60 * 24) )+1 ))
  fi
}

dump() {
  limit=1800
  if [ "$#" -eq 1 ]
    then
      limit="$1"
    fi

  # Checking if index is open. and opens it if closed
  exists=$( curl -s -XGET "http://${INPUT_SERVER}/_cat/indices/${INDEX}")
 #  echo -e $exists
 #  if [[ $exists ]] ; then
 #   open=$( curl -s -X POST "http://${INPUT_SERVER}/${INDEX}/_open?pretty" )
 #   echo -e $open
 # fi


  if [[ $exists == *"index_not_found_exception"* ]] ; then
    echo -e "\nIndex ${INDEX} does not exist. skipping..."
    exit 1 ;
  else
    isClosed=$( curl -s -XGET "http://${INPUT_SERVER}/_cat/indices/${INDEX}" | grep ' close ')
    if [[ $isClosed ]] ; then
      echo -e "Index is Closed ... Opening"
      opened=$( curl -s -X POST "http://${INPUT_SERVER}/${INDEX}/_open?pretty" | grep '"acknowledged" : true')
      if [[ $opened ]] ; then
        echo -e "Opened"
      else
        echo -e "Index did not open.. stopping"
        exit 1;
      fi
    else
      echo -e "Index already open"
    fi
    # echo -e $(curl -s -X GET "http://${INPUT_SERVER}/${INDEX}")

    echo -e "\nDumping ${INDEX}"

    elasticdump \
          --input=http://${INPUT_SERVER}/${INDEX} \
          --output=http://${OUTPUT_SERVER}/${INDEX} \
          --type=mapping\
          --limit=$limit
    elasticdump \
          --input=http://${INPUT_SERVER}/${INDEX} \
          --output=http://${OUTPUT_SERVER}/${INDEX} \
          --type=data\
          --limit=$limit
  fi

}

delete_index(){
  original_size=$( curl -s -XGET "$INPUT_SERVER/$INDEX/_stats" | jq '._all.primaries.docs.count' )
  archived_size=$( curl -s -XGET "$OUTPUT_SERVER/$INDEX/_stats" | jq '._all.primaries.docs.count' )

  if [ $original_size = $archived_size ]
  then
    echo "Deleting Index from Original server"
    curl -XDELETE "$INPUT_SERVER/$INDEX"
    echo -e "\n"

  else
    echo "Warning: Not deleting Index! Backup documents do not match original."
    echo "    - Original docs: $original_size"
    echo "    - Archived docs: $archived_size"
  fi
}

# export .env files
export $(grep -v '^#' .env | xargs)
echo "${NAMES}"

INPUT_SERVER=${DEFAULT}
OUTPUT_SERVER=${ARCHIVE}
PORT_FORWARD=false
DELETE=false
FROM_DATE=$(date -j -v-7d +"%Y.%m.%d" )
TO_DATE=$(date -j -v-7d +"%Y.%m.%d" )
INDEX=""
OPTIND=1
# Resetting OPTIND is necessary if getopts was used previously in the script.
# It is a good idea to make OPTIND local if you process options in a function.
while getopts "hi:o:pc:f:t:d" opt; do
       case $opt in
           h) usage
              exit 0 ;;

           i)  INPUT_SERVER=$OPTARG ;;
           o)  OUTPUT_SERVER=$OPTARG ;;
           p)  PORT_FORWARD=true ;;
           c)  INDEX=$OPTARG ;;
           f)  FROM_DATE=$OPTARG;
                  check_date $FROM_DATE ;;
           t)  TO_DATE=$OPTARG
                  check_date $TO_DATE;;
           d)  DELETE=true;;
           *)  usage >&2
               exit 1 ;;
       esac
   done

if ${PORT_FORWARD}
 then
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
echo "======================================"
date

if  ! [ -z "$INDEX" ]
  then
    echo ${INDEX}
    dump
    if ${DELETE}; then
      delete_index
    fi
  else
    check_date_range
    echo "Archiving dates from: $FROM_DATE to $TO_DATE"

    d=${FROM_DATE}
    IFS=,
    while ! [ $d = $(date -v+1d -f "%Y.%m.%d" -j ${TO_DATE} +"%Y.%m.%d") ]; do
      for name in ${NAMES}; do
        if [[ $name == "partner" ]]; then
          for ss in ${SUFFIX}; do
            INDEX="$name-$d-$ss"
            echo $INDEX
            dump
            if ${DELETE}; then
              delete_index
            fi
          done
        else
          INDEX="$name-$d"
          echo $INDEX
          dump
          if ${DELETE}; then
            delete_index
          fi
        fi
      done

      d=$(date -v+1d -f "%Y.%m.%d" -j $d +"%Y.%m.%d")
    done
  fi
