# Use an official lightweight image with curl and jq
FROM alpine:3.18

# Install required packages
RUN apk add --no-cache curl jq bash

# Create the bash script within the Dockerfile
RUN mkdir -p /usr/local/bin && \
    cat <<'EOF' > /usr/local/solr-curl.sh
#!/bin/bash
master_server=$(curl -s https://api.peviitor.ro/devops/solr/)
echo "Master server: $master_server"
curl "${master_server}solr/jobs/select?q=*:*&fl=job_title,job_link,company,hiringOrganization.name,country,remote,jobLocationType,validThrough,city,sursa,id,county&rows=1000000&wt=json&indent=true" -o backup.json
jq '.response.docs' backup.json > cleaned_backup.json
my_server=http://solr-container:8983  # Use the container name here
echo "Cleaning data on $my_server"
curl "${my_server}/solr/jobs/update" -H "Content-Type: text/xml" --data-binary '<delete><query>*:*</query></delete>'
curl "${my_server}/solr/jobs/update" --data '<commit/>'
echo "Uploading data to ${my_server}"
curl "${my_server}/solr/jobs/update?commit=true" -H "Content-Type: application/json" --data-binary @cleaned_backup.json
EOF

# Make the script executable
RUN chmod +x /usr/local/solr-curl.sh

# Set the script as the entry point
ENTRYPOINT ["/usr/local/solr-curl.sh"]
