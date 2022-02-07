domain(){
  if [ "$1" = "bi" ]; then
    echo ${BI};
  elif [ "$1" = "search" ]; then
    echo ${SEARCH};
  elif [ "$1" = "ARCHIVE" ]; then
    echo ${ARCHIVE}
  else echo $1;
  fi
}

usage(){
cat << EOF
elastic2csv - automated process for exporting elastic queries to csv files

Usage: ${0##*/} [options] [-q QUERY] <json file> [-d DOMAIN] <hostname>

   -h                      Display this help and exit
   -i <server>             Elasticsearch server input
   -o <server>             Elasricsearch server output
   -p <true/false>         Whether to port forward or not (useful if done remotely)
   -o <output file>        File or dir to save the csv response
   -i <index name>         Elasticsearch index name or pattern to search from
   -s <server connection>  Remote server name,port, user where elasticsearch is hosted on

EOF
}

check_mandatory_fields(){
  if [[ -z $QUERY_REQUEST  ||  -z $ESDOMAIN || -z $TOTAL_COLS ]]
  then
    echo "ERROR: -q <query> and -d <hostname> -c <columns> are mandatory arguments. See usage: \n";
    usage;
    exit 1;
  fi
}

# export .env files
export $(grep -v '^#' ../.env | xargs)

QUERY_REQUEST=""
ESDOMAIN=""
OUTPUT="./out/finalExportedData.csv"
INDEX=""
TOTAL_COLS=""
OPTIND=1
# Resetting OPTIND is necessary if getopts was used previously in the script.
# It is a good idea to make OPTIND local if you process options in a function.
while getopts "hq:o:i:d:s:c:" opt; do
       case $opt in
           h) usage
              exit 0 ;;
           q)  QUERY_REQUEST=$OPTARG ;;
           o)  OUTPUT=$OPTARG ;;
           i)  INDEX=$OPTARG ;;
           d)  ESDOMAIN=$OPTARG ;;
           s)  SERVER=$OPTARG ;;
           c)  TOTAL_COLS=$OPTARG ;;
           *)  usage >&2
               exit 1 ;;
       esac
   done


check_mandatory_fields;
