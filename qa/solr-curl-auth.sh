#!/bin/bash

master_server=$(curl -s https://api.peviitor.ro/devops/solr/)
echo $master_server
curl "${master_server}solr/jobs/select?q=*:*&fl=job_title,job_link,company,hiringOrganization.name,country,remote,jobLocationType,validThrough,city,sursa,id,county&rows=1000000&wt=json&indent=true" -o backup.json
jq '.response.docs' backup.json > cleaned_backup.json

my_server=http://peviitorqa.go.ro:8983
solr_user="solr"
solr_password="SolrRocks"
echo "Cleaning data on $my_server"
curl --user "$solr_user:$solr_password" "${my_server}/solr/jobs/update" \
    -H "Content-Type: text/xml" \
    --data-binary '<delete><query>*:*</query></delete>'

curl --user "$solr_user:$solr_password" "${my_server}/solr/jobs/update" --data '<commit/>'

echo "Uploading data to ${my_server}"
curl --user "$solr_user:$solr_password" "${my_server}/solr/jobs/update?commit=true" \
    -H "Content-Type: application/json" \
    --data-binary @cleaned_backup.json