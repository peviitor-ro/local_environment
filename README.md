# local_environment
Script to build local environment for peviitor project

# Windows script
## Requirements
- GIT installed
- Docker installed
https://docs.docker.com/desktop/install/windows-install/

## Directories
- linux-local-auth -> local env with SOLR security
- linux-local -> local env without security
- qa -> env for QA

## How to run:
How to run the script:
- Go to the script location
- Double click on the run.bat script

After running the script you can find the peviitor directory here: C:\peviitor

How to ***repopulate SOLR***:
- Double click on the data-migration.bat script

## Add `api.env` file in `api` folder
- Create api.env file with the following structure:

`LOCAL_SERVER = <local server>
PROD_SERVER = <production server>
SOLR_USER = <solr user>
SOLR_PASS = <solr password>`

# Linux script
## Requirements
- GIT installed
- Docker installed
https://docs.docker.com/desktop/install/linux/

## How to run in terminal:
Go to the script location.
```
sudo bash run.sh
```
After running the script you can find the peviitor directory here
```
/home/<your-username>/peviitor
```
For ***API*** changes modify inside peviitor/build/api

For ***FE*** changes modify inside peviitor/search-engine, then rebuild:
```
sudo bash rebuild_fe.sh
```

How ***repopulate SOLR***:
```
sudo bash data-migration.sh
```
How to ***delete docker containers and docker imagines*** that are created for 
local_environment:
```
sudo bash delete_containers_images_local_env.sh
```
## Add `api.env` file in `api` folder
- Create api.env file with the following structure:

`SOLR_SERVER = 172.18.0.10:8983 
SOLR_USER = <solr_user>
SOLR_PASS = <solr_pass>`

# Test the environment in the browser:
- http://localhost:8983/
- http://localhost:8080/api/v0/random/
- http://localhost:8080/
