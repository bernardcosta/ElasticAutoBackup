# Elasticsearch Archiving

#### Tool to move `elasticsearch` indices from one server to another based on `elasticdump`.

There are two scripts doing the same procedure. One uses GNU `date` (to run on linux). The other uses FreeBSD `date` (to run on mac os)


## Usage

##### To archive a single index

Example:

```
./archiveGNU.sh -d -c index-2019.05.01 -i 12.87.23.159:9200 -o 78.89.8.10:9200
```

- `-d` will delete the index from original server (`-i`) after archiving.
- `-c <index_name>` To specify the index to archive.
- `-o <host:ip>` url of elasticsearch server to output to
- `-i <host:ip>` url of elasticsearch server to input from
  - If `-i` & `-o` are left out, there is a fallback to use `DEFAULT` and `ARCHIVE` environmental variables. These can be set up in a `.env` like so:
  ```
  ARCHIVE=12.45.78.111:9300
  DEFAULT=45.22.122.78:9200
  ```


**Other flags**
- `-p`. If elastic clusters are on remote server, this flag will port forward the input url (`-i`) to `localhost:9201` and the output url (`-o`) to `localhost:9202`.
  - This works by accessing the servers via ssh therefore ssh credentials are required to the server hosting the clusters.
  - For this to work an ssh connection needs to be established. **Set the `SERVER` environment variable like so:**

  ```
  SERVER=user@hostname
  ```

##### To batch archive indices based on date range

If indices are of the form `index-2019.01.01` then the below example will batch archive these indices one after the other:

Example
```
./archiveGNU.sh -d -p -f 2021-05-01 -t 2021-06-01
```
or for FreeBSD (mac) version:
```
./archive.sh -d -p -f 2021.05.01 -t 2021.06.01

```
