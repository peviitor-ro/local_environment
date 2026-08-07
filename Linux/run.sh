#!/bin/bash

RUNSH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================================="
echo "                      Local environment                          "
echo "                          peviitor.ro                            "
echo "================================================================="

sudo apt-get install coreutils -y

#########################################################################
if ! command -v apt >/dev/null 2>&1; then
        echo -e "Sistemul nu face parte din familia Debian"
        exit 1
fi
#########################################################################

# Function to validate the password against the specified policy
validate_password() {
  local password="$1"

  if [ ${#password} -ge 15 ]; then
    return 0
  fi
  if ! [[ $password =~ [a-z] ]]; then
    return 1
  fi
  if ! [[ $password =~ [A-Z] ]]; then
    return 1
  fi
  if ! [[ $password =~ [0-9] ]]; then
    return 1
  fi
  if ! [[ $password =~ [\!\@\#\$\%\^\&\*\_\-\[\]\(\)] ]]; then
    return 1
  fi
  return 0
}

# Prompt for Solr username and password with validation
read -p "Enter the Solr username: " solr_user

while true; do
  read -sp "Enter the Solr password: " solr_password
  echo
  if validate_password "$solr_password"; then
    echo "[~] Password accepted."
    break
  else
    echo "[~] Password must be strong. Try again!"
  fi
done

echo "================================================================="
echo "                        Apache Solr login                        "
echo "                          peviitor.ro                            "
echo "================================================================="

echo "You entered user: $solr_user"

if [ "$SUDO_USER" ]; then
    username=$SUDO_USER
else
    username=$USER
fi

if ! command -v git &> /dev/null; then
    echo "--> installing git"
    sudo apt-get update && sudo apt-get install -y git
fi
if ! command -v git &> /dev/null; then
    echo "ERROR: git could not be installed."
    exit 1
fi
echo "--> git is ready."

if ! command -v unzip &> /dev/null; then
    echo "--> installing unzip"
    sudo apt-get update && sudo apt-get install -y unzip
fi
if ! command -v unzip &> /dev/null; then
    echo "ERROR: unzip could not be installed."
    exit 1
fi
echo "--> unzip is ready."

if ! command -v docker &> /dev/null; then
    echo "--> Docker is not installed. Attempting to install Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo groupadd -f docker
    sudo usermod -aG docker "$username"
fi
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker could not be installed."
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not accessible. Run the script with sudo, or log out/in so the 'docker' group is applied."
    exit 1
fi
echo "--> docker is ready."

echo "Remove existing containers if they exist"
for container in apache-container solr-container data-migration deploy-fe
do
  if [ "$(docker ps -aq -f name=$container)" ]; then
    docker stop "$container"
    docker rm "$container"
  fi
done

network='mynetwork'

if [ ! -z "$(docker network ls | grep $network)" ]; then
  echo "Network $network exists, removing..."
  docker network rm "$network"
fi

echo "Creating network $network..."
docker network create --subnet=172.168.0.0/16 "$network"

PEVITOR_DIR="/home/$username/peviitor"
echo "Cleaning $PEVITOR_DIR ..."
sudo rm -rf "$PEVITOR_DIR"

echo " --> preparing FRONTEND build. this will take a while..."

REPO="peviitor-ro/search-engine"
ASSET_NAME="build.zip"
TARGET_DIR="$PEVITOR_DIR"

DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" \
  | grep "browser_download_url" \
  | grep "$ASSET_NAME" \
  | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
  echo "EROARE: Nu am gasit URL-ul pentru \"$ASSET_NAME\" in ultimul release."
  exit 1
fi

echo "Download URL gasit: $DOWNLOAD_URL"

sudo mkdir -p "$TARGET_DIR"
sudo chmod -R 777 "$TARGET_DIR"

TMP_FILE="/tmp/$ASSET_NAME"

echo "Descarc $ASSET_NAME..."
wget -q --show-progress "$DOWNLOAD_URL" -O "$TMP_FILE"
if [ $? -ne 0 ]; then
  echo "EROARE la descarcare."
  exit 1
fi

echo "Dezarhivez arhiva in: $TARGET_DIR"
unzip -o "$TMP_FILE" -d "$TARGET_DIR"
if [ $? -ne 0 ]; then
  echo "EROARE la dezarhivare."
  exit 1
fi
sudo rm -f "$TMP_FILE"

# Normalizeaza layout-ul build-ului FE: release-urile recente extrag "dist/", nu "build/"
if [ -d "$TARGET_DIR/dist" ] && [ ! -d "$TARGET_DIR/build" ]; then
  echo " --> mut dist/ in build/ pentru layout-ul release-ului"
  sudo mv "$TARGET_DIR/dist" "$TARGET_DIR/build"
fi

echo " --> updating FE hardcoded endpoints to local (http://localhost:8081/api/v1)"
sudo find "$TARGET_DIR/build" -type f \( -name '*.js' -o -name '*.html' \) -exec sed -i \
    's|https://api\.peviitor\.ro/v1/|http://localhost:8081/api/v1/|g; s|http://zimbor\.go\.ro:8091|http://localhost:8081|g' {} +

rm -f "$TARGET_DIR/build/.htaccess"

echo " --> cloning API repo from https://github.com/peviitor-ro/api.git"
git clone --depth 1 --branch master --single-branch https://github.com/peviitor-ro/api.git "$TARGET_DIR/build/api/"

echo " --> updating API endpoints from old domains to solr.peviitor.ro / api.peviitor.ro"
sudo find "$TARGET_DIR/build/api" -type f \( -name '*.php' -o -name '*.json' -o -name '*.env' \) -exec sed -i \
    's|zimbor\.go\.ro|solr.peviitor.ro|g; s|api\.laurentiumarian\.ro|api.peviitor.ro|g; s|api\.peviitor\.ro/api/v[01]|api.peviitor.ro/v1|g; s|api\.peviitor\.ro/v0/|api.peviitor.ro/v1/|g' {} +

echo " --> creating api.env file for API"
cat > "$TARGET_DIR/build/api/api.env" <<EOF
LOCAL_SERVER = 172.168.0.10:8983
PROD_SERVER = solr.peviitor.ro
BACK_SERVER = http://localhost:8081/
SOLR_SERVER = 172.168.0.10:8983
PROTOCOL = http
SOLR_USER = $solr_user
SOLR_PASS = $solr_password
EOF

echo " --> building APACHE WEB SERVER container for FRONTEND, API and SWAGGER-UI. this will take a while..."
docker run --name apache-container --network mynetwork --ip 172.168.0.11  --restart=always -d -p 8081:80 \
    -v "$TARGET_DIR/build:/var/www/html" alexstefan1702/php-apache

# Modificarea URL-ului pentru swagger in containerul lui Alex Stefan
docker exec apache-container sed -i 's|url: "http://localhost:8080/api/v[01]/swagger.json"|url: "http://localhost:8081/api/v1/swagger.json"|g' /var/www/swagger-ui/swagger-initializer.js
docker restart apache-container

#########################################################################
### SOLR SETUP - CORES (standalone mode)                              ###
#########################################################################
CORE_JOB=job
CORE_COMPANY=company
CONTAINER_NAME="solr-container"
SOLR_PORT=8983
SOLR_VOLUME="$PEVITOR_DIR/solr/core/data"
SOLR_SCHEMA="http://localhost:$SOLR_PORT/solr"
SECURITY_FILE="$RUNSH_DIR/security.json"

echo " --> starting Solr container (standalone mode) on port $SOLR_PORT"
sudo mkdir -p "$SOLR_VOLUME"
sudo chmod -R 777 "$SOLR_VOLUME"

# NOTE: Solr 9 defaults to solrcloud mode. --user-managed switches to
# standalone (cores) mode so the admin UI shows the Core Selector, not collections.
docker run --name $CONTAINER_NAME --network mynetwork --ip 172.168.0.10 --restart=always -d \
    -p $SOLR_PORT:$SOLR_PORT \
    -v "$SOLR_VOLUME:/var/solr/data" \
    solr:latest solr-foreground --user-managed

echo "Waiting for Solr to start..."
READY=0
for i in $(seq 1 60); do
  if curl -sf "$SOLR_SCHEMA/admin/info/system" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 2
done
if [ "$READY" -ne 1 ]; then
  echo "ERROR: Solr did not start in time."
  docker logs $CONTAINER_NAME | tail -20
  exit 1
fi
echo " --> Solr is ready."

# Delete ALL collections (this setup uses cores, not collections)
echo " --> deleting all Solr collections"
COLLECTION_LIST=$(docker exec $CONTAINER_NAME curl -s "$SOLR_SCHEMA/admin/collections?action=LIST&wt=json" 2>/dev/null \
  | python3 -c 'import sys,json; print(" ".join(json.load(sys.stdin).get("collections",[])))' 2>/dev/null)
for collection in $COLLECTION_LIST; do
  echo "  deleting collection $collection"
  docker exec $CONTAINER_NAME /opt/solr/bin/solr delete -c "$collection" 2>/dev/null || true
done

# Delete leftover cores, keeping only job & company
echo " --> deleting leftover cores (keeping only job and company)"
CORE_LIST=$(docker exec $CONTAINER_NAME curl -s "$SOLR_SCHEMA/admin/cores?action=STATUS&wt=json" 2>/dev/null \
  | python3 -c 'import sys,json; print(" ".join(json.load(sys.stdin).get("status",{}).keys()))' 2>/dev/null)
for core in $CORE_LIST; do
  if [ "$core" != "job" ] && [ "$core" != "company" ]; then
    echo "  deleting leftover core $core"
    docker exec $CONTAINER_NAME /opt/solr/bin/solr delete -c "$core" 2>/dev/null || true
  fi
done

echo " --> creating Solr cores: $CORE_JOB, $CORE_COMPANY"
for core in $CORE_JOB $CORE_COMPANY; do
  docker exec $CONTAINER_NAME /opt/solr/bin/solr create -c "$core" \
    || echo "WARN: core $core not created (may already exist)"
done

sleep 3

post_to_solr() {
  local url="$1"
  local data="$2"
  local out
  out=$(docker exec $CONTAINER_NAME curl -s -X POST -H "Content-Type: application/json" \
      --data "$data" "$url")
  if ! echo "$out" | grep -q '"status":0'; then
    echo "WARN: POST $url -> $out"
  fi
}

echo " --> adding fields to Solr core $CORE_JOB"
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-field":[{"name":"job_link","type":"text_general","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-field":[{"name":"job_title","type":"text_general","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-field":[{"name":"company","type":"text_general","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-field":[{"name":"company_str","type":"string","stored":true,"indexed":true,"docValues":true,"uninvertible":true,"omitNorms":true,"omitTermFreqAndPositions":true,"sortMissingLast":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-field":[{"name":"hiringOrganization.name","type":"text_general","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-field":[{"name":"hiringOrganization.name_str","type":"string","stored":true,"indexed":true,"docValues":true,"uninvertible":true,"omitNorms":true,"omitTermFreqAndPositions":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-field":[{"name":"country","type":"text_general","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-field":[{"name":"city","type":"text_general","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-field":[{"name":"county","type":"text_general","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'

echo " --> adding copy fields to Solr core $CORE_JOB"
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-copy-field":{"source":"job_link","dest":"_text_"}}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-copy-field":{"source":"job_title","dest":"_text_"}}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-copy-field":{"source":"company","dest":["_text_","company_str","hiringOrganization.name"]}}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-copy-field":{"source":"hiringOrganization.name","dest":"hiringOrganization.name_str"}}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-copy-field":{"source":"country","dest":"_text_"}}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/schema" \
  '{"add-copy-field":{"source":"city","dest":"_text_"}}'

echo " --> adding fields to Solr core $CORE_COMPANY"
post_to_solr "$SOLR_SCHEMA/$CORE_COMPANY/schema" \
  '{"add-field":[{"name":"cui","type":"plongs","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_COMPANY/schema" \
  '{"add-field":[{"name":"stare","type":"text_general","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_COMPANY/schema" \
  '{"add-field":[{"name":"cod_postal","type":"plongs","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_COMPANY/schema" \
  '{"add-field":[{"name":"cod_stare","type":"plongs","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_COMPANY/schema" \
  '{"add-field":[{"name":"sector","type":"plongs","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_COMPANY/schema" \
  '{"add-field":[{"name":"brands","type":"string","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'
post_to_solr "$SOLR_SCHEMA/$CORE_COMPANY/schema" \
  '{"add-field":[{"name":"denumire","type":"text_general","stored":true,"indexed":true,"multiValued":true,"uninvertible":true}]}'

echo " --> adding copy fields to Solr core $CORE_COMPANY"
post_to_solr "$SOLR_SCHEMA/$CORE_COMPANY/schema" \
  '{"add-copy-field":{"source":"sector","dest":"_text_"}}'
post_to_solr "$SOLR_SCHEMA/$CORE_COMPANY/schema" \
  '{"add-copy-field":{"source":"brands","dest":"_text_"}}'
post_to_solr "$SOLR_SCHEMA/$CORE_COMPANY/schema" \
  '{"add-copy-field":{"source":"denumire","dest":"_text_"}}'
post_to_solr "$SOLR_SCHEMA/$CORE_COMPANY/schema" \
  '{"add-copy-field":{"source":"stare","dest":"_text_"}}'
post_to_solr "$SOLR_SCHEMA/$CORE_COMPANY/schema" \
  '{"add-copy-field":{"source":"id","dest":"_text_"}}'

echo " --> adding SuggestComponent to $CORE_JOB core"
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/config" \
  '{"add-searchcomponent":{"name":"suggest","class":"solr.SuggestComponent","suggester":{"name":"jobTitleSuggester","lookupImpl":"FuzzyLookupFactory","dictionaryImpl":"DocumentDictionaryFactory","field":"job_title","suggestAnalyzerFieldType":"text_general","buildOnCommit":"true","buildOnStartup":"false"}}}'
post_to_solr "$SOLR_SCHEMA/$CORE_JOB/config" \
  '{"add-requesthandler":{"name":"/suggest","class":"solr.SearchHandler","startup":"lazy","defaults":{"suggest":"true","suggest.dictionary":"jobTitleSuggester","suggest.count":"10"},"components":["suggest"]}}'

# Create security.json to enable authentication
echo " --> creating security.json at $SECURITY_FILE for Basic Authentication Plugin"
cat <<EOF > "$SECURITY_FILE"
{
"authentication":{
   "blockUnknown": true,
   "class":"solr.BasicAuthPlugin",
   "credentials":{"solr":"IV0EHq1OnNrj6gvRCwvFwTrZ1+z1oBbnQdiVC3otuq0= Ndd7LKvVBAaZIF0QAVi1ekCfAJXr1GGfLtRUXhgrF8c="},
   "realm":"My Solr users",
   "forwardCredentials": false
},
"authorization":{
   "class":"solr.RuleBasedAuthorizationPlugin",
   "permissions":[{"name":"security-edit",
      "role":"admin"}],
   "user-role":{"solr":"admin"}
}}
EOF

echo " --> enabling Basic Authentication Plugin"
docker cp "$SECURITY_FILE" $CONTAINER_NAME:/var/solr/data/security.json
docker exec -u root $CONTAINER_NAME chown solr:solr /var/solr/data/security.json 2>/dev/null || true
docker exec -u root $CONTAINER_NAME chmod 600 /var/solr/data/security.json 2>/dev/null || true
docker restart $CONTAINER_NAME
echo " --> $CONTAINER_NAME restarted. Waiting for it to come back..."
for i in $(seq 1 30); do
  if curl -s -o /dev/null -u solr:SolrRocks "$SOLR_SCHEMA/admin/info/system"; then
    echo " --> Solr is back up."
    break
  fi
  sleep 2
done

echo "No credentials (should be 401):"
curl -s -o /dev/null -w "  HTTP %{http_code}\n" "$SOLR_SCHEMA/admin/info/system"
echo "With credentials (should be 200):"
curl -s -o /dev/null -w "  HTTP %{http_code}\n" -u solr:SolrRocks "$SOLR_SCHEMA/admin/info/system"

new_user="$solr_user"
new_pass="$solr_password"
old_user="solr"
old_pass="SolrRocks"

echo " --> creating user $new_user and assigning admin role"
curl -s --user $old_user:$old_pass "$SOLR_SCHEMA/admin/authentication" \
-H 'Content-type:application/json' \
-d "{\"set-user\": {\"$new_user\":\"$new_pass\"}}"
echo
curl -s --user $old_user:$old_pass "$SOLR_SCHEMA/admin/authorization" \
-H 'Content-type:application/json' \
-d "{\"set-user-role\": {\"$new_user\": [\"admin\"]}}"
echo
curl -s --user $new_user:$new_pass "$SOLR_SCHEMA/admin/authentication" \
-H 'Content-type:application/json' \
-d "{\"delete-user\": [\"$old_user\"]}"
echo

echo " --> verifying cores with the new user"
curl -s -u "$new_user:$new_pass" "$SOLR_SCHEMA/admin/cores" | grep -oE '"(job|company)"' | sort -u || true
echo

#########################################################################
### JAVA + JMETER                                                      ###
#########################################################################
if type -p java; then
    echo "Java is already installed:"
    java -version
else
    echo "Java not found. Installing default JDK..."
    sudo apt-get install -y default-jdk
    java -version
fi

JMETER_HOME=/usr/share/jmeter
REQUIRED_PLUGINS=("jpgc-functions")

is_plugin_installed() {
    local plugin_id="$1"
    if [ -z "$JMETER_HOME" ]; then
        echo "Error: JMETER_HOME is not set" >&2
        return 1
    fi
    if [ ! -f "$JMETER_HOME/bin/PluginsManagerCMD.sh" ]; then
        echo "Error: PluginsManagerCMD.sh not found in $JMETER_HOME/bin" >&2
        return 1
    fi
    if "$JMETER_HOME/bin/PluginsManagerCMD.sh" status 2>/dev/null | grep -q "$plugin_id"; then
        return 0
    else
        return 1
    fi
}

if type -p jmeter; then
    echo "JMeter is already installed:"
    jmeter --version
else
    echo "JMeter not found. Installing..."
    sudo apt-get install -y jmeter libcanberra-gtk3-module
fi

sudo mkdir -p "$JMETER_HOME"
sudo chown -R "$username:$username" "$JMETER_HOME" 2>/dev/null || true
sudo chmod -R a+rX "$JMETER_HOME"

echo " --> downloading apache-jmeter-5.6.3"
wget -q -O /tmp/apache-jmeter-5.6.3.tgz https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-5.6.3.tgz
sudo tar --strip-components=1 -xzf /tmp/apache-jmeter-5.6.3.tgz -C "$JMETER_HOME"
rm -f /tmp/apache-jmeter-5.6.3.tgz

echo " --> installing JMeter plugins manager"
wget -q -O "$JMETER_HOME/lib/ext/plugins-manager.jar" https://jmeter-plugins.org/get/
sudo chmod a+r "$JMETER_HOME/lib/ext/plugins-manager.jar"

wget -q -O "$JMETER_HOME/lib/cmdrunner-2.2.jar" "https://repo1.maven.org/maven2/kg/apc/cmdrunner/2.2/cmdrunner-2.2.jar"
wget -q -O "$JMETER_HOME/lib/cmdrunner-2.3.jar" "https://repo1.maven.org/maven2/kg/apc/cmdrunner/2.3/cmdrunner-2.3.jar"

java -cp "$JMETER_HOME/lib/ext/plugins-manager.jar" org.jmeterplugins.repository.PluginManagerCMDInstaller

for plugin in "${REQUIRED_PLUGINS[@]}"; do
  if is_plugin_installed "$plugin"; then
    echo "Plugin $plugin is already installed."
  else
    echo "Plugin $plugin not found. Installing..."
    "$JMETER_HOME/bin/PluginsManagerCMD.sh" install "$plugin"
  fi
done

"$JMETER_HOME/bin/PluginsManagerCMD.sh" status || true

echo "Installation and validation complete."

#########################################################################
### RUN JMETER TESTS                                                   ###
#########################################################################
echo " --> running populate_local.sh"
LOCAL_USER="$new_user" LOCAL_PASS="$new_pass" bash "$RUNSH_DIR/populate_local.sh" || echo "WARN: populate_local.sh failed"

#########################################################################
### INFO FILE                                                          ###
#########################################################################
FILE="$RUNSH_DIR/informatii_importante.peviitor.txt"
mkdir -p "$(dirname "$FILE")"
cat > "$FILE" <<EOF
=================================================================
                    IMPORTANT INFORMATION
=================================================================

SERVICES
  [~] SOLR:       http://localhost:8983/solr/
  [~] UI:         http://localhost:8081/
  [~] Swagger UI: http://localhost:8081/swagger-ui/

JMETER
  [~] Migrare:  jmeter -n -t ${RUNSH_DIR}/migration.jmx -Duser=${new_user} -Dpass=${new_pass}
  [~] Firme:    jmeter -n -t ${RUNSH_DIR}/firme.jmx    -Duser=${new_user} -Dpass=${new_pass}

CREDENTIALS
  [~] SOLR local user: ${new_user}
  [~] SOLR local pass: ${new_pass}

DOCKER
  [~] List container:     docker ps -a
  [~] List images:        docker images
  [~] Logs container:     docker logs <container_name>
  [~] Inspect container:  docker inspect <container_name>
  [~] IP container:
      - docker inspect <container_name>
      - docker inspect <container_name> | grep IPAddress
  [~] Start container:    docker start <container_name>
  [~] Stop container:     docker stop <container_name>
  [~] Remove container:   docker rm <container_name>

=================================================================
                       Local environment
                          peviitor.ro
=================================================================
EOF

echo " --> saved important information to: $FILE"

clear
echo -e "\n\033[1;34m=================================================================\033[0m"
echo -e "\033[1;34m                    IMPORTANT INFORMATION\033[0m"
echo -e "\033[1;34m=================================================================\033[0m"

echo -e "\n\033[1;36mSERVICES\033[0m"
echo -e "  [~] SOLR:       http://localhost:8983/solr/"
echo -e "  [~] UI:         http://localhost:8081/"
echo -e "  [~] Swagger UI: http://localhost:8081/swagger-ui/"

echo -e "\n\033[1;36mJMETER COMMANDS\033[0m"
echo -e "  [~] Migrare:  \033[1;32mjmeter -n -t ${RUNSH_DIR}/migration.jmx -Duser=${new_user} -Dpass=${new_pass}\033[0m"
echo -e "  [~] Firme:    \033[1;32mjmeter -n -t ${RUNSH_DIR}/firme.jmx    -Duser=${new_user} -Dpass=${new_pass}\033[0m"

echo -e "\n\033[1;36mCREDENTIALS\033[0m"
echo -e "  [~] SOLR local user: ${new_user}"
echo -e "  [~] SOLR local pass: ${new_pass}"

echo -e "\n\033[1;36mDOCKER\033[0m"
echo -e "  [~] List container:     docker ps -a"
echo -e "  [~] List images:        docker images"
echo -e "  [~] Logs container:     docker logs <container_name>"
echo -e "  [~] Inspect container:  docker inspect <container_name>"
echo -e "  [~] IP container:"
echo -e "      - docker inspect <container_name>"
echo -e "      - docker inspect <container_name> | grep IPAddress"
echo -e "  [~] Start container:    docker start <container_name>"
echo -e "  [~] Stop container:     docker stop <container_name>"
echo -e "  [~] Remove container:   docker rm <container_name>"

echo -e "\n\033[1;34m=================================================================\033[0m"
echo -e "\033[1;34m                       Local environment\033[0m"
echo -e "\033[1;34m                          peviitor.ro\033[0m"
echo -e "\033[1;34m=================================================================\033[0m\n"

echo "Script execution completed."

rm -f "$RUNSH_DIR/security.json"
rm -f ./jmeter.log
echo " --> end of script execution  <-- "
