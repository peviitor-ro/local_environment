# local_environment
Script to build local environment for peviitor project

# Windows script
## Requirements
- GIT installed
- Docker installed

## How to run:
How to run the script:
- Go to the script location
- Double click on the run.bat script

After running the script you can find the peviitor directory here: C:\peviitor

How to ***repopulate SOLR***:
- Double click on the data-migration.bat script

# Linux script
## Requirements
- GIT installed
- Docker installed

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

# Test the environment in the browser:
- http://localhost:8983/
- http://localhost:8080/api/v0/random/
- http://localhost:8080/