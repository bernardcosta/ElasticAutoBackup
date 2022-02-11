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
   -f <date from> ex:2021-01-12  date from when to start archiving
   -t <date to>   ex:2021-01-12  date to stop archiving at
   -d                            to delete indices once transfered to archive

EOF
}

check_date() {
  date +"%Y.%m.%d" -d "$1" >/dev/null 2>&1 && is_valid=true || is_valid=false
  if ! ${is_valid}
    then
      echo "Date $1 is invalid. Use format: %Y-%m-%d"
      exit 1;
  fi
}

check_date_range() {
  if [ $(date +"%s" -d ${FROM_DATE} ) -gt $(date +"%s" -d ${TO_DATE}) ]
  then
    echo "\"From\" date (${FROM_DATE}) cannot be more recent than \"To\" date (${TO_DATE})"
    exit 1;
  else
    # Convert to seconds
    to=$(date +"%s" -d ${TO_DATE} )
    from=$(date +"%s" -d ${FROM_DATE} )

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
  curl -s -XPOST "http://${INPUT_SERVER}/${INDEX}/_open"
  echo "\nDumping"

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
}

delete_index(){
  original_size=$( curl -s -XGET "$INPUT_SERVER/$INDEX/_stats" | jq '._all.primaries.docs.count' )
  archived_size=$( curl -s -XGET "$OUTPUT_SERVER/$INDEX/_stats" | jq '._all.primaries.docs.count' )

  if [ $original_size = $archived_size ]
  then
    echo "Deleting Index from Original server"
    curl -XDELETE "$INPUT_SERVER/$INDEX"
    ehcho "\n"
  else
    echo "Warning: Not deleting Index! Backup documents do not match original."
    echo "    - Original docs: $original_size"
    echo "    - Archived docs: $archived_size"
  fi
}

# export .env files
export $(grep -v '^#' .env | xargs)

INPUT_SERVER=${DEFAULT}
OUTPUT_SERVER=${ARCHIVE}
PORT_FORWARD=false
DELETE=false
FROM_DATE=$(date +"%Y.%m.%d" -d "7 days ago"  )
TO_DATE=$(date +"%Y.%m.%d" -d "7 days ago"  )
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
           f)  FROM_DATE=$OPTARG
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

if  ! [ -z "$INDEX" ]
  then
    dump
    if ${DELETE}; then
      delete_index
    fi
  else
    check_date_range
    echo "Archiving dates from: $FROM_DATE to $TO_DATE"
    IFS=,
    d=$( date -d "${FROM_DATE}" +"%Y-%m-%d")
    while ! [ $d = $( date -d "${TO_DATE} + 1 day" +"%Y-%m-%d") ]; do
      for name in ${NAMES}; do
        if [[ $name == "partner" ]]; then
          for ss in ${SUFFIX}; do
            INDEX="$name-$d-$ss"
            dump
            if ${DELETE}; then
              delete_index
            fi
          done
        else
          INDEX="$name-$(date -d $d +%Y.%m.%d)"
          echo ${INDEX}
          dump
          if ${DELETE}; then
            delete_index
          fi
        fi
      done
      d=$(date -d "$d + 1 day" +"%Y-%m-%d" )

    done
  fi
