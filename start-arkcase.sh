#!/bin/bash

#!/bin/bash
# ============================================================
# Helper functions
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

success() { echo -e "${GREEN}      ✔ $1${NC}"; }
error()   { echo -e "${RED}      ✘ ERROR: $1${NC}"; FAILED=true; }
warning() { echo -e "${YELLOW}      ⚠ WARNING: $1${NC}"; }
info()    { echo -e "${BLUE}      ℹ $1${NC}"; }  
# ============================================================
# ArkCase Startup Script for VS Code
# Replaces all IntelliJ Run Configuration steps
# ============================================================
FAILED=false
TRAINING_DIR="$HOME/training"
TOMCAT_DIR="$TRAINING_DIR/apache-tomcat-9.0.117"
ARKCASE_DIR="$TRAINING_DIR/ArkCase"
DOCKER_SERVICES_DIR="$TRAINING_DIR/ArkCase_Docker_Services_Training"
ARKCASE_TRAINING_DIR="$TRAINING_DIR/ArkCase_Training"
CERT_FILE="$DOCKER_SERVICES_DIR/cert/arkcase.ts"
ENV_FILE="$DOCKER_SERVICES_DIR/env/.env-core"
RUNTIME_SRC="$DOCKER_SERVICES_DIR/minio/arkcase-config/arkcase-runtime.yaml"
#RUNTIME_DEST="$ARKCASE_TRAINING_DIR/acm-standard-applications/war/arkcase/target/arkcase-25.09.01-SNAPSHOT/WEB-INF/classes/acm/acm-config-server-repo"
RUNTIME_DEST="$ARKCASE_TRAINING_DIR/acm-standard-applications/war/arkcase/target/arkcase-25.09.01-SNAPSHOT/WEB-INF/classes/acm/acm-config-server-repo"
WEBAPPS_DIR="$TOMCAT_DIR/webapps"
#WAR_SOURCE="$ARKCASE_TRAINING_DIR/acm-standard-applications/war/arkcase/target/arkcase-25.09.01-SNAPSHOT"
WAR_SOURCE="$TRAINING_DIR/complaint-extension/war/target/extension-arkcase-1.0.0-SNAPSHOT"

echo ""
echo "============================================================"
echo " ArkCase Startup Script"
echo "============================================================"
echo ""

# ------------------------------------------------------------
# STEP 1 - Kill any existing Tomcat/Java processes
# ------------------------------------------------------------
echo ""
echo -e "${BLUE}[1/11] Stopping any existing Tomcat or Java processes...${NC}"
pkill -f catalina 2>/dev/null
pkill -f tomcat 2>/dev/null
pkill -f "arkcase" 2>/dev/null
sleep 3
success "      Done."

if [ "$FAILED" = false ]; then
  success "catalina,tomcat,arkcase are free"
fi
# ------------------------------------------------------------
# STEP 2 - Checking the xml file
# ------------------------------------------------------------

# Check and install xmllint if not installed
echo ""
echo -e "${BLUE}[2/11] Verifying required files and folders...${NC}"

# Check and install xmllint if not installed
info "Checking if xmllint is installed..."
if ! command -v xmllint > /dev/null 2>&1; then
 warning "xmllint is not installed. Installing now..."
 sudo apt-get install -y libxml2-utils > /dev/null 2>&1
 if ! command -v xmllint > /dev/null 2>&1; then
   error "Failed to install xmllint!"
   info "Try manually: sudo apt-get install libxml2-utils"
 fi
 success "xmllint installed successfully."
else
 success "xmllint is already installed."
fi

# Check Tomcat directory
if [ ! -d "$TOMCAT_DIR" ]; then
 error "Tomcat directory not found at: $TOMCAT_DIR"
 info "Make sure Tomcat 9.0.117 is extracted in your training folder."
fi
success "Tomcat found at $TOMCAT_DIR"

# Check Tomcat catalina.sh is executable
if [ ! -x "$TOMCAT_DIR/bin/catalina.sh" ]; then
 error "catalina.sh is not executable!"
 info "Fix it by running: chmod +x $TOMCAT_DIR/bin/catalina.sh"
fi
success "catalina.sh is executable."

# Check server.xml exists and is valid
if [ ! -f "$TOMCAT_DIR/conf/server.xml" ]; then
 error "server.xml not found at $TOMCAT_DIR/conf/server.xml"
 info "Tomcat configuration is missing or corrupted."
fi
if ! xmllint --noout "$TOMCAT_DIR/conf/server.xml" 2>/dev/null; then
 error "server.xml contains a syntax error!"
 info "Run this to see the exact line and error:"
 info "xmllint $TOMCAT_DIR/conf/server.xml"
fi
success "server.xml found and is valid."

# ------------------------------------------------------------
# STEP 3 - Verify required files exist
# ------------------------------------------------------------
#echo "[3/11] Verifying required files and folders..."
echo ""
echo -e "${BLUE} [3/11] Verifying required files and folders...${NC}"
# Check certificate file
if [ ! -f "$CERT_FILE" ]; then
 error "SSL Certificate not found at: $CERT_FILE"
 info "ArkCase cannot start without the SSL certificate."
 info "Make sure ArkCase_Docker_Services_Training is set up correctly."
fi
success "SSL Certificate found."

# Check ENV file
if [ ! -f "$ENV_FILE" ]; then
 error "ENV file not found at: $ENV_FILE"
 info "ArkCase cannot start without the .env-core file."
 info "Make sure ArkCase_Docker_Services_Training is set up correctly."
fi
success "ENV file found."

success "      All required files found."

# ============================================================
# STEP 4 - Check Docker is running
# ============================================================
echo ""
echo -e "${BLUE}[4/11] Checking Docker and required services...${NC}"

if ! docker info > /dev/null 2>&1; then
  error "Docker is not running!"
  info "Attempting to start Docker..."
  sudo service docker start > /dev/null 2>&1
  sleep 5
  if ! docker info > /dev/null 2>&1; then
    error "Failed to start Docker!"
    info "Try manually: sudo service docker start"
  else
    success "Docker started successfully."
  fi
else
  success "Docker is running."
fi



# Define required containers and their expected ports
declare -A CONTAINER_PORTS
CONTAINER_PORTS["mariadb"]="3306"
#CONTAINER_PORTS["mariadb"]="5710"
CONTAINER_PORTS["minio"]="9000"
#CONTAINER_PORTS["solr-standalone"]="443"
#CONTAINER_PORTS["activemq"]="61616"
#CONTAINER_PORTS["samba"]="389"

echo ""
info "Checking required containers..."
echo ""

# Check if any containers are missing and run docker-compose if needed
MISSING_CONTAINERS=false
for CONTAINER in "${!CONTAINER_PORTS[@]}"; do
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    MISSING_CONTAINERS=true
    warning "Container '$CONTAINER' is not running."
  fi
done

# If any containers are missing run docker-compose
if [ "$MISSING_CONTAINERS" = true ]; then
  echo ""
  warning "Some containers are not up and running."
  info "Run docker-compose up in $DOCKER_SERVICES_DIR... to start them"
fi

# Now check each container status and port connectivity
echo ""
info "Verifying all containers..."
echo ""

for CONTAINER in "${!CONTAINER_PORTS[@]}"; do
  PORT=${CONTAINER_PORTS[$CONTAINER]}

  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    STATUS=$(docker ps --format '{{.Names}}\t{{.Status}}' | grep "^${CONTAINER}" | awk '{print $2, $3, $4}')
    PORTS=$(docker ps --format '{{.Names}}\t{{.Ports}}' | grep "^${CONTAINER}" | cut -f2)

    success "Container '$CONTAINER' is running."
    info "  Status : $STATUS"
    info "  Ports  : $PORTS"

    # Test actual port connectivity
    info "  Testing connection to port $PORT..."
    if nc -zw3 localhost $PORT > /dev/null 2>&1; then
      success "  Port $PORT is reachable — connection successful."
    else
      error "  Port $PORT is NOT reachable — connection timed out!"
      info "  Container may still be starting up."
      info "  Try: nc -zv localhost $PORT"
    fi
  else
    error "Container '$CONTAINER' is still NOT running"
    info "  Check logs with: docker logs $CONTAINER"
    info "  Try manually: cd $DOCKER_SERVICES_DIR && docker-compose up -d"
  fi

  echo ""
done

# Final Docker summary
ALL_CONTAINERS_UP=true
for CONTAINER in "${!CONTAINER_PORTS[@]}"; do
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    ALL_CONTAINERS_UP=false
  fi
done

if [ "$ALL_CONTAINERS_UP" = true ]; then
  echo ""
  success "All required Docker containers are running."
else
  echo ""
  error "One or more required Docker containers are still not running!"
  info "Check the errors above and fix them before starting ArkCase."
fi


# ------------------------------------------------------------
# STEP 5 - Checking if port is reachable 
# ------------------------------------------------------------
# Check if expected port is actually reachable
echo ""
echo -e "${BLUE}[5/11] Checking if expected port is reacherble ${NC}"
info "  Testing connection to port $PORT..."
if nc -zw3 localhost $PORT > /dev/null 2>&1; then
  success "  Port $PORT is reachable — connection successful."
else
  error "  Port $PORT is NOT reachable — connection timed out or refused!"
  info "  Container may be starting up or port may be blocked."
  info "  Try: nc -zv localhost $PORT"
fi

# ------------------------------------------------------------
# STEP 6 - Create ~/.arkcase/custom folder
# ------------------------------------------------------------
#echo "[5/11] Creating ~/.arkcase/custom folder..."
echo ""
echo -e "${BLUE}[6/11] Checking ~/.arkcase/custom folder...${NC}"
mkdir -p ~/.arkcase/custom
if [ -d "$HOME/.arkcase/custom" ]; then
 success "~/.arkcase/custom folder exists."
else
 error "Failed to create ~/.arkcase/custom!"
 info "Try manually: mkdir -p ~/.arkcase/custom"
 exit 1
fi

# ------------------------------------------------------------
# STEP 6 - Add acm-arkcase to /etc/hosts if not already there
# ------------------------------------------------------------
echo ""
echo -e "${BLUE}[7/11] Checking /etc/hosts for acm-arkcase entry..."
if grep -q "acm-arkcase" /etc/hosts; then
  success "      acm-arkcase already in /etc/hosts. Skipping."
else
  error "127.0.0.1  acm-arkcase not found in hosts file "
  info " Open /etc/hosts using sudo vi and add 127.0.0.1 acm-arkcase to /etc/hosts..."
fi

# ------------------------------------------------------------
# STEP 7 - Load ENV file variables
# ------------------------------------------------------------
echo ""
echo -e "${BLUE}[8/11] Loading environment variables from .env-core...${NC}"

set -a
source "$ENV_FILE"
set +a
success "      Done. ARKCASE_JDBC_PLATFORM=$ARKCASE_JDBC_PLATFORM"

# ------------------------------------------------------------
# STEP 8 - Set JAVA_OPTS (VM Options from IntelliJ config)
# ------------------------------------------------------------
echo ""
echo -e "${BLUE} [9/11] Setting JAVA_OPTS..."
export JAVA_OPTS="-Djava.net.preferIPv4Stack=true -Duser.timezone=GMT -Djavax.net.ssl.trustStorePassword=password -Djavax.net.ssl.trustStore=$CERT_FILE -Dspring.profiles.active=ldap,custom,local -Xms1024M"
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
export JRE_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
echo "      Done."

# ------------------------------------------------------------
# STEP 9 - Copy Runtime File (Before Launch step from IntelliJ)
# ------------------------------------------------------------
echo ""
echo -e "${BLUE}[10/11] Copying arkcase-runtime.yaml...${NC}"

if [ ! -f "$RUNTIME_SRC" ]; then
  warning "      WARNING: Runtime source file not found at $RUNTIME_SRC"
  echo "      Skipping runtime file copy."
else
  mkdir -p "$RUNTIME_DEST"
  cp -f "$RUNTIME_SRC" "$RUNTIME_DEST"
  success "      Done. Copied to $RUNTIME_DEST"
fi

# ------------------------------------------------------------
# STEP 10 - Deploy WAR to Tomcat webapps
# (Equivalent of arkcase:war exploded with context /arkcase)
# ------------------------------------------------------------
echo ""
echo -e "${BLUE}[11/11] Deploying ArkCase WAR to Tomcat webapps...${NC}"

if [ -d "$WEBAPPS_DIR/arkcase" ]; then
  warning "      Removing old deployment..."
  rm -rf "$WEBAPPS_DIR/arkcase"
fi

if [ -d "$WAR_SOURCE" ]; then
  info "      Copying exploded WAR to webapps/arkcase..."
  cp -r "$WAR_SOURCE" "$WEBAPPS_DIR/arkcase"
  echo "      Done."
  success "ArkCase deployed to $WEBAPPS_DIR/arkcase"
else
  echo "      WARNING: Exploded WAR not found at $WAR_SOURCE"
  echo "      Checking if already deployed..."
  if [ ! -d "$WEBAPPS_DIR/arkcase" ]; then
    error "      ERROR: No WAR found to deploy. Please run Maven build first:"
    echo "             cd $ARKCASE_DIR"
    echo "             mvn clean package -DskipTests"
    exit 1
  else
    echo "      Existing deployment found. Continuing..."
  fi
fi



# ============================================================
# FINAL SUMMARY
# ============================================================
echo ""
echo "============================================================"
echo -e "${BLUE}[FINAL] RESULTS SUMMARY....${NC}"

if [ "$FAILED" = true ]; then
  echo -e "${RED} ✘  Sorry script completed with errors!${NC}"
  echo -e "${RED} Review the errors above, fix them and re-run.${NC}"
  echo "============================================================"
  echo ""
  return 1 2>/dev/null || exit 1
else
  echo -e "${GREEN} ✔ All setup steps completed successfully!${NC}"
  echo "============================================================"
  echo ""
  echo -e "${BLUE} Next Steps:${NC}"
  echo "  3. Watch the OUTPUT tab for logs"
  echo "  4. Once you see 'Server startup in [xxxx] milliseconds'"
  echo "     open your browser and go to:"
  echo ""
  echo -e "${GREEN}     https://localhost:8843/arkcase${NC}"
  echo ""
  echo "     Username: arkcase-admin@arkcase.org"
  echo "     Password: arkcase"
  echo ""
fi

cd "$TOMCAT_DIR/bin"
./catalina.sh run