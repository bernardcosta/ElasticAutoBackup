#!/bin/bash
usage(){
cat << EOF
Archiving - automated process for exporting bi data to archive

Usage: ${0##*/} [options] [-iopc]

   -h                      Display this help and exit
   -i <server>             Elasticsearch server input
   -o <server>             Elasricsearch server output
   -p <true/false>         Whether to port forward or not (useful if done remotely)
   -c <index name>         Custom archive for only this index

EOF
}

# export .env files
export $(grep -v '^#' ../.env | xargs)

INPUT_SERVER=${Y02}
OUTPUT_SERVER=${ARCHIVE}
PORT_FORWARD=false
INDEX=""
OPTIND=1
# Resetting OPTIND is necessary if getopts was used previously in the script.
# It is a good idea to make OPTIND local if you process options in a function.
while getopts "hi:o:pc:" opt; do
       case $opt in
           h) usage
              exit 0 ;;

           i)  INPUT_SERVER=$OPTARG ;;
           o)  OUTPUT_SERVER=$OPTARG ;;
           p)  PORT_FORWARD=true ;;
           c)  INDEX=$OPTARG ;;
           *)  usage >&2
               exit 1 ;;
       esac
   done

if ${PORT_FORWARD} ; then
   # kill ssh tunnel already using this port
   kill $( ps aux | grep '[9]201:' | awk '{print $2}' )
   kill $( ps aux | grep '[9]202:' | awk '{print $2}' )
   # Port forward remote elasticsearch server
   ssh -f -N -q -L "9201:"$( domain $INPUT_SERVER ) ${SERVER}
   ssh -f -N -q -L "9202:"$( domain $OUTPUT_SERVER ) ${SERVER}
fi
